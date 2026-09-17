#!/usr/bin/env bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Appends pipeline state entry to feature-scoped pipeline-state.jsonl file.
# Usage: write-pipeline-state.sh <stage> [key=value ...] [--check-only] [--record-refusal]
#
# Exit codes: 0 success, 1 usage/resolution error, 3 the record could not be
# formed, 4 the write was declined (prerequisite unmet), 5 guard-internal
# fault, 6 the record could not be written to the history file.
# Example: write-pipeline-state.sh clarify questions_asked=5 questions_answered=5
# Example: write-pipeline-state.sh review status=blocked gate_type=primary must_address=3

set -euo pipefail

# Resolve this script's own directory so the sourced telemetry emitter is found
# regardless of the caller's cwd. Referenced literally in the terminal safety
# group below; do not indirect through a variable the installer cannot see.
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Catches the common "no initialized workspace at all" case with the same
# fixed message every guarded entry point uses, before any of this script's
# own (differently-worded, differently-caused) error paths below can fire.
# Guarded on existence for defense-in-depth against a partial/stale install.
[[ -f "$SCRIPT_DIR/require-workspace.sh" ]] && { bash "$SCRIPT_DIR/require-workspace.sh" || exit $?; }
[[ -f "$SCRIPT_DIR/common.sh" ]] || { echo "ERROR: common.sh not found — reinstall with 'speckit init'" >&2; exit 1; }
source "$SCRIPT_DIR/common.sh"

_paths_output=$(get_feature_paths) || { echo "ERROR: Failed to resolve feature directory" >&2; exit 1; }
eval "$_paths_output"
unset _paths_output

# --check-only can appear anywhere in the argument list — both
# "write-pipeline-state.sh --check-only <stage>" and
# "write-pipeline-state.sh <stage> ... --check-only" are valid call shapes —
# so it is stripped out before positional parsing rather than assumed to be
# the last token, which would otherwise let it be mistaken for STAGE.
#
# --record-refusal is position-independent for the same reason. It qualifies
# --check-only: the evaluation is unchanged, but a strict-mode refusal also
# appends its refusal record instead of leaving the outcome undocumented. It
# exists so a caller that must decide *before* writing anything of its own can
# still get the durable record a refusal is required to leave, without a second
# evaluation. On its own (no --check-only) it changes nothing — the real write
# path already records refusals.
CHECK_ONLY="false"
RECORD_REFUSAL="false"
_ARGS=()
for _ARG in "$@"; do
  if [[ "$_ARG" == "--check-only" ]]; then
    CHECK_ONLY="true"
  elif [[ "$_ARG" == "--record-refusal" ]]; then
    RECORD_REFUSAL="true"
  else
    _ARGS+=("$_ARG")
  fi
done
set -- "${_ARGS[@]}"
unset _ARGS _ARG

STAGE="${1:-}"
shift || true

if [[ -z "$STAGE" ]]; then
  echo "ERROR: Missing stage parameter" >&2
  echo "Usage: write-pipeline-state.sh <stage> [key=value ...]" >&2
  exit 1
fi

# Determine output path
STATE_FILE="$FEATURE_DIR/pipeline-state.jsonl"

# Parse key=value arguments up front, independent of --check-only and of the
# eventual seq/timestamp (computed later, inside the locked critical section
# for the real write path). STATUS/GATE_TYPE are captured for the reserved
# telemetry channel and prerequisite-chain evaluation respectively (last
# key=value wins); each stays empty when its arg is not forwarded.
# prereq_override_reason is captured separately (not folded into JSON_PARTS
# here) because a successful override also synthesizes a sibling
# prereq_override:true field — both are appended together below.
JSON_PARTS=()
STATUS=""
GATE_TYPE=""
PREREQ_OVERRIDE_REASON=""
PREREQ_OVERRIDE_REASON_SET="false"
for ARG in "$@"; do
  if [[ "$ARG" =~ ^([a-z_]+)=(.+)$ ]]; then
    KEY="${BASH_REMATCH[1]}"
    VALUE="${BASH_REMATCH[2]}"

    if [[ "$KEY" == "status" ]]; then
      STATUS="$VALUE"
    fi
    if [[ "$KEY" == "gate_type" ]]; then
      GATE_TYPE="$VALUE"
    fi
    if [[ "$KEY" == "prereq_override_reason" ]]; then
      PREREQ_OVERRIDE_REASON="$VALUE"
      PREREQ_OVERRIDE_REASON_SET="true"
      continue
    fi

    # Determine if value is numeric or string
    if [[ "$VALUE" =~ ^[0-9]+$ ]]; then
      # Numeric value
      JSON_PARTS+=("\"$KEY\": $VALUE")
    elif [[ "$VALUE" == "true" || "$VALUE" == "false" || "$VALUE" == "null" ]]; then
      # Boolean or null
      JSON_PARTS+=("\"$KEY\": $VALUE")
    else
      # String value - escape quotes
      VALUE_ESCAPED="${VALUE//\"/\\\"}"
      JSON_PARTS+=("\"$KEY\": \"$VALUE_ESCAPED\"")
    fi
  else
    echo "WARNING: Ignoring malformed argument '$ARG' (expected key=value)" >&2
  fi
