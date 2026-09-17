#!/usr/bin/env bash
# Bounded wait over an attempt directory's reviewer (or synthesis) delivery.
#
# This script — not the calling agent — decides whether the ceiling has been
# reached: it compares wall-clock time against a deadline in the attempt
# manifest, so the ceiling survives however many invocations the wait takes.
#
# Usage:
#   review-wait.sh --attempt-dir <path> [--expect reviewers|synthesis] \
#                  [--poll-seconds 15] [--max-invocation-seconds 90] \
#                  [--no-artifact-grace-seconds 300]
#   review-wait.sh --attempt-dir <path> --extend <seconds>

set -euo pipefail

FINDINGS_SUBDIR="findings"
NO_ARTIFACT_REMEDY="The reviewer templates appear to be out of date relative to the review command — no reviewer produced any output. Re-run \`speckit init\` in this project to reinstall, then re-run the review."
EXTEND_CAP_SECONDS=1800

usage() {
  cat >&2 <<'EOF'
Usage: review-wait.sh --attempt-dir <path> [--expect reviewers|synthesis] [--poll-seconds N] [--max-invocation-seconds N] [--no-artifact-grace-seconds N]
       review-wait.sh --attempt-dir <path> --extend <seconds>
EOF
}

ATTEMPT_DIR=""
EXPECT="reviewers"
POLL_SECONDS="15"
MAX_INVOCATION_SECONDS="90"
NO_ARTIFACT_GRACE_SECONDS="300"
EXTEND_SECONDS=""
EXTEND_MODE="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --attempt-dir)
      ATTEMPT_DIR="$2"
      shift 2
      ;;
    --expect)
      EXPECT="$2"
      shift 2
      ;;
    --poll-seconds)
      POLL_SECONDS="$2"
      shift 2
      ;;
    --max-invocation-seconds)
      MAX_INVOCATION_SECONDS="$2"
      shift 2
      ;;
    --no-artifact-grace-seconds)
      NO_ARTIFACT_GRACE_SECONDS="$2"
      shift 2
      ;;
    --extend)
      EXTEND_SECONDS="$2"
      EXTEND_MODE="true"
      shift 2
      ;;
    *)
      echo "ERROR: Unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

if [[ -z "$ATTEMPT_DIR" ]]; then
  echo "ERROR: --attempt-dir is required" >&2
  usage
  exit 2
fi

if [[ "$EXPECT" != "reviewers" && "$EXPECT" != "synthesis" ]]; then
  echo "ERROR: --expect must be 'reviewers' or 'synthesis'" >&2
  usage
  exit 2
fi

for pair in "POLL_SECONDS:$POLL_SECONDS" "MAX_INVOCATION_SECONDS:$MAX_INVOCATION_SECONDS" "NO_ARTIFACT_GRACE_SECONDS:$NO_ARTIFACT_GRACE_SECONDS"; do
  val="${pair#*:}"
  if ! [[ "$val" =~ ^[0-9]+$ ]]; then
    echo "ERROR: ${pair%%:*} must be a non-negative integer" >&2
    usage
    exit 2
  fi
done

if [[ "$EXTEND_MODE" == "true" ]] && ! [[ "$EXTEND_SECONDS" =~ ^[0-9]+$ ]]; then
  echo "ERROR: --extend must be a non-negative integer" >&2
  usage
  exit 2
fi

# jq is the only JSON reader this script uses. Its absence means the manifest
# and every marker are unreadable, so the wait cannot proceed in any mode.
if ! command -v jq >/dev/null 2>&1; then
  printf '%s\n' "$NO_ARTIFACT_REMEDY" >&2
  echo "review_wait_status: infra_error" >&2
  exit 0
fi

MANIFEST="$ATTEMPT_DIR/manifest.json"

