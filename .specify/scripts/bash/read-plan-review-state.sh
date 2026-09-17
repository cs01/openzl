#!/usr/bin/env bash

# Reads the plan-review skip-guard inputs out of pipeline-state.jsonl (Meta
# preset). Used by speckit.review-plan.md steps 4b and 4c so the corrupt-history
# rule lives in one testable place instead of five inline jq pipelines.
#
# Usage: bash read-plan-review-state.sh <pipeline-state.jsonl>
#
# Output: six KEY=VALUE lines on stdout, safe to eval:
#   STATE_UNREADABLE, LATEST_SECONDARY_REVIEW_SEQ, LATEST_PLAN_SEQ,
#   PENDING_RECOMMENDATION, AUTO_MODE, SKIP_REVIEW
#
# WHY THIS IS NOT A SLURPED READ
#
# `jq -s` aborts the entire read on one unparseable line, so each query's own
# `//` default never gets a chance to apply and an empty string reaches
# comparisons written for values that are never empty.
#
# WHY IT IS ALSO NOT A "SKIP THE BAD LINES" READ
#
# Every query below takes the *latest* matching record, so dropping an
# unparseable line silently promotes an older one. A truncated newest `plan`
# record hands back the previous plan's `seq` and `skip_review`: the stale
# review looks current and a cleared skip is re-armed. So one unparseable line
# anywhere condemns the whole history rather than degrading it.
#
# THE SAME TRAP, ONE LEVEL DOWN
#
# A record can parse cleanly and still be unusable, and the failure lands in
# the same direction. `LATEST_PLAN_SEQ=0` reads as "the plan is older than the
# review", which *permits* a skip; a recommendation status that is absent or
# oddly shaped drops the pending exemption. So a record that exists but whose
# field is missing or malformed condemns the read too — it does not fall back
# to a stand-in value. Only a genuinely absent record yields 0/"none", which is
# the honest reading of "this stage never ran".
#
# The booleans are the one exception: anything that is not exactly `true`
# becomes `false`, which is already the safe reading (attended, review not
# skipped), so they never condemn.
#
# A missing or empty file is not corruption: it is the ordinary state before
# anything has been recorded. It yields the defaults without the flag.
#
# The whole history is read and classified in a single jq pass. Earlier
# revisions used one process per query plus an awk line count; that re-parsed
# the history five times and let the line-count and record-count halves
# disagree on edge cases (a lone carriage return counted as a record for awk
# but not for jq, producing a false "unreadable").
#
# This script always exits 0 — its exit status carries no meaning, the outcome
# is conveyed solely via the stdout values above.

set -u

STATE_FILE="${1:-}"

emit() {
  echo "STATE_UNREADABLE=$1"
  echo "LATEST_SECONDARY_REVIEW_SEQ=${2:-0}"
  echo "LATEST_PLAN_SEQ=${3:-0}"
  echo "PENDING_RECOMMENDATION=${4:-none}"
  echo "AUTO_MODE=${5:-false}"
  echo "SKIP_REVIEW=${6:-false}"
}

if [[ -z "$STATE_FILE" || ! -f "$STATE_FILE" ]]; then
  emit false
  exit 0
fi

