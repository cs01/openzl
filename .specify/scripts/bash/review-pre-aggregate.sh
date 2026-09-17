#!/usr/bin/env bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Pre-aggregate finding files from delivered reviewers for synthesis.
#
# Usage:
#   review-pre-aggregate.sh --attempt-dir <path>
#
# Reads done markers, filters for delivered agents, concatenates finding files
# with per-file provenance headers. Verifies aggregate integrity.
#
# Output (stdout):
#   AGGREGATE_PATH=<path>
#   RAW_FINDING_COUNT=<N>
#
# Exit codes:
#   0 — success
#   2 — usage error
#   3 — infrastructure error (disk, permissions)
#   4 — integrity check failed (reviewer count mismatch)

set -euo pipefail

FINDINGS_SUBDIR="findings"

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/common.sh" ]] || { echo "ERROR: common.sh not found — reinstall with 'speckit init'" >&2; exit 3; }
# shellcheck disable=SC1091  # common.sh is resolved at runtime, not statically
source "$SCRIPT_DIR/common.sh"

usage() {
  echo "Usage: review-pre-aggregate.sh --attempt-dir <path>" >&2
}

command -v jq >/dev/null 2>&1 || { echo "ERROR: jq is required but not found" >&2; exit 3; }

ATTEMPT_DIR=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --attempt-dir)
      [[ $# -ge 2 ]] || { echo "ERROR: --attempt-dir requires a value" >&2; usage; exit 2; }
      ATTEMPT_DIR="$2"; shift 2 ;;
    *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 2 ;;
  esac
done

if [[ -z "$ATTEMPT_DIR" ]]; then
  echo "ERROR: --attempt-dir is required" >&2
  usage
  exit 2
fi

MANIFEST="$ATTEMPT_DIR/manifest.json"
[[ -r "$MANIFEST" ]] || { echo "ERROR: manifest not readable at $MANIFEST" >&2; exit 3; }

MANIFEST_JSON=$(jq -c . "$MANIFEST" 2>/dev/null) || { echo "ERROR: manifest is not valid JSON: $MANIFEST" >&2; exit 3; }
ATTEMPT_ID=$(printf '%s' "$MANIFEST_JSON" | jq -r '.attempt_id // empty')
[[ -n "$ATTEMPT_ID" ]] || { echo "ERROR: manifest missing attempt_id" >&2; exit 3; }

ROSTER_PREFIX=()
ROSTER_ROLE=()
while IFS=$'\t' read -r p r; do
  [[ -n "$p" ]] || continue
  ROSTER_PREFIX+=("$p")
  ROSTER_ROLE+=("$r")
done < <(printf '%s' "$MANIFEST_JSON" | jq -r '.roster[] | [.prefix, .role] | @tsv')

[[ ${#ROSTER_PREFIX[@]} -gt 0 ]] || { echo "ERROR: manifest roster is empty" >&2; exit 3; }

shopt -s nullglob

count_findings() {
  local prefix="$1"
  local n=0
  local f
  for f in "$ATTEMPT_DIR/$FINDINGS_SUBDIR/${prefix}-"*.md; do
    [[ -f "$f" ]] && n=$((n + 1))
  done
  printf '%s' "$n"
}

# Classifies a roster entry using the same five-status vocabulary as
# review-wait.sh / review-plan-synthesis.md. Only "delivered" and
# "delivered (count discrepancy)" are aggregated.
classify_prefix() {
  local prefix="$1"
  local marker_file="$ATTEMPT_DIR/${prefix}.done.json"
  local status="outstanding"
  local m_count=0
  local count_number
  count_number=$(count_findings "$prefix")

  if [[ -f "$marker_file" ]]; then
    local marker_json
    if marker_json=$(jq -c . "$marker_file" 2>/dev/null); then
      local m_attempt m_status
      m_attempt=$(printf '%s' "$marker_json" | jq -r '.attempt_id // empty')
      if [[ "$m_attempt" == "$ATTEMPT_ID" ]]; then
        m_status=$(printf '%s' "$marker_json" | jq -r '.status // empty')
        m_count=$(printf '%s' "$marker_json" | jq -r '.finding_count // 0')
        [[ "$m_count" =~ ^[0-9]+$ ]] || m_count=0
        if [[ "$m_status" == "failed" ]]; then
          status="failed"
        elif [[ "$m_status" == "complete" ]]; then
          if (( count_number == m_count )); then
            status="delivered"
          elif (( count_number > m_count )); then
            status="delivered (count discrepancy)"
          else
            status="outstanding"
          fi
        fi
      fi
    fi
  fi

  printf '%s\t%s\t%s\n' "$status" "$count_number" "$m_count"
}

AGGREGATE_PATH="$ATTEMPT_DIR/findings-aggregated.md"
RAW_FINDING_COUNT=0
AGGREGATE_CONTENT=""
DELIVERED_PREFIXES=()

for i in "${!ROSTER_PREFIX[@]}"; do
  prefix="${ROSTER_PREFIX[$i]}"
  role="${ROSTER_ROLE[$i]}"

  IFS=$'\t' read -r status file_count _marker_count < <(classify_prefix "$prefix")

  case "$status" in
    delivered|"delivered (count discrepancy)") ;;
    *) continue ;;
  esac

  DELIVERED_PREFIXES+=("$prefix")
  RAW_FINDING_COUNT=$((RAW_FINDING_COUNT + file_count))

  AGGREGATE_CONTENT+="## Findings from ${role} (${prefix})"$'\n\n'

  if [[ "$file_count" -eq 0 ]]; then
    AGGREGATE_CONTENT+="(No findings)"$'\n\n'
    continue
  fi

  # Bash pathname expansion yields matches in sorted order, so the finding
  # files are already concatenated in ascending -NNN order.
  for f in "$ATTEMPT_DIR/$FINDINGS_SUBDIR/${prefix}-"*.md; do
    [[ -f "$f" ]] && AGGREGATE_CONTENT+="$(cat "$f")"$'\n\n'
  done
done

if ! printf '%s' "$AGGREGATE_CONTENT" > "$AGGREGATE_PATH"; then
  echo "ERROR: Could not write aggregate to: $AGGREGATE_PATH" >&2
  exit 3
fi

# Integrity check: array-compare aggregate section prefixes against the
# delivered/discrepancy prefixes actually included above. Reads the
# in-memory $AGGREGATE_CONTENT built above, not the file just written, and
# compares one prefix per line (never joined) so distinct sets can never
# collide (e.g. {AB,C} vs {A,BC} joining to the same "ABC"). The uppercase-only
# prefix class is deliberate, not a bug: every real roster prefix is exactly
# two uppercase letters (CR/CV/RK/CC), so a prefix the regex can't
# recover is a malformed roster entry, and failing closed on it is correct.
AGGREGATE_PREFIXES=()
while IFS= read -r line; do
  [[ "$line" =~ ^\#\#\ Findings\ from\ .*\ \(([A-Z]+)\)$ ]] && AGGREGATE_PREFIXES+=("${BASH_REMATCH[1]}")
done <<< "$AGGREGATE_CONTENT"

SORTED_DELIVERED=()
while IFS= read -r line; do
  [[ -n "$line" ]] && SORTED_DELIVERED+=("$line")
done < <(printf '%s\n' "${DELIVERED_PREFIXES[@]:-}" | sort)

SORTED_AGGREGATE=()
while IFS= read -r line; do
  [[ -n "$line" ]] && SORTED_AGGREGATE+=("$line")
done < <(printf '%s\n' "${AGGREGATE_PREFIXES[@]:-}" | sort)

if [[ "${#SORTED_DELIVERED[@]}" -ne "${#SORTED_AGGREGATE[@]}" ]] || \
   [[ "$(printf '%s\n' "${SORTED_DELIVERED[@]:-}")" != "$(printf '%s\n' "${SORTED_AGGREGATE[@]:-}")" ]]; then
  rm -f "$AGGREGATE_PATH"
  echo "ERROR: aggregate integrity check failed — section prefixes do not match delivered roster" >&2
  exit 4
fi

echo "AGGREGATE_PATH=$AGGREGATE_PATH"
echo "RAW_FINDING_COUNT=$RAW_FINDING_COUNT"
exit 0