if [[ "$EXTEND_MODE" == "true" ]]; then
  if [[ ! -r "$MANIFEST" ]]; then
    echo "ERROR: manifest not readable at $MANIFEST" >&2
    exit 2
  fi
  CURRENT_EXTENDED=$(jq -r '.extended_seconds // empty' "$MANIFEST" 2>/dev/null) || CURRENT_EXTENDED=""
  CURRENT_DEADLINE=$(jq -r '.deadline_epoch // empty' "$MANIFEST" 2>/dev/null) || CURRENT_DEADLINE=""
  if [[ -z "$CURRENT_EXTENDED" || -z "$CURRENT_DEADLINE" ]]; then
    echo "ERROR: manifest missing extended_seconds or deadline_epoch" >&2
    exit 2
  fi
  NEW_EXTENDED=$((CURRENT_EXTENDED + EXTEND_SECONDS))
  if (( NEW_EXTENDED > EXTEND_CAP_SECONDS )); then
    echo "ERROR: extension rejected — cumulative extension would be ${NEW_EXTENDED}s, exceeding the ${EXTEND_CAP_SECONDS}s cap" >&2
    exit 5
  fi
  NEW_DEADLINE=$((CURRENT_DEADLINE + EXTEND_SECONDS))
  if ! jq --argjson d "$NEW_DEADLINE" --argjson e "$NEW_EXTENDED" \
      '.deadline_epoch = $d | .extended_seconds = $e' "$MANIFEST" > "$MANIFEST.tmp"; then
    echo "ERROR: failed to rewrite manifest" >&2
    exit 2
  fi
  mv "$MANIFEST.tmp" "$MANIFEST"
  exit 0
fi

if [[ ! -d "$ATTEMPT_DIR" || ! -r "$MANIFEST" ]]; then
  echo "review_wait_status: infra_error" >&2
  exit 0
fi

if ! MANIFEST_JSON=$(jq -c . "$MANIFEST" 2>/dev/null); then
  echo "review_wait_status: infra_error" >&2
  exit 0
fi

ATTEMPT_ID=$(printf '%s' "$MANIFEST_JSON" | jq -r '.attempt_id // empty')
PANEL_SIZE=$(printf '%s' "$MANIFEST_JSON" | jq -r '.panel_size // empty')
QUORUM_REQUIRED=$(printf '%s' "$MANIFEST_JSON" | jq -r '.quorum_required // empty')
DISPATCHED_AT=$(printf '%s' "$MANIFEST_JSON" | jq -r '.dispatched_at // empty')
DEADLINE_EPOCH=$(printf '%s' "$MANIFEST_JSON" | jq -r '.deadline_epoch // empty')
SYNTHESIS_DEADLINE_EPOCH=$(printf '%s' "$MANIFEST_JSON" | jq -r '.synthesis_deadline_epoch // empty')

if [[ -z "$ATTEMPT_ID" || -z "$PANEL_SIZE" || -z "$QUORUM_REQUIRED" || -z "$DISPATCHED_AT" ]]; then
  echo "review_wait_status: infra_error" >&2
  exit 0
fi

if [[ "$EXPECT" == "reviewers" && -z "$DEADLINE_EPOCH" ]]; then
  echo "review_wait_status: infra_error" >&2
  exit 0
fi

if [[ "$EXPECT" == "synthesis" && -z "$SYNTHESIS_DEADLINE_EPOCH" ]]; then
  echo "review_wait_status: infra_error" >&2
  exit 0
fi

ROSTER_PREFIX=()
ROSTER_ROLE=()
while IFS=$'\t' read -r p r; do
  [[ -n "$p" ]] || continue
  ROSTER_PREFIX+=("$p")
  ROSTER_ROLE+=("$r")
done < <(printf '%s' "$MANIFEST_JSON" | jq -r '.roster[] | [.prefix, .role] | @tsv')

