#!/usr/bin/env bash
# Unified review gate writer — consolidates duplicated gate-writing blocks
# Calls write-review-gate.sh and write-pipeline-state.sh with correct arguments

set -euo pipefail

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

usage() {
  cat <<EOF
Usage: $0 --gate-type TYPE --status STATUS --must-address N --should-consider M --minor K --agents-completed A [--primary-completed-at TS] [--stage review|verify] [--partial] [--override] [--resolved] [--attempt-id ID]

Arguments:
  --gate-type TYPE              primary or secondary (not validated when --stage verify)
  --status STATUS               passed or blocked
  --must-address N              Count of MUST-ADDRESS findings
  --should-consider M           Count of SHOULD-CONSIDER findings
  --minor K                     Count of MINOR findings
  --agents-completed A          Number of agents that completed
  --primary-completed-at TS     Primary gate timestamp (required for secondary gate if not in pipeline-state.jsonl)
  --stage review|verify         Pipeline stage this gate belongs to (default: review)
  --partial                     Mark the gate as partial (both stages)
  --attempt-id ID                The current review attempt's id (review stage only). Absent
                                 on the one legitimately attempt-less caller, --skip-review;
                                 write-review-gate.sh records null in that case.
  --override                    Mark this gate write as originating from an override (both stages)
  --resolved                    Mark this gate write as originating from a resolution loop's own
                                 fix-application (both stages) — verify-auto/verify-interactive on the
                                 verify stage, review-auto/review-interactive on the review stage.
                                 sapling-commit.sh's after_verify and after_review branches read this to
                                 decide whether the artifact edits made during resolution are this run's
                                 own sanctioned output, not incidental drift
  --panel-size N                 Designed adversarial panel size (review stage only; default: 0)
  --quorum-met true|false        Whether the panel reached quorum (review stage only; default: true)
  prereq_override_reason=REASON  Bypass the prerequisite chain for this write, recording REASON
                                 on the entry. REASON must be non-empty. Written in key=value
                                 form (not --flag form) because the graduated refusal gate
                                 instructs the user to re-invoke the same write with this
                                 token appended verbatim.
  --auto-applied                 Mark this gate write as covering findings the synthesis
                                  triage step auto-applied to the gate's own artifact (review
                                  stage only) — spec.md at a primary gate, plan.md at a
                                  secondary gate. sapling-commit.sh's after_review branch
                                  reads this: the primary-gate commit scope already covers
                                  the whole feature directory unconditionally, so the flag is
                                  metadata/observability there; on a secondary gate it widens
                                  the commit scope to include plan.md.

EOF
  exit 1
}

# Parse arguments
GATE_TYPE=""
STATUS=""
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
PREREQ_OVERRIDE_REASON=""
PREREQ_OVERRIDE_REASON_SET="false"
# Set by _snapshot_gate before any gate write; initialized here so the rollback
# path can never trip `set -u` on an unexpected route.
GATE_SNAPSHOT=""
GATE_EXISTED="false"

while [[ $# -gt 0 ]]; do
  case $1 in
    --gate-type)
      GATE_TYPE="$2"
      shift 2
      ;;
    --status)
      STATUS="$2"
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
    # Accepted in write-pipeline-state.sh's key=value shape rather than this
    # script's --flag shape, because the graduated refusal gate instructs the
    # user to re-invoke *the same write* with this token appended verbatim.
    # Six of that gate's call sites reach the writer through this script, so
    # rejecting the token here would make the sanctioned override unusable at
    # the majority of them.
    prereq_override_reason=*)
      PREREQ_OVERRIDE_REASON="${1#prereq_override_reason=}"
      # An empty reason is rejected rather than accepted as a bare bypass. The
      # glob above matches the empty string, and the override skips the whole
      # prerequisite evaluation, so accepting it here would disable the chain
      # while recording nothing about why. write-pipeline-state.sh already
      # declines the empty form (its key=value pattern requires a value); this
      # keeps the two in step instead of forwarding a token that the writer
      # would silently drop while this script believed an override was active.
      if [[ -z "$PREREQ_OVERRIDE_REASON" ]]; then
        echo "ERROR: prereq_override_reason requires a non-empty reason" >&2
        exit 1
      fi
      PREREQ_OVERRIDE_REASON_SET="true"
      shift 1
      ;;
    *)
      echo "Unknown argument: $1" >&2
      usage
      ;;
  esac
done

if [[ "$STAGE" != "review" && "$STAGE" != "verify" ]]; then
  echo "Error: --stage must be 'review' or 'verify'" >&2
  exit 1
fi