# `!` is the unusable-field sentinel: it fails every shape check below, so a
# record that exists without a usable field can never reach the caller as a
# permissive value.
#
# A parseable line that is not a JSON *object* — an array, string, number, or
# null — is corruption, not a record to skip past. Dropping it quietly would
# once again let `last` return an older record than the history actually holds.
#
# Each value is emitted on its own line rather than as one tab-separated row:
# an empty or absent field in a TSV row shifts every later column left, so a
# single bad value would silently reassign the others. One value per line makes
# a missing field a missing *line*, which the field count below catches.
RESULT=$(jq -Rrn '
  def seqval($r):
    if $r == null then "0"
    elif ($r.seq | type) == "number" and $r.seq == ($r.seq | floor) and $r.seq >= 0
      then ($r.seq | tostring)
    else "!" end;
  def boolval($r; $f):
    if $r == null or $r[$f] == null then "false"
    elif ($r[$f] | type) == "boolean" then ($r[$f] | tostring)
    else "!" end;
  def statusval($r):
    if $r == null then "none"
    elif ($r.status | type) == "string" and ($r.status | test("^[A-Za-z0-9_-]+$"))
      then $r.status
    else "!" end;

  [inputs | sub("\r$"; "") | select(test("[^ \t]"))] as $lines
  | ($lines | map(fromjson? | select(type == "object"))) as $objs
  | if ($objs | length) != ($lines | length) then ["true", "0", "0", "none", "false", "false"]
    else
      ($objs | map(select(.stage == "plan")) | last) as $plan
      | ($objs | map(select(.stage == "review" and .gate_type == "secondary"
                            and .status == "passed")) | last) as $rev
      | ($objs | map(select(.stage == "review-recommendation"
                            and .gate_type == "secondary")) | last) as $rec
      | ["false", seqval($rev), seqval($plan), statusval($rec),
         boolval($plan; "auto_mode"), boolval($plan; "skip_review")]
    end
  | .[]
' "$STATE_FILE" 2>/dev/null)
JQ_STATUS=$?

# An environment fault (jq absent or crashed, file unreadable by permissions)
# and a corrupt history both end at the same conservative output, because there
# is no safe way to proceed in either case. They are not the same problem
# though, and the caller's "pipeline state unreadable" wording points at the
# wrong one — so say which happened on stderr, where it lands in the log
# without becoming part of the command's user-facing report.
if [[ $JQ_STATUS -ne 0 || -z "$RESULT" ]]; then
  if [[ $JQ_STATUS -ne 0 ]]; then
    echo "read-plan-review-state: could not evaluate the history — jq is missing, failed to run, or the file is unreadable. Falling back to safe defaults." >&2
  fi
  emit true
  exit 0
fi

# Read line-wise into an array rather than with `mapfile`, which is bash 4+
# and these scripts must still run under the bash 3.2 shipped on macOS.
FIELDS=()
while IFS= read -r FIELD_LINE; do
  FIELDS+=("$FIELD_LINE")
done <<<"$RESULT"

# Exactly six values, none of them empty. A short read or an empty field means
# the reader did not produce the contract it promises, and guessing which value
# went missing is precisely the mistake that lets a permissive default through.
if [[ ${#FIELDS[@]} -ne 6 ]]; then
  emit true
  exit 0
fi
for FIELD in "${FIELDS[@]}"; do
  if [[ -z "$FIELD" ]]; then
    emit true
    exit 0
  fi
done

UNREADABLE="${FIELDS[0]}"
SEC="${FIELDS[1]}"
PLAN="${FIELDS[2]}"
PEND="${FIELDS[3]}"
AUTO="${FIELDS[4]}"
SKIP="${FIELDS[5]}"

# Re-check every shape in the shell too. jq has already rejected the wrong JSON
# types; this second pass keeps the output eval-safe regardless of how jq
# rendered a value, and it is where the `!` sentinel is finally caught. The
# booleans are checked strictly rather than normalized: a `skip_review` that is
# not a JSON boolean is a record we do not understand, and quietly reading it
# as `false` would be guessing at the very field that turns a review off.
if [[ "$UNREADABLE" != "false" ]] ||
   ! [[ "$SEC" =~ ^[0-9]+$ ]] || ! [[ "$PLAN" =~ ^[0-9]+$ ]] ||
   ! [[ "$PEND" =~ ^[A-Za-z0-9_-]+$ ]] ||
   ! [[ "$AUTO" =~ ^(true|false)$ ]] || ! [[ "$SKIP" =~ ^(true|false)$ ]]; then
  emit true
  exit 0
fi

emit false "$SEC" "$PLAN" "$PEND" "$AUTO" "$SKIP"
exit 0