if [[ "$EXPECT" == "reviewers" && ${#ROSTER_PREFIX[@]} -eq 0 ]]; then
  echo "review_wait_status: infra_error" >&2
  exit 0
fi

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

has_any_file() {
  local prefix="$1"
  local f
  for f in "$ATTEMPT_DIR/${prefix}.alive" "$ATTEMPT_DIR/${prefix}.done.json" "$ATTEMPT_DIR/${prefix}.done.json.tmp"; do
    [[ -e "$f" ]] && { printf 'yes'; return; }
  done
  for f in "$ATTEMPT_DIR/$FINDINGS_SUBDIR/${prefix}-"*; do
    [[ -e "$f" ]] && { printf 'yes'; return; }
  done
  printf 'no'
}

# Emits: status \t findings_display \t count_number \t counts_toward_quorum(0|1)
evaluate_prefix() {
  local prefix="$1"
  local marker_file="$ATTEMPT_DIR/${prefix}.done.json"
  local status="outstanding (no output)"
  local findings_display="—"
  local count_number
  count_number=$(count_findings "$prefix")
  local counts=0

  if [[ -f "$marker_file" ]]; then
    local marker_json
    if marker_json=$(jq -c . "$marker_file" 2>/dev/null); then
      local m_attempt
      m_attempt=$(printf '%s' "$marker_json" | jq -r '.attempt_id // empty')
      if [[ "$m_attempt" == "$ATTEMPT_ID" ]]; then
        local m_status m_count
        m_status=$(printf '%s' "$marker_json" | jq -r '.status // empty')
        m_count=$(printf '%s' "$marker_json" | jq -r '.finding_count // 0')
        if [[ "$m_status" == "failed" ]]; then
          status="failed"
          findings_display="$m_count"
          count_number="$m_count"
        elif [[ "$m_status" == "complete" ]]; then
          if (( count_number == m_count )); then
            status="delivered"
            findings_display="$count_number"
          elif (( count_number > m_count )); then
            status="delivered (count discrepancy)"
            findings_display="$count_number (marker claimed $m_count)"
          else
            status="outstanding"
            findings_display="—"
          fi
        fi
      fi
      # A marker with a foreign attempt_id is ignored entirely; status is
      # left at its default and re-derived below from what else exists.
    fi
  fi

  if [[ "$status" == "outstanding (no output)" ]]; then
    if [[ "$(has_any_file "$prefix")" == "yes" ]]; then
      status="outstanding"
    fi
  fi

  case "$status" in
    delivered|"delivered (count discrepancy)") counts=1 ;;
  esac

  printf '%s\t%s\t%s\t%s\n' "$status" "$findings_display" "$count_number" "$counts"
}

write_wait_concluded() {
  local token="$1"
  local concluded_at
  concluded_at=$(date +%s)
  if jq -n --arg attempt_id "$ATTEMPT_ID" --arg expect "$EXPECT" --arg token "$token" \
      --argjson concluded_at "$concluded_at" \
      '{attempt_id: $attempt_id, expect: $expect, token: $token, concluded_at: $concluded_at}' \
      > "$ATTEMPT_DIR/wait-concluded.json.tmp" 2>/dev/null; then
    mv "$ATTEMPT_DIR/wait-concluded.json.tmp" "$ATTEMPT_DIR/wait-concluded.json" || true
  fi
}

emit_token() {
  echo "review_wait_status: $1" >&2
}

NOW=$(date +%s)
START="$NOW"
BUDGET_END=$((START + MAX_INVOCATION_SECONDS))

TOKEN=""
PREV_STATUS=()
for _ in "${ROSTER_PREFIX[@]}"; do
  PREV_STATUS+=("")
done

if [[ "$EXPECT" == "synthesis" ]]; then
  while true; do
    NOW=$(date +%s)
    SYN_FILE="$ATTEMPT_DIR/synthesis.done.json"
    SYN_DELIVERED="false"
    if [[ -f "$SYN_FILE" ]]; then
      if syn_json=$(jq -c . "$SYN_FILE" 2>/dev/null); then
        syn_attempt=$(printf '%s' "$syn_json" | jq -r '.attempt_id // empty')
        [[ "$syn_attempt" == "$ATTEMPT_ID" ]] && SYN_DELIVERED="true"
      fi
    fi

    if [[ "$SYN_DELIVERED" == "true" ]]; then
      TOKEN="all_delivered"
    elif (( NOW >= SYNTHESIS_DEADLINE_EPOCH )); then
      TOKEN="ceiling_reached"
    fi

    if [[ -n "$TOKEN" ]]; then
      break
    fi

    if (( NOW >= BUDGET_END )); then
      TOKEN="in_progress"
      break
    fi

    SLEEP_FOR=$POLL_SECONDS
    REMAINING=$((BUDGET_END - NOW))
    (( REMAINING < SLEEP_FOR )) && SLEEP_FOR=$REMAINING
    (( SLEEP_FOR > 0 )) && sleep "$SLEEP_FOR"
  done

  case "$TOKEN" in
    all_delivered) echo "Synthesis: complete" ;;
    ceiling_reached) echo "Synthesis: ceiling reached, no synthesis marker" ;;
    in_progress) echo "Synthesis: in progress" ;;
  esac

  if [[ "$TOKEN" != "in_progress" ]]; then
    write_wait_concluded "$TOKEN"
  fi
  emit_token "$TOKEN"
  exit 0
fi

# --expect reviewers
DELIVERED_COUNT=0

