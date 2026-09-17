#!/usr/bin/env bash
# Write review gate JSON file from CLI arguments
# Usage: write-review-gate.sh --status <passed|blocked> --gate-type <primary|secondary> --must-address <N> --should-consider <N> --minor <N> --agents-completed <N> [--primary-completed-at <ISO8601>] [--stage <review|verify>] [--partial] [--override] [--resolved] [--panel-size <N>] [--quorum-met <true|false>] [--auto-applied] [--attempt-id <id>]

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/common.sh" ]] || { echo "ERROR: common.sh not found — reinstall with 'speckit init'" >&2; exit 1; }
source "$SCRIPT_DIR/common.sh"

_paths_output=$(get_feature_paths) || { echo "ERROR: Failed to resolve feature directory" >&2; exit 1; }
eval "$_paths_output"
unset _paths_output

# Parse arguments
STATUS=""
GATE_TYPE=""
MUST_ADDRESS=""
SHOULD_CONSIDER=""
MINOR=""
AGENTS_COMPLETED=""
PRIMARY_COMPLETED_AT=""
STAGE="review"
PARTIAL="false"
OVERRIDE="false"
RESOLVED="false"
PANEL_SIZE="0"
QUORUM_MET="true"
AUTO_APPLIED="false"
ATTEMPT_ID=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --status)
      STATUS="$2"
      shift 2
      ;;
    --gate-type)
      GATE_TYPE="$2"
      shift 2
      ;;
    --must-address)
      MUST_ADDRESS="$2"
      shift 2
      ;;
    --should-consider)
      SHOULD_CONSIDER="$2"
      shift 2
      ;;
    --minor)
      MINOR="$2"
      shift 2
      ;;
    --agents-completed)
      AGENTS_COMPLETED="$2"
      shift 2
      ;;
    --primary-completed-at)
      PRIMARY_COMPLETED_AT="$2"
      shift 2
      ;;
    --stage)
      STAGE="$2"
      shift 2
      ;;
    --partial)
      PARTIAL="true"
      shift 1
      ;;
    --override)
      OVERRIDE="true"
      shift 1
      ;;
    --resolved)
      RESOLVED="true"
      shift 1
      ;;
    --panel-size)
      PANEL_SIZE="$2"
      shift 2
      ;;
    --quorum-met)
      QUORUM_MET="$2"
      shift 2
      ;;
    --auto-applied)
      AUTO_APPLIED="true"
      shift 1
      ;;
    --attempt-id)
      ATTEMPT_ID="$2"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      echo "Usage: write-review-gate.sh --status <passed|blocked> --gate-type <primary|secondary> --must-address <N> --should-consider <N> --minor <N> --agents-completed <N> [--primary-completed-at <ISO8601>] [--stage <review|verify>] [--partial] [--override] [--resolved] [--panel-size <N>] [--quorum-met <true|false>] [--auto-applied] [--attempt-id <id>]" >&2
      exit 1
      ;;
  esac
done

if [[ "$STAGE" != "review" && "$STAGE" != "verify" ]]; then
  echo "ERROR: --stage must be 'review' or 'verify'" >&2
  exit 1
fi

# Validate required parameters
if [[ -z "$STATUS" || -z "$GATE_TYPE" || -z "$MUST_ADDRESS" || -z "$SHOULD_CONSIDER" || -z "$MINOR" || -z "$AGENTS_COMPLETED" ]]; then
  echo "ERROR: Missing required parameters" >&2
  echo "Usage: write-review-gate.sh --status <passed|blocked> --gate-type <primary|secondary> --must-address <N> --should-consider <N> --minor <N> --agents-completed <N> [--primary-completed-at <ISO8601>]" >&2
  exit 1
fi

# Validate enums
if [[ "$STATUS" != "passed" && "$STATUS" != "blocked" ]]; then
  echo "ERROR: --status must be 'passed' or 'blocked'" >&2
  exit 1
fi

if [[ "$GATE_TYPE" != "primary" && "$GATE_TYPE" != "secondary" ]]; then
  echo "ERROR: --gate-type must be 'primary' or 'secondary'" >&2
  exit 1
fi

# Validate integers
if ! [[ "$MUST_ADDRESS" =~ ^[0-9]+$ ]] || ! [[ "$SHOULD_CONSIDER" =~ ^[0-9]+$ ]] || ! [[ "$MINOR" =~ ^[0-9]+$ ]] || ! [[ "$AGENTS_COMPLETED" =~ ^[0-9]+$ ]]; then
  echo "ERROR: Count parameters must be non-negative integers" >&2
  exit 1