done

if [[ "$PREREQ_OVERRIDE_REASON_SET" == "true" ]]; then
  JSON_PARTS+=("\"prereq_override\": true")
  PREREQ_OVERRIDE_REASON_ESCAPED="${PREREQ_OVERRIDE_REASON//\"/\\\"}"
  JSON_PARTS+=("\"prereq_override_reason\": \"$PREREQ_OVERRIDE_REASON_ESCAPED\"")
fi

# --- Pipeline-integrity prerequisite chain (pipeline_integrity_enforcement) ---
#
# GUARD_FAULT/REFUSED form a fail-open sentinel split: anything that
# crashes inside the config read or the evaluation itself is a GUARD_FAULT,
# never mistaken for a legitimate REFUSED (unmet-prerequisite) decision.

# Reads ENFORCEMENT_MODE from .specify/config.yml. Returns 0 (mode resolved,
# defaulting to "advisory" on an absent/unreadable file or an
# absent/unrecognized key) or 1 (a genuine read fault — not a clean "file
# missing" or "no match" — which the caller must treat as a GUARD_FAULT,
# never as a silent advisory default).
_read_enforcement_mode() {
  ENFORCEMENT_MODE="advisory"
  local cfg="$REPO_ROOT/.specify/config.yml"
  # Absent or unreadable is a legitimate advisory-selecting case,
  # not a fault — checked before grep runs so grep only ever sees a file it
  # can actually read.
  [[ -f "$cfg" && -r "$cfg" ]] || return 0
  local line grep_rc
  line=$(grep -m1 -E '^pipeline_integrity_enforcement:[[:space:]]*(off|advisory|strict)[[:space:]]*$' "$cfg" 2>/dev/null)
  grep_rc=$?
  # grep exit 1 is a clean "no matching line" (key absent, unrecognized value,
  # or a commented-out example) — the guarantee that a commented line never
  # selects a mode holds because the pattern is anchored with no `#` prefix
  # permitted. Anything else (>1) is a genuine read fault.
  if [[ $grep_rc -gt 1 ]]; then
    return 1
  fi
  if [[ -n "$line" ]]; then
    ENFORCEMENT_MODE=$(printf '%s' "$line" | sed -E 's/^pipeline_integrity_enforcement:[[:space:]]*//; s/[[:space:]]*$//') || return 1
  fi
  return 0
}

