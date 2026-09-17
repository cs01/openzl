#!/usr/bin/env bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Writes .specify/clarify-gate.json after clarify command completes.
# Usage: write-clarify-gate.sh <questions_asked> <questions_answered> <auto_resolved>

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/common.sh" ]] || { echo "ERROR: common.sh not found — reinstall with 'speckit init'" >&2; exit 1; }
source "$SCRIPT_DIR/common.sh"

_paths_output=$(get_feature_paths) || { echo "ERROR: Failed to resolve feature directory" >&2; exit 1; }
eval "$_paths_output"
unset _paths_output

QUESTIONS_ASKED="${1:-0}"
QUESTIONS_ANSWERED="${2:-0}"
AUTO_RESOLVED="${3:-0}"

# Generate timestamp
TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

GATE_FILE="$FEATURE_DIR/clarify-gate.json"

# Build and write JSON
cat > "$GATE_FILE" <<EOF
{
  "status": "completed",
  "questions_asked": $QUESTIONS_ASKED,
  "questions_answered": $QUESTIONS_ANSWERED,
  "auto_resolved": $AUTO_RESOLVED,
  "timestamp": "$TIMESTAMP"
}
EOF

echo "✓ Clarify gate written to $GATE_FILE"