fi

if ! [[ "$PANEL_SIZE" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --panel-size must be a non-negative integer" >&2
  exit 1
fi

if [[ "$QUORUM_MET" != "true" && "$QUORUM_MET" != "false" ]]; then
  echo "ERROR: --quorum-met must be 'true' or 'false'" >&2
  exit 1
fi

# Validate primary_completed_at constraints
if [[ "$GATE_TYPE" == "secondary" && -z "$PRIMARY_COMPLETED_AT" ]]; then
  echo "ERROR: --primary-completed-at is required for secondary gates (use 'null' if no primary gate exists)" >&2
  exit 1
fi

if [[ "$GATE_TYPE" == "primary" && -n "$PRIMARY_COMPLETED_AT" ]]; then
  echo "ERROR: --primary-completed-at must NOT be provided for primary gates" >&2
  exit 1
fi

# Compute total findings
TOTAL_FINDINGS=$((MUST_ADDRESS + SHOULD_CONSIDER + MINOR))

# Generate timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

# Determine output path — write to feature directory (matching write-pipeline-state.sh)
if [[ "$STAGE" == "verify" ]]; then
  GATE_FILE="$FEATURE_DIR/verify-gate.json"
else
  mkdir -p "$FEATURE_DIR/review"
  GATE_FILE="$FEATURE_DIR/review/review-gate.json"
fi

# Build JSON
if [[ "$GATE_TYPE" == "primary" ]]; then
  PRIMARY_COMPLETED_AT_JSON="null"
elif [[ "$PRIMARY_COMPLETED_AT" == "null" ]]; then
  PRIMARY_COMPLETED_AT_JSON="null"
else
  PRIMARY_COMPLETED_AT_JSON="\"$PRIMARY_COMPLETED_AT\""
fi

# Absent for every caller except one inside an attempt's lifetime: --skip-review
# is the sole legitimately attempt-less writer, and it must get null, not a
# parse error.
if [[ -z "$ATTEMPT_ID" ]]; then
  ATTEMPT_ID_JSON="null"
else
  ATTEMPT_ID_JSON="\"$ATTEMPT_ID\""
fi

if [[ "$STAGE" == "verify" ]]; then
  JSON=$(cat <<EOF
{
  "status": "$STATUS",
  "gate_type": "$GATE_TYPE",
  "must_address_count": $MUST_ADDRESS,
  "should_consider_count": $SHOULD_CONSIDER,
  "minor_count": $MINOR,
  "total_findings": $TOTAL_FINDINGS,
  "agents_completed": $AGENTS_COMPLETED,
  "timestamp": "$TIMESTAMP",
  "primary_completed_at": $PRIMARY_COMPLETED_AT_JSON,
  "partial": $PARTIAL,
  "override": $OVERRIDE,
  "resolved": $RESOLVED,
  "auto_applied": $AUTO_APPLIED
}
EOF
)
else
  JSON=$(cat <<EOF
{
  "status": "$STATUS",
  "gate_type": "$GATE_TYPE",
  "must_address_count": $MUST_ADDRESS,
  "should_consider_count": $SHOULD_CONSIDER,
  "minor_count": $MINOR,
  "total_findings": $TOTAL_FINDINGS,
  "agents_completed": $AGENTS_COMPLETED,
  "timestamp": "$TIMESTAMP",
  "primary_completed_at": $PRIMARY_COMPLETED_AT_JSON,
  "attempt_id": $ATTEMPT_ID_JSON,
  "partial": $PARTIAL,
  "override": $OVERRIDE,
  "resolved": $RESOLVED,
  "auto_applied": $AUTO_APPLIED,
  "panel_size": $PANEL_SIZE,
  "quorum_met": $QUORUM_MET
}
EOF
)
fi

# Validate JSON with jq
if ! echo "$JSON" | jq . > /dev/null 2>&1; then
  echo "ERROR: Generated invalid JSON (jq parse failed)" >&2
  exit 3
fi

# Write to file
if ! echo "$JSON" | jq . > "$GATE_FILE"; then
  echo "ERROR: Failed to write $GATE_FILE" >&2
  exit 2
fi

exit 0