# Returns 0 (satisfied), 1 (unsatisfied — UNMET_PREREQ names the missing
# stage), or 2 (evaluation itself faulted, e.g. jq missing/crashed). A record
# whose stage matches but carries record_type:"refusal" is never consulted —
# it documents a prior refusal, not a completion.
#
# Records are parsed one line at a time rather than slurped: `jq -s` fails the
# entire read on a single corrupt line, which would turn one bad record into a
# guard fault over the whole history. `jq -R 'fromjson? // empty'` drops only
# the lines that do not parse and passes the rest through, so a malformed
# record is skipped and evaluation continues over the remainder. A file that
# yields no parseable record at all then produces an empty candidate set, which
# reads as an unsatisfied prerequisite (return 1) — each mode's own
# unmet-prerequisite behaviour applies, rather than the fault path. An absent
# file is an empty history and takes the same unsatisfied return, never the
# fault return.
#
# Unparseable *content* and a broken *evaluator* are deliberately kept apart.
# The two jq stages are therefore run as separate commands with their exit
# statuses inspected individually, rather than as one pipeline whose combined
# status cannot distinguish them: `fromjson? // empty` exits 0 on a file whose
# every line is corrupt (it simply emits nothing), so a non-zero status from
# either stage means jq itself is missing or failed to run — an environmental
# fault, not a statement about the history's contents. Collapsing that onto
# return 1 would report "prerequisite unmet" for a guard that never actually
# evaluated, naming a stage the user has in fact completed.
_stage_history_satisfied() {
  local pstage="$1" pgate="$2"
  [[ -f "$STATE_FILE" ]] || return 1
  local records result
  records=$(jq -R 'fromjson? // empty' "$STATE_FILE" 2>/dev/null) || return 2
  result=$(printf '%s' "$records" | jq -s --arg s "$pstage" --arg g "$pgate" '
      any(.[]; .stage == $s
        and ((.record_type // "") != "refusal")
        and (($g == "") or ((.gate_type // "") == $g))
        and ((.status // "") as $st | ($st == "" or (["blocked","abandoned","pending"] | index($st) | not))))
    ' 2>/dev/null) || return 2
  [[ "$result" == "true" ]] && return 0
  return 1
}

# The six-stage prerequisite chain.
# Returns 0 (satisfied or out-of-chain), 1 (unsatisfied), or 2 (fault).
_evaluate_prerequisites() {
  local stage="$1" gate_type="$2"
  local -a prereqs=()
  case "$stage" in
    specify) return 0 ;;
    plan) prereqs=("specify:") ;;
    review)
      # Only a secondary-gate review write participates in the chain: it
      # requires the plan stage, and only when gate_type == secondary. A
      # primary-gate or gate_type-absent write is out-of-chain.
      [[ "$gate_type" == "secondary" ]] || return 0
      prereqs=("plan:")
      ;;
    tasks) prereqs=("plan:" "review:secondary") ;;
    implement) prereqs=("tasks:") ;;
    verify) prereqs=("implement:") ;;
    *) return 0 ;;
  esac

  local p pstage pgate rc
  for p in "${prereqs[@]}"; do
    pstage="${p%%:*}"
    pgate="${p#*:}"
    _stage_history_satisfied "$pstage" "$pgate"
    rc=$?
    if [[ $rc -eq 2 ]]; then
      return 2
    elif [[ $rc -eq 1 ]]; then
      UNMET_PREREQ="$pstage"
      return 1
    fi
  done
  return 0
}

# Maps a chain-stage token to the pipeline command that produces it, for use
# in the refusal diagnostic below. "review" always maps to the plan-review
# command specifically — UNMET_PREREQ is only ever set to "review" via the
# gate_type=="secondary" prereq in _evaluate_prerequisites, which is the
# plan-review gate, never /speckit-review or /speckit-review-spec.
_prereq_command() {
  case "$1" in
    specify) echo "/speckit-specify" ;;
    plan) echo "/speckit-plan" ;;
    review) echo "/speckit-review-plan" ;;
    tasks) echo "/speckit-tasks" ;;
    implement) echo "/speckit-implement" ;;
    *) echo "the pipeline command that produces '$1'" ;;
  esac
}

# Fires exactly once per refused write, in both advisory and strict
# modes, as soon as REFUSED is known — regardless of whether the ordinary
# tail-of-file emitter below is ever reached (the strict path exits before
# reaching it). Reuses the same silent-no-op guard the tail emitter relies on
# so it can never block or abort the writer, and must not extend the
# critical-section lock hold on the real-write path.
_emit_refusal_telemetry() {
  local _feature="${FEATURE_DIR#"$REPO_ROOT"/}"
  # shellcheck disable=SC1091  # telemetry.sh is resolved at runtime, not statically
  { ( source "$SCRIPT_DIR/telemetry.sh" && declare -F speckit_log_event >/dev/null && speckit_log_event prerequisite_unmet "$STAGE" "unrecorded" "$_feature" "refused" "unmet_prerequisite=$UNMET_PREREQ" "mode=$ENFORCEMENT_MODE" "adjudication=unadjudicated" ) || true; } 2>/dev/null
}

GUARD_FAULT=0
REFUSED=0
UNMET_PREREQ=""
ENFORCEMENT_MODE="advisory"

# The config read runs once, unlocked (it never races — it does not depend on
# concurrent writers) but still inside the same fail-open sentinel discipline
# as the evaluation itself: disabling `set -e` here means an
# unexpected failure is captured as GUARD_FAULT, never an aborted script.
set +e
_read_enforcement_mode
_CONFIG_READ_RC=$?
set -e
if [[ $_CONFIG_READ_RC -ne 0 ]]; then
  GUARD_FAULT=1
fi
unset _CONFIG_READ_RC