# Validate required arguments
if [[ -z "$STATUS" || -z "$MUST_ADDRESS" || -z "$SHOULD_CONSIDER" || -z "$MINOR" || -z "$AGENTS_COMPLETED" ]]; then
  echo "Error: Missing required arguments" >&2
  usage
fi

# gate-type carries the primary/secondary distinction, which only applies to
# the review stage. The verify stage has no such distinction — a caller-passed
# --gate-type value (e.g. "verify") is accepted without validation.
if [[ "$STAGE" == "review" ]]; then
  if [[ -z "$GATE_TYPE" ]]; then
    echo "Error: Missing required arguments" >&2
    usage
  fi

  if [[ "$GATE_TYPE" != "primary" && "$GATE_TYPE" != "secondary" ]]; then
    echo "Error: --gate-type must be 'primary' or 'secondary'" >&2
    exit 1
  fi
fi

if [[ "$STATUS" != "passed" && "$STATUS" != "blocked" ]]; then
  echo "Error: --status must be 'passed' or 'blocked'" >&2
  exit 1
fi

# For secondary gate, read primary_completed_at from pipeline-state.jsonl if not provided
if [[ "$STAGE" == "review" && "$GATE_TYPE" == "secondary" && -z "$PRIMARY_COMPLETED_AT" ]]; then
  if [[ ! -f "${FEATURE_DIR}/pipeline-state.jsonl" ]]; then
    echo "Error: Secondary gate requires --primary-completed-at or existing pipeline-state.jsonl" >&2
    exit 1
  fi
  PRIMARY_COMPLETED_AT=$(jq -sr '.[] | select(.stage == "review") | select(.gate_type == "primary") | .timestamp' "${FEATURE_DIR}/pipeline-state.jsonl" | tail -1)
  if [[ -z "$PRIMARY_COMPLETED_AT" || "$PRIMARY_COMPLETED_AT" == "null" ]]; then
    # No primary gate exists — set to null for secondary-only review
    PRIMARY_COMPLETED_AT="null"
  fi
fi

# Pre-flight against write-pipeline-state.sh's --check-only mode:
# refuses (exit 4) before the gate file is written at all, so a refused write
# leaves no gate artifact. A satisfied check (exit 0) falls through to the
# unchanged write sequence below. A guard fault surfaces as exit 5 only in
# strict mode — advisory and off report 0 from the pre-flight and fail open
# into the write sequence, matching write-pipeline-state.sh's own posture
# toward its own guard faults.
#
# This script does not present a user-facing choice for the exit 3/4/5/6 it
# propagates below — it is a plain bash script with no interactive surface.
# The 11th call site for the graduated refusal gate
# (.specify/templates/prerequisite-refusal-gate.md) is therefore not here: it
# lives in every command template that invokes this script and reads its exit
# code (speckit.verify.md, speckit.verify-auto.md, speckit.verify-interactive.md,
# speckit.review-plan.md, speckit.review-interactive.md, speckit.review-auto.md).
# Each of those carries its own pointer to the shared template, and the template
# routes each code: only 4 opens the three-way choice, while 5 and 6 relay their
# diagnostic and halt.
#
# --record-refusal is what makes the pre-flight's refusal durable. Without it,
# --check-only writes nothing, so a refusal caught here would leave no record
# at all and the gap would read to every presence-checking consumer as a stage
# that never ran. It is passed to the single pre-flight call rather than
# handled by re-invoking the writer afterwards: a second invocation would
# evaluate the chain a second time, which emits the refusal telemetry twice,
# and — if a concurrent writer satisfied the prerequisite in between — would
# take the ordinary append path and record a *completion* for this stage
# carrying none of the payload below, a phantom entry that then satisfies every
# later prerequisite check.
_preflight_or_exit() {
  local rc=0
  bash "$SCRIPT_DIR/write-pipeline-state.sh" --check-only --record-refusal "$@" || rc=$?
  # Any non-zero result means no state record for this stage will exist — a
  # refusal (4), a guard fault (5), a record that could not be formed (3) or
  # one that could not be appended (6) all leave the same absence. None may
  # proceed to write a gate file that would then stand alone. Propagating here
  # rather than falling through also spares the write-then-roll-back round trip
  # the real write would otherwise perform for the same outcome.
  if [[ "$rc" -ne 0 ]]; then
    exit "$rc"
  fi
}