while true; do
  NOW=$(date +%s)

  ELAPSED_SINCE_DISPATCH=$((NOW - DISPATCHED_AT))
  TOP_LEVEL_EMPTY="true"
  for f in "$ATTEMPT_DIR"/*; do
    [[ -f "$f" ]] || continue
    [[ "$(basename "$f")" == "manifest.json" ]] && continue
    TOP_LEVEL_EMPTY="false"
    break
  done
  FINDINGS_EMPTY="true"
  if [[ -d "$ATTEMPT_DIR/$FINDINGS_SUBDIR" ]]; then
    for f in "$ATTEMPT_DIR/$FINDINGS_SUBDIR"/*; do
      [[ -f "$f" ]] || continue
      FINDINGS_EMPTY="false"
      break
    done
  fi

  if [[ "$TOP_LEVEL_EMPTY" == "true" && "$FINDINGS_EMPTY" == "true" && $ELAPSED_SINCE_DISPATCH -ge $NO_ARTIFACT_GRACE_SECONDS ]]; then
    TOKEN="no_artifacts"
  fi

  STATUS=()
  FINDINGS_DISPLAY=()
  COUNT_NUMBER=()
  COUNTS_FLAG=()
  DELIVERED_COUNT=0
  ALL_TERMINAL="true"
  for prefix in "${ROSTER_PREFIX[@]}"; do
    IFS=$'\t' read -r s fd cn cf < <(evaluate_prefix "$prefix")
    STATUS+=("$s")
    FINDINGS_DISPLAY+=("$fd")
    COUNT_NUMBER+=("$cn")
    COUNTS_FLAG+=("$cf")
    [[ "$cf" == "1" ]] && DELIVERED_COUNT=$((DELIVERED_COUNT + 1))
    case "$s" in
      delivered|"delivered (count discrepancy)"|failed) ;;
      *) ALL_TERMINAL="false" ;;
    esac
  done

  if [[ -z "$TOKEN" && "$ALL_TERMINAL" == "true" ]]; then
    TOKEN="all_delivered"
  fi

  if [[ -z "$TOKEN" ]] && (( NOW >= DEADLINE_EPOCH )); then
    TOKEN="ceiling_reached"
  fi

  # Progress line: reviewers that newly transitioned into a delivered state
  # this cycle, plus the running tally. Recomputed and re-diffed every
  # cycle — nothing here is latched across invocations.
  NEW_DELIVERIES=()
  i=0
  for prefix in "${ROSTER_PREFIX[@]}"; do
    prev="${PREV_STATUS[i]}"
    cur="${STATUS[i]}"
    case "$cur" in
      delivered|"delivered (count discrepancy)")
        case "$prev" in
          delivered|"delivered (count discrepancy)") ;;
          *) NEW_DELIVERIES+=("${ROSTER_ROLE[i]} delivered (${COUNT_NUMBER[i]} findings)") ;;
        esac
        ;;
    esac
    PREV_STATUS[i]="$cur"
    i=$((i + 1))
  done

  if [[ ${#NEW_DELIVERIES[@]} -gt 0 ]]; then
    joined=$(printf '%s, ' "${NEW_DELIVERIES[@]}")
    joined="${joined%, }"
    echo "Review progress: ${joined} — ${DELIVERED_COUNT}/${PANEL_SIZE} delivered"
  else
    echo "Review progress: ${DELIVERED_COUNT}/${PANEL_SIZE} delivered"
  fi

  if [[ -n "$TOKEN" ]]; then
    break
  fi

  if (( NOW >= BUDGET_END )); then
    TOKEN="in_progress"
    break
  fi

  SLEEP_FOR=$POLL_SECONDS
  REMAINING=$((BUDGET_END - NOW))
  (( REMAINING < SLEEP_FOR )) && SLEEP_FOR=$REMAINING
  (( SLEEP_FOR > 0 )) && sleep "$SLEEP_FOR"
done

echo "| Reviewer | Status | Findings |"
echo "|---|---|---|"
i=0
for prefix in "${ROSTER_PREFIX[@]}"; do
  echo "| ${ROSTER_ROLE[i]} | ${STATUS[i]} | ${FINDINGS_DISPLAY[i]} |"
  i=$((i + 1))
done
echo ""
echo "Coverage: ${DELIVERED_COUNT}/${PANEL_SIZE} reviewers delivered."
if (( DELIVERED_COUNT >= QUORUM_REQUIRED )); then
  echo "Quorum: met (${DELIVERED_COUNT} of ${PANEL_SIZE} delivered, ${QUORUM_REQUIRED} required)"
else
  echo "Quorum: not met (${DELIVERED_COUNT} delivered, ${QUORUM_REQUIRED} required)"
fi
if [[ "$TOKEN" == "no_artifacts" ]]; then
  echo ""
  printf '%s\n' "$NO_ARTIFACT_REMEDY"
fi

# in_progress is not a verdict, so it must leave no conclusion marker behind:
# the synthesis step treats this file's presence as proof a wait concluded.
if [[ "$TOKEN" != "in_progress" ]]; then
  write_wait_concluded "$TOKEN"
fi

emit_token "$TOKEN"
exit 0