# --- Shared write machinery ---
#
# Defined ahead of the --check-only branch because both paths can now reach
# it: --check-only appends a refusal record when --record-refusal asks it to,
# and takes the same lock the real write does so the two can never interleave
# a partial line.
#
# The lock file lives outside the versioned tree, keyed per feature, so it
# never appears in `sl status` and two features never contend on one lock.
# Keyed on the full absolute FEATURE_DIR path, not just its basename: two
# unrelated checkouts can easily share a feature directory's basename (e.g.
# two repos both have "specs/042-foo"), and a basename-only key would collide
# their locks in the shared system temp directory even though the features
# are otherwise unrelated. `$FEATURE_DIR` is already normalized absolute by
# get_feature_paths(). The substitution is captured via `printf` (not piped
# directly into tr) so tr never sees a trailing newline to translate into a
# spurious trailing dash.
_FEATURE_KEY="$(printf '%s' "$FEATURE_DIR" | tr -c 'A-Za-z0-9_.-' '-')"
LOCK_FILE="${TMPDIR:-/tmp}/speckit-pipeline-state-${_FEATURE_KEY}.lock"
unset _FEATURE_KEY
FLOCK_AVAILABLE="false"
command -v flock >/dev/null 2>&1 && FLOCK_AVAILABLE="true"

CRIT_EXIT=0
SEQ=0
TIMESTAMP=""

# Sequence number: highest existing seq + 1, with a nanosecond-epoch fallback
# on any read failure so the result can never collide with a small-integer
# seq already in the corpus. Both writing paths call this while holding the
# lock, so the seq they compute cannot be claimed by a concurrent writer
# between the read and the append.
_compute_seq_and_timestamp() {
  SEQ=1
  if [[ -f "$STATE_FILE" ]]; then
    local highest_seq
    # A jq exit failure isn't the only way this read can produce something
    # arithmetic can't consume: slurping a zero-byte file succeeds (jq exits
    # 0) but yields `[]`, whose `max` is the bareword "null" — an unbound-
    # variable abort under `set -u` once it reaches `$((...))`. Route that
    # case through the same nanosecond fallback as a genuine jq failure.
    if highest_seq=$(jq -s 'map(.seq // 0) | max' "$STATE_FILE" 2>/dev/null) && [[ "$highest_seq" =~ ^[0-9]+$ ]]; then
      SEQ=$((highest_seq + 1))
    else
      SEQ=$(date +%s%N)
    fi
  fi
  TIMESTAMP=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
}

# Appends the refusal record that a strict-mode refusal leaves in place of
# the completion write. Sets CRIT_EXIT to 4 on success, 3 if the record could
# not be formed, 6 if it could not be appended. Callers must have computed
# SEQ/TIMESTAMP first.
_append_refusal_record() {
  local refusal_feature refusal_json
  refusal_feature="${FEATURE_DIR#"$REPO_ROOT"/}"
  refusal_json=$(printf '{"stage": "%s", "record_type": "refusal", "unmet_prerequisite": "%s", "feature": "%s", "seq": %s, "timestamp": "%s"}' \
    "$STAGE" "$UNMET_PREREQ" "$refusal_feature" "$SEQ" "$TIMESTAMP")
  if ! echo "$refusal_json" | jq . > /dev/null 2>/dev/null; then
    echo "ERROR: Generated invalid JSON: $refusal_json" >&2
    CRIT_EXIT=3
    return
  fi
  # Checked, not assumed. A refusal reported as an ordinary refusal while its
  # record failed to land is the exact gap the record exists to close: every
  # consumer that reads presence would see a stage that simply never ran.
  if ! echo "$refusal_json" >> "$STATE_FILE"; then
    echo "SPECKIT-STATE-WRITE-FAILED: stage '$STAGE' was declined, but the refusal record could not be appended to $STATE_FILE — the decision is not recorded" >&2
    CRIT_EXIT=6
    return
  fi
  CRIT_EXIT=4
}

# Runs the named function while holding the feature's lock, and returns that
# function's own exit status. Lock-acquisition failure is reported out-of-band
# through LOCK_TIMED_OUT rather than through the return value, because the two
# are different outcomes that the callers answer differently — folding a
# timeout into the return value would make it indistinguishable from a callback
# that ran and failed.
#
# The callback's status must be captured explicitly. Every call site invokes
# this helper in a condition or `||` position, which disables `set -e` for the
# whole nested call: a failing callback neither aborts nor propagates on its
# own, and the `flock -u` that follows it would otherwise become the function's
# exit status and report success.
#
# Bounded acquisition: an unbounded wait would turn a crashed or wedged
# lock-holder into a permanent block on every later write to this feature's
# history. The lock is released and the descriptor closed on every path out,
# including the one where the callback failed.
LOCK_TIMED_OUT=0