# Snapshots the gate file (if any) before it is overwritten, so a later
# rollback can restore what was there rather than deleting it. A gate file
# already on disk is a valid record of an earlier gate; deleting it turns a
# refused re-run into the loss of a good artifact.
#
# The copy goes to a temp file rather than a shell variable: command
# substitution strips trailing newlines, so a variable round-trip cannot
# reproduce the original bytes — an empty gate file would come back one byte
# long, and one without a trailing newline would gain one.
_snapshot_gate() {
  local gate_file="$1"
  GATE_SNAPSHOT=""
  GATE_EXISTED="false"
  [[ -f "$gate_file" ]] || return 0
  GATE_EXISTED="true"
  local tmp
  tmp="$(mktemp "${TMPDIR:-/tmp}/speckit-gate-snapshot.XXXXXX" 2>/dev/null)" || return 0
  if cp "$gate_file" "$tmp" 2>/dev/null; then
    GATE_SNAPSHOT="$tmp"
  else
    rm -f "$tmp" 2>/dev/null || true
  fi
}

# The snapshot is scratch state, never an artifact — clear it on every exit
# path, including the rollback exits below.
trap '[[ -n "${GATE_SNAPSHOT:-}" ]] && rm -f "$GATE_SNAPSHOT" 2>/dev/null; true' EXIT

# Compensating rollback for a race that can still occur: the
# pre-flight passed but the real write below was refused anyway. Deletes the
# gate file just written so it never disagrees with pipeline-state.jsonl, then
# re-raises exit 4. If the delete itself fails — permission error, or the file
# already missing — that is a distinct, worse fault: a gate file may now
# survive contradicting a pipeline-state that says the write never landed. The
# fixed "SPECKIT-GUARD-FAULT:" prefix distinguishes this exit 5 from both a
# clean rollback (exit 4) and an ordinary pre-flight refusal (also exit 4, but
# with no gate file ever written).
_rollback_gate_or_fault() {
  local gate_file="$1"
  local exit_code="${2:-4}"
  local restored=0
  if [[ "$GATE_EXISTED" == "true" ]]; then
    # Restore the prior gate rather than removing it: this run overwrote a
    # valid artifact, and rolling back means undoing the overwrite, not
    # destroying what was there before. A missing snapshot means the copy
    # failed earlier; report that as the fault it is rather than falling back
    # to deleting a gate file that was valid before this run touched it.
    if [[ -n "$GATE_SNAPSHOT" && -f "$GATE_SNAPSHOT" ]]; then
      cp "$GATE_SNAPSHOT" "$gate_file" 2>/dev/null || restored=1
    else
      restored=1
    fi
  else
    rm "$gate_file" 2>/dev/null || restored=1
  fi
  if [[ "$restored" -ne 0 ]]; then
    echo "SPECKIT-GUARD-FAULT: the pipeline-state write failed after the gate file was written, and restoring '$gate_file' to its prior state failed — it survives and contradicts pipeline-state.jsonl" >&2
    exit 5
  fi
  exit "$exit_code"
}

if [[ "$STAGE" == "verify" ]]; then
  # Verify has no primary/secondary distinction — write-review-gate.sh still
  # requires a primary|secondary --gate-type, so it is always invoked as
  # "primary" here (which also means no --primary-completed-at, consistent
  # with primary-gate rules).
  PREFLIGHT_ARGS=(verify)
  if [[ "$PREREQ_OVERRIDE_REASON_SET" == "true" ]]; then
    PREFLIGHT_ARGS+=("prereq_override_reason=$PREREQ_OVERRIDE_REASON")
  fi
  _preflight_or_exit "${PREFLIGHT_ARGS[@]}"

  WRITE_GATE_ARGS=(
    --stage verify
    --status "$STATUS"
    --gate-type primary
    --must-address "$MUST_ADDRESS"
    --should-consider "$SHOULD_CONSIDER"
    --minor "$MINOR"
    --agents-completed "$AGENTS_COMPLETED"
  )
  if [[ "$PARTIAL" == "true" ]]; then
    WRITE_GATE_ARGS+=(--partial)
  fi
  if [[ "$OVERRIDE" == "true" ]]; then
    WRITE_GATE_ARGS+=(--override)
  fi
  if [[ "$RESOLVED" == "true" ]]; then
    WRITE_GATE_ARGS+=(--resolved)
  fi
  _snapshot_gate "$FEATURE_DIR/verify-gate.json"
  bash "$SCRIPT_DIR/write-review-gate.sh" "${WRITE_GATE_ARGS[@]}"

  WRITE_STATE_ARGS=(
    verify
    status="$STATUS"
    must_address="$MUST_ADDRESS"
    should_consider="$SHOULD_CONSIDER"
    minor="$MINOR"
    agents_completed="$AGENTS_COMPLETED"
    override="$OVERRIDE"
    resolved="$RESOLVED"
  )
  if [[ "$PREREQ_OVERRIDE_REASON_SET" == "true" ]]; then
    WRITE_STATE_ARGS+=("prereq_override_reason=$PREREQ_OVERRIDE_REASON")
  fi
  _state_rc=0
  bash "$SCRIPT_DIR/write-pipeline-state.sh" "${WRITE_STATE_ARGS[@]}" || _state_rc=$?
  # Any non-zero result rolls the gate back, not just a refusal (4) or a
  # guard fault (5). The gate file is already on disk whatever went wrong, and
  # every failing path leaves the state record equally absent — a write that
  # could not be appended (6) or a record that could not be formed (3) strands
  # exactly the same torn pair. The original code is preserved so the caller
  # still learns which of them happened.
  if [[ "$_state_rc" -ne 0 ]]; then
    _rollback_gate_or_fault "$FEATURE_DIR/verify-gate.json" "$_state_rc"
  fi