_run_locked() {
  local fn="$1"
  local rc=0
  LOCK_TIMED_OUT=0
  if [[ "$FLOCK_AVAILABLE" != "true" ]]; then
    # Soft dependency: no flock on this host reverts to the pre-existing
    # unlocked read-evaluate-append, unchanged from today's behavior.
    "$fn" || rc=$?
    return "$rc"
  fi
  exec {LOCK_FD}>"$LOCK_FILE"
  if flock -w 5 "$LOCK_FD"; then
    "$fn" || rc=$?
    flock -u "$LOCK_FD"
  else
    echo "SPECKIT-GUARD-FAULT: could not acquire the pipeline-state lock for '$FEATURE_DIR' within 5s — proceeding without atomic evaluate-and-append" >&2
    LOCK_TIMED_OUT=1
  fi
  exec {LOCK_FD}>&-
  return "$rc"
}

_record_refusal_section() {
  _compute_seq_and_timestamp
  _append_refusal_record
}

if [[ "$CHECK_ONLY" == "true" ]]; then
  # --check-only does not append a completion entry: it evaluates and
  # reports 0/4. Without --record-refusal it touches the history file not at
  # all, which is the original contract; with it, a strict-mode refusal also
  # leaves the refusal record that documents the outcome.
  if [[ "$GUARD_FAULT" -ne 1 && "$PREREQ_OVERRIDE_REASON_SET" != "true" && "$ENFORCEMENT_MODE" != "off" ]]; then
    set +e
    _evaluate_prerequisites "$STAGE" "$GATE_TYPE"
    _EVAL_RC=$?
    set -e
    if [[ $_EVAL_RC -eq 2 ]]; then
      GUARD_FAULT=1
    elif [[ $_EVAL_RC -eq 1 ]]; then
      REFUSED=1
    fi
    unset _EVAL_RC
  fi

  if [[ "$GUARD_FAULT" -eq 1 ]]; then
    echo "SPECKIT-GUARD-FAULT: pipeline-integrity guard failed internally while evaluating stage '$STAGE' — proceeding without a prerequisite decision" >&2
    [[ "$ENFORCEMENT_MODE" == "strict" ]] && exit 5
    exit 0
  elif [[ "$REFUSED" -eq 1 ]]; then
    echo "ERROR: stage '$STAGE' requires '$UNMET_PREREQ' to complete first. Run $(_prereq_command "$UNMET_PREREQ"), then retry." >&2
    _emit_refusal_telemetry
    if [[ "$ENFORCEMENT_MODE" == "strict" ]]; then
      if [[ "$RECORD_REFUSAL" == "true" ]]; then
        _REFUSAL_RC=0
        _run_locked _record_refusal_section || _REFUSAL_RC=$?
        if [[ "$LOCK_TIMED_OUT" -eq 1 ]]; then
          # A lock timeout must not downgrade a decided refusal into a fault:
          # the decision stands either way, and the record is what the caller
          # asked for, so fall back to the unlocked append the no-flock host
          # already uses rather than exiting without one.
          _REFUSAL_RC=0
          _record_refusal_section || _REFUSAL_RC=$?
        fi
        if [[ "$_REFUSAL_RC" -ne 0 ]]; then
          exit "$_REFUSAL_RC"
        fi
        # CRIT_EXIT 4 is the refusal itself. Anything else means the record was
        # not written, and reporting a plain refusal would claim a durable
        # trace that does not exist.
        if [[ "$CRIT_EXIT" -ne 0 && "$CRIT_EXIT" -ne 4 ]]; then
          exit "$CRIT_EXIT"
        fi
        unset _REFUSAL_RC
      fi
      exit 4
    fi
    exit 0
  fi
  exit 0
fi

# --- Real write path: atomic evaluate-and-append ---