else
  # Call write-review-gate.sh. --override applies to both stages: the gate
  # JSON and the pipeline-state entry must agree on whether this run was an
  # override.
  PREFLIGHT_ARGS=(review "gate_type=$GATE_TYPE")
  if [[ "$PREREQ_OVERRIDE_REASON_SET" == "true" ]]; then
    PREFLIGHT_ARGS+=("prereq_override_reason=$PREREQ_OVERRIDE_REASON")
  fi
  _preflight_or_exit "${PREFLIGHT_ARGS[@]}"

  WRITE_GATE_ARGS=(
    --status "$STATUS"
    --gate-type "$GATE_TYPE"
    --must-address "$MUST_ADDRESS"
    --should-consider "$SHOULD_CONSIDER"
    --minor "$MINOR"
    --agents-completed "$AGENTS_COMPLETED"
  )
  if [[ "$GATE_TYPE" == "secondary" ]]; then
    WRITE_GATE_ARGS+=(--primary-completed-at "$PRIMARY_COMPLETED_AT")
  fi
  if [[ "$OVERRIDE" == "true" ]]; then
    WRITE_GATE_ARGS+=(--override)
  fi
  # --resolved applies to both stages, for the same reason --override does: a
  # review-stage run that retained its own auto-resolve edits must record that
  # retention here too.
  if [[ "$RESOLVED" == "true" ]]; then
    WRITE_GATE_ARGS+=(--resolved)
  fi
  if [[ "$AUTO_APPLIED" == "true" ]]; then
    WRITE_GATE_ARGS+=(--auto-applied)
  fi
  # --partial is no longer verify-only: a review-stage attempt with
  # under-covered delivery carries the same flag.
  if [[ "$PARTIAL" == "true" ]]; then
    WRITE_GATE_ARGS+=(--partial)
  fi
  if [[ -n "$ATTEMPT_ID" ]]; then
    WRITE_GATE_ARGS+=(--attempt-id "$ATTEMPT_ID")
  fi
  WRITE_GATE_ARGS+=(--panel-size "$PANEL_SIZE" --quorum-met "$QUORUM_MET")
  mkdir -p "$FEATURE_DIR/review"
  _snapshot_gate "$FEATURE_DIR/review/review-gate.json"
  bash "$SCRIPT_DIR/write-review-gate.sh" "${WRITE_GATE_ARGS[@]}"

  # Call write-pipeline-state.sh. override= and resolved= must be threaded
  # here too, so the gate JSON and pipeline state agree on both fields for
  # this stage.
  WRITE_STATE_ARGS=(
    review
    status="$STATUS"
    gate_type="$GATE_TYPE"
    must_address="$MUST_ADDRESS"
    should_consider="$SHOULD_CONSIDER"
    minor="$MINOR"
    agents_completed="$AGENTS_COMPLETED"
  )
  if [[ "$GATE_TYPE" == "secondary" ]]; then
    WRITE_STATE_ARGS+=(primary_completed_at="$PRIMARY_COMPLETED_AT")
  fi
  WRITE_STATE_ARGS+=(override="$OVERRIDE")
  WRITE_STATE_ARGS+=(resolved="$RESOLVED")
  WRITE_STATE_ARGS+=(auto_applied="$AUTO_APPLIED")
  if [[ "$PREREQ_OVERRIDE_REASON_SET" == "true" ]]; then
    WRITE_STATE_ARGS+=("prereq_override_reason=$PREREQ_OVERRIDE_REASON")
  fi
  _state_rc=0
  bash "$SCRIPT_DIR/write-pipeline-state.sh" "${WRITE_STATE_ARGS[@]}" || _state_rc=$?
  # Every non-zero result rolls back — see the verify branch above.
  if [[ "$_state_rc" -ne 0 ]]; then
    _rollback_gate_or_fault "$FEATURE_DIR/review/review-gate.json" "$_state_rc"
  fi
fi