_critical_section() {
  _compute_seq_and_timestamp

  if [[ "$GUARD_FAULT" -ne 1 && "$PREREQ_OVERRIDE_REASON_SET" != "true" && "$ENFORCEMENT_MODE" != "off" ]]; then
    # set +e here, not just around the top-level config read: a bare
    # non-zero return from this call — the normal way it reports "refused"
    # or "fault" — would otherwise trip `set -e` and abort the script before
    # the branches below ever see the result.
    local eval_rc
    set +e
    _evaluate_prerequisites "$STAGE" "$GATE_TYPE"
    eval_rc=$?
    set -e
    if [[ $eval_rc -eq 2 ]]; then
      GUARD_FAULT=1
    elif [[ $eval_rc -eq 1 ]]; then
      REFUSED=1
    fi
  fi

  if [[ "$GUARD_FAULT" -eq 1 ]]; then
    echo "SPECKIT-GUARD-FAULT: pipeline-integrity guard failed internally while evaluating stage '$STAGE' — proceeding without a prerequisite decision" >&2
    if [[ "$ENFORCEMENT_MODE" == "strict" ]]; then
      CRIT_EXIT=5
      return
    fi
    # advisory/off: fall through to the ordinary append below.
  elif [[ "$REFUSED" -eq 1 ]]; then
    echo "ERROR: stage '$STAGE' requires '$UNMET_PREREQ' to complete first. Run $(_prereq_command "$UNMET_PREREQ"), then retry." >&2
    _emit_refusal_telemetry
    if [[ "$ENFORCEMENT_MODE" == "strict" ]]; then
      # Strict mode declines the requested completion write outright: a
      # refusal record is appended in its place, and the write never
      # reaches the ordinary append below.
      _append_refusal_record
      return
    fi
    # advisory: diagnostic + telemetry only — the ordinary write still proceeds.
  fi

  local -a full_parts=("\"stage\": \"$STAGE\"" "\"timestamp\": \"$TIMESTAMP\"" "\"seq\": $SEQ" "${JSON_PARTS[@]}")
  local json
  json=$(IFS=,; echo "{${full_parts[*]}}")
  if ! echo "$json" | jq . > /dev/null 2>/dev/null; then
    echo "ERROR: Generated invalid JSON: $json" >&2
    CRIT_EXIT=3
    return
  fi
  # Checked, not assumed — see the refusal-record append above. Announcing a
  # write that did not happen is worse than failing: the stage reads as
  # complete to every later prerequisite check while its record is absent.
  if ! echo "$json" >> "$STATE_FILE"; then
    echo "SPECKIT-STATE-WRITE-FAILED: could not append the '$STAGE' record to $STATE_FILE — the stage is not recorded" >&2
    CRIT_EXIT=6
    return
  fi
  echo "✓ Pipeline state written to $STATE_FILE (seq $SEQ)"
}

_SECTION_RC=0
_run_locked _critical_section || _SECTION_RC=$?
if [[ "$LOCK_TIMED_OUT" -eq 1 ]]; then
  # A timeout is a guard-internal fault, not a refusal — strict mode reports
  # it as such; the other modes fail open and write without the lock.
  if [[ "$ENFORCEMENT_MODE" == "strict" ]]; then
    exit 5
  fi
  _SECTION_RC=0
  _critical_section || _SECTION_RC=$?
fi

# A non-zero return from the section is distinct from the CRIT_EXIT it sets
# deliberately: it means the section aborted somewhere it did not expect to,
# which must not be reported as a completed write.
if [[ "$_SECTION_RC" -ne 0 ]]; then
  exit "$_SECTION_RC"
fi
unset _SECTION_RC

if [[ "$CRIT_EXIT" -ne 0 ]]; then
  exit "$CRIT_EXIT"
fi

# Telemetry: emitted as the LAST statement so nothing after it can be
# affected, wrapped in a terminal safety group so a sourcing failure, a missing
# function, or an emitter error can neither change this script's exit code nor
# leak output. The JSONL write above has already succeeded and is never gated on
# this line. Do not add code below it.
#
# get_feature_paths() normalizes FEATURE_DIR to an absolute path for file I/O,
# but the telemetry event's feature id is documented as REPO_ROOT-relative —
# strip the prefix here rather than changing FEATURE_DIR itself, which every
# other consumer in this script needs absolute.
_TELEMETRY_FEATURE="${FEATURE_DIR#"$REPO_ROOT"/}"
# shellcheck disable=SC1091  # telemetry.sh is resolved at runtime, not statically
{ ( source "$SCRIPT_DIR/telemetry.sh" && declare -F speckit_log_event >/dev/null && speckit_log_event pipeline_stage "$STAGE" "$SEQ" "$_TELEMETRY_FEATURE" "$STATUS" "$@" ) || true; } 2>/dev/null
