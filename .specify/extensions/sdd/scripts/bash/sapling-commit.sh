#!/usr/bin/env bash
# SDD extension: sapling-commit.sh
# Commit spec artifacts via Sapling after a SpecKit command completes.
# Scoped to specs/ (spec.md, plan.md, tasks.md, auto-resolution-log.md, etc.)
# and .specify/ — never commits code changes.
#
# Usage: sapling-commit.sh <event_name>
#   e.g.: sapling-commit.sh after_specify

set -euo pipefail

EVENT_NAME="${1:-}"
if [ -z "$EVENT_NAME" ]; then
    echo "Usage: $0 <event_name>" >&2
    exit 1
fi

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

_find_project_root() {
    local dir="$1"
    while [ "$dir" != "/" ]; do
        if [ -d "$dir/.specify" ]; then
            echo "$dir"
            return 0
        fi
        dir="$(dirname "$dir")"
    done
    return 1
}

# After install, SCRIPT_DIR is .specify/extensions/sdd/scripts/bash/ —
# traversal finds .specify at the project root. Falls back to cwd if
# invoked before install copies the script.
REPO_ROOT=$(_find_project_root "$SCRIPT_DIR") || REPO_ROOT="$(pwd)"
cd "$REPO_ROOT"

_COMMON="$REPO_ROOT/.specify/scripts/bash/common.sh"
[[ -f "$_COMMON" ]] || { echo "ERROR: common.sh not found — reinstall with 'speckit init'" >&2; exit 1; }
# shellcheck disable=SC1090  # dynamic path resolved from REPO_ROOT at runtime
source "$_COMMON"

if ! command -v sl >/dev/null 2>&1; then
    echo "[specify] Warning: Sapling (sl) not found; skipped auto-commit" >&2
    exit 0
fi

_resolve_prefix() {
    python3 -c '
import re, os, sys
repo = sys.argv[1]
for name in [".claude/CLAUDE.md", "CLAUDE.md"]:
    path = os.path.join(repo, name)
    if not os.path.isfile(path):
        continue
    try:
        content = open(path).read()
    except Exception:
        continue
    for section in re.split(r"^## ", content, flags=re.MULTILINE):
        header = section.split("\n", 1)[0].strip().lower()
        if "diff" not in header:
            continue
        m = re.search(r"Prefix\s*:\s*`?\[([^\]]+)\]", section)
        if not m:
            m = re.search(r"Title tag\s*\|\s*`?\[([^\]]+)\]", section)
        if m:
            print("[" + m.group(1) + "]")
            sys.exit(0)
dirname = os.path.basename(sys.argv[1])
if dirname:
    print("[" + dirname + "]")
' "$REPO_ROOT" 2>/dev/null || :
}
_prefix=$(_resolve_prefix)
if [ -z "$_prefix" ]; then
    _prefix="[$(basename "$REPO_ROOT")]"
fi

# Check for suppression marker (setup command suppresses sub-command commits).
# after_setup is exempt — it's the "done" signal that commits setup artifacts,
# so it must never be suppressed even if the marker is still present.
_suppress_file=".specify/.suppress-sdd-commit"
if [ -f "$_suppress_file" ] && [ "$EVENT_NAME" != "after_setup" ]; then
    # Distinguish "marker unreadable" from "marker stale": an empty, missing,
    # zero, or non-numeric timestamp means the marker is malformed, not old, so
    # log it as such rather than reporting a bogus multi-hour age.
    _marker_ts=$(python3 -c "import json; v=json.load(open('$_suppress_file')).get('timestamp', 0); print(v if isinstance(v, int) and v > 0 else '')" 2>/dev/null) || _marker_ts=""
    case "$_marker_ts" in
        ''|*[!0-9]*)
            echo "[specify] Warning: unreadable suppression marker; removing and proceeding" >&2
            rm -f "$_suppress_file"
            ;;
        *)
            _now=$(date +%s)
            _age=$(( _now - _marker_ts ))
            if [ "$_age" -lt 0 ]; then
                # Future timestamp (clock skew / bad writer): a negative age would
                # otherwise satisfy "-lt 3600" and suppress forever. Treat as
                # malformed — remove and proceed — mirroring the unreadable branch.
                echo "[specify] Warning: suppression marker timestamp is in the future; removing and proceeding" >&2
                rm -f "$_suppress_file"
            elif [ "$_age" -lt 3600 ]; then
                echo "[specify] Suppressing ${EVENT_NAME} commit (marker present, age: ${_age}s)" >&2
                exit 0
            else
                echo "[specify] Warning: Stale suppression marker detected (age: ${_age}s); removing and proceeding" >&2
                rm -f "$_suppress_file"
            fi
            ;;
    esac
fi

_command_name=$(echo "$EVENT_NAME" | sed 's/^after_//' | sed 's/^before_//')

_feature_name=""
# get_feature_paths() falls back to a branch-name/directory-scanning guess when
# no feature is explicitly set — appropriate for scripts that always need an
# answer, but wrong for a passive commit hook that runs after every pipeline
# command (including feature-less ones like after_constitution): guessing
# wrong silently misattributes a commit to the wrong feature directory. Only
# resolve via common.sh when a feature is explicitly declared.
_raw_feature_dir=$(read_feature_json_feature_directory "$REPO_ROOT" 2>/dev/null) || _raw_feature_dir=""
if [ -n "$_raw_feature_dir" ] || [ -n "${SPECIFY_FEATURE_DIRECTORY:-}" ]; then
    _paths_output=$(get_feature_paths 2>/dev/null) && eval "$_paths_output" || :
    unset _paths_output
    # This hook never commits code changes outside specs/ (see header comment).
    # get_feature_paths() accepts SPECIFY_FEATURE_DIRECTORY pointing anywhere —
    # validate containment here rather than trusting an override that could
    # widen the commit scope outside specs/.
    if [ -n "${FEATURE_DIR:-}" ]; then
        case "$FEATURE_DIR" in
            "$REPO_ROOT"/specs/*) _feature_name="$(basename "$FEATURE_DIR")" ;;
            *)
                echo "[specify] Warning: resolved feature directory '$FEATURE_DIR' is outside specs/; treating as feature-less for this commit" >&2
                FEATURE_DIR=""
                ;;
        esac
    fi
fi
unset _raw_feature_dir

# Build paths to check.
#
# For after_review, the commit scope depends on the review gate type, read from
# review/review-gate.json (always written by the review command before this hook fires):
#
#   primary   — the spec review runs standalone (after_specify has no review hook),
#               so no later commit will mop up. Commit broadly (feature dir +
#               .specify/) or the spec.md resolution edits and the pipeline-state
#               gate transition are silently dropped.
#
#   secondary — Plan Review auto-fires nested in the after_plan chain.
#               The outer after_plan sdd.commit runs last and commits plan + review
#               artifacts together. This nested commit MUST
#               stay scoped to review-only artifacts, or it would sweep the freshly
#               written, still-uncommitted plan.md into a "${_prefix} Review" commit.
#
#               One narrow addition to that scope: when the review gate reports
#               resolved=true, this run's own auto-resolve or interactive-resolution
#               loop wrote spec.md/plan.md/contracts edits, and leaving them out
#               strands them dirty and unattributed. The addition names exactly those
#               three paths rather than widening to the feature directory, so it does
#               not reproduce the misattribution warned about above: plan.md is
#               captured only on the runs that actually touched it, and on every other
#               run the outer after_plan commit still owns it uncontested. resolved is
#               written only by the resolution skills — never by a clean pass, a
#               quorum failure, or a plain override.
#
# Unknown/unreadable gate_type falls back to the narrow (secondary) scope — the
# conservative choice that never misattributes an uncommitted plan.md.
#
# Standalone-vs-nested note: gate_type cannot distinguish a standalone secondary
# review re-run from one nested under after_plan's mop-up. That distinction is
# unnecessary here — resolved=true captures spec.md/plan.md/contracts/ on either
# shape, so a standalone resolved run's edits are committed the same as a nested
# one's.
#
# pipeline-state.jsonl is in the narrow secondary scope: a degraded-quorum
# disclosure sidecar entry written to this file needs a commit path, since no
# existing after_review writer captured it before now.
# Accepted side effect: because Plan Review fires nested inside after_plan before
# the outer commit runs, pipeline-state.jsonl at that moment still carries the
# plan stage's own uncommitted entry too — on a run where both are dirty, the
# nested "[…] Review" commit captures it instead of the outer "[…] Plan"
# commit. This is a narrower instance of the misattribution class documented
# above and is accepted for the same reason: the entry reflects review-stage
# completion by the time it is actually captured.
_review_gate_type=""
_review_resolved="false"
_review_auto_applied="false"
_review_gate_file=""
if [ "$EVENT_NAME" = "after_review" ] && [ -n "$_feature_name" ]; then
    if [ -f "${FEATURE_DIR}/review/review-gate.json" ]; then
        _review_gate_file="${FEATURE_DIR}/review/review-gate.json"
    elif [ -f "${FEATURE_DIR}/review-gate.json" ]; then
        _review_gate_file="${FEATURE_DIR}/review-gate.json"
    fi
fi
if [ -n "$_review_gate_file" ]; then
    _review_gate_type=$(python3 -c "import json,sys; print(json.load(open(sys.argv[1])).get('gate_type',''))" "$_review_gate_file" 2>/dev/null) || _review_gate_type=""
    _review_resolved=$(python3 -c "import json,sys; print(str(json.load(open(sys.argv[1])).get('resolved', False)).lower())" "$_review_gate_file" 2>/dev/null) || _review_resolved="false"
    _review_auto_applied=$(python3 -c "import json,sys; print(str(json.load(open(sys.argv[1])).get('auto_applied', False)).lower())" "$_review_gate_file" 2>/dev/null) || _review_auto_applied="false"
fi

if [ "$EVENT_NAME" = "after_review" ] && [ "$_review_gate_type" = "primary" ] && [ -d "$FEATURE_DIR" ]; then
    # Primary spec review: standalone, no outer mop-up — commit broadly (scoped to
    # the current feature) so spec.md edits and pipeline-state are captured.
    _paths=("${FEATURE_DIR}/" ".specify/")
elif [ "$EVENT_NAME" = "after_review" ] && [ -n "$_feature_name" ] && [ -d "$FEATURE_DIR" ]; then
    # Secondary (or unknown) review: narrow scope — review-only artifacts.
    # Check review/ subdirectory first (new layout), then flat paths (old layout).
    _paths=()
    for _rel in review/review-findings.md review/review-gate.json auto-resolution-log.md review/review-findings-primary.md review/review-gate-primary.json pipeline-state.jsonl review-findings.md review-gate.json review-findings-primary.md review-gate-primary.json; do
        _candidate="${FEATURE_DIR}/${_rel}"
        if [ -e "$_candidate" ]; then
            _paths+=("$_candidate")
        fi
    done
    if [ "$_review_resolved" = "true" ]; then
        # This run's own resolution loop wrote these. Named individually, never
        # as a directory glob — see the scope note above.
        for _rel in spec.md plan.md; do
            _candidate="${FEATURE_DIR}/${_rel}"
            if [ -e "$_candidate" ]; then
                _paths+=("$_candidate")
            fi
        done
        if [ -d "${FEATURE_DIR}/contracts" ]; then
            _paths+=("${FEATURE_DIR}/contracts")
        fi
    elif [ "$_review_auto_applied" = "true" ]; then
        # Plan review's own synthesis-time triage step auto-applied fixes to
        # plan.md — narrower than the resolved=true widening above, since on
        # this (secondary/plan-review) branch auto-apply edits only ever
        # touch the plan, never spec.md/contracts/. Spec review's own
        # auto-apply writes to spec.md instead, but that is handled by the
        # primary-gate branch above, which already commits the whole feature
        # directory unconditionally — this branch never sees a primary gate.
        _candidate="${FEATURE_DIR}/plan.md"
        if [ -e "$_candidate" ]; then
            _paths+=("$_candidate")
        fi
    fi
elif { [ "$EVENT_NAME" = "verify_complete" ] || [ "$EVENT_NAME" = "after_verify" ]; } \
     && [ -n "$_feature_name" ] && [ -d "$FEATURE_DIR" ]; then
    # Verify is read-only with respect to spec.md during its own agent-dispatch
    # phase: speckit.verify.md dispatches read-only agents, writes
    # verification.md, and reports. Commit only what that phase itself
    # produces, so a spec edit sitting in the working copy for unrelated
    # reasons can never be labelled "Verify" — that is how a rewritten
    # requirement (and a rewritten Clarifications transcript) once landed
    # inside a PASS/0-findings commit.
    #
    # Resolution is a different phase with a different contract. When the gate
    # is blocked, speckit.verify-auto.md / speckit.verify-interactive.md apply
    # fixes directly to spec.md/plan.md/tasks.md as their entire purpose —
    # that is this run's own sanctioned output, not incidental drift.
    # verify-gate.json's "resolved" field (written only by those two skills,
    # never by a clean pass or a plain override) is the signal: when true,
    # widen to the whole feature dir, mirroring after_review's primary
    # (standalone, no outer mop-up) scope, so the resolved edits are captured
    # instead of being left dirty and misnamed as stray.
    _resolved="false"
    if [ -f "${FEATURE_DIR}/verify-gate.json" ]; then
        _resolved=$(python3 -c "import json,sys; print(str(json.load(open(sys.argv[1])).get('resolved', False)).lower())" "${FEATURE_DIR}/verify-gate.json" 2>/dev/null) || _resolved="false"
    fi

    if [ "$_resolved" = "true" ]; then
        _paths=("${FEATURE_DIR}/" ".specify/")
    else
        _verify_scope=1
        _paths=()
        for _rel in verification.md pipeline-state.jsonl verify-gate.json; do
            _candidate="${FEATURE_DIR}/${_rel}"
            if [ -e "$_candidate" ]; then
                _paths+=("$_candidate")
            fi
        done
    fi
else
    _paths=(".specify/")
    if [ -d "specs" ]; then
        _paths=("specs/" ".specify/")
    fi
fi

# Name anything the verify stage left dirty but out of scope. A silent drop is
# the failure mode the review scope note above exists to avoid, so warn rather
# than widening the commit.
if [ "${_verify_scope:-0}" = "1" ]; then
    # Plain `sl status` is -mardu: it already lists untracked files alongside
    # modified ones. Do NOT add -u here — -u means "show ONLY unknown", so it
    # would hide a modified spec.md, which is the case this warning exists for.
    # (The -u call further down is filtering to untracked deliberately, to feed
    # `sl add`.) Locked in by VerifyCommitScopeTest.
    _status_rc=0
    _status_out=$(sl status "${FEATURE_DIR}/" 2>/dev/null) || _status_rc=$?
    if [ "$_status_rc" -ne 0 ]; then
        # A silent "nothing stray" on a failed status is the same silent drop
        # this warning exists to prevent, so say so rather than saying nothing.
        echo "[specify] WARNING: 'sl status' failed (exit ${_status_rc}); cannot" >&2
        echo "  check ${FEATURE_DIR}/ for uncommitted files. Verify the" >&2
        echo "  working copy manually." >&2
    else
        # grep exits 1 when every line is filtered out — the clean case, not an
        # error, so it must not be conflated with the status failure above.
        _stray=$(printf '%s' "$_status_out" \
            | awk 'NF {print $2}' \
            | grep -v -e '/verification\.md$' -e '/pipeline-state\.jsonl$' -e '/verify-gate\.json$') || :
        if [ -n "$_stray" ]; then
            # Deliberately does not claim the verify stage caused these — the
            # script cannot distinguish an edit made during verify from one
            # already pending.
            echo "[specify] WARNING: uncommitted file(s) in the feature dir, NOT" >&2
            echo "  included in this commit (verify commits only its own report):" >&2
            echo "    ${_stray//$'\n'/$'\n'    }" >&2
            echo "  Commit these deliberately with an accurate message." >&2
        fi
    fi
fi

# Add extra paths from environment variable (colon-delimited)
if [ -n "${SPECKIT_COMMIT_EXTRA_PATHS:-}" ]; then
    IFS=':' read -ra _extra <<< "$SPECKIT_COMMIT_EXTRA_PATHS"
    for _ep in "${_extra[@]}"; do
        [ -n "$_ep" ] && _paths+=("$_ep")
    done
fi

# Filter to only paths that have actual changes — sl commit errors on clean directories
_commit_paths=()
for _p in "${_paths[@]}"; do
    if [ -n "$(sl status "$_p" 2>/dev/null)" ]; then
        _commit_paths+=("$_p")
    fi
done
if [ ${#_commit_paths[@]} -eq 0 ]; then
    exit 0
fi

_untracked=""
_untracked=$(sl status -u "${_commit_paths[@]}" 2>/dev/null | awk '{print $2}') || :
if [ -n "$_untracked" ]; then
    echo "$_untracked" | while IFS= read -r f; do
        sl add "$f" 2>/dev/null || :
    done
fi

_for_feature=""
if [ -n "$_feature_name" ]; then
    _for_feature=" for ${_feature_name}"
fi

case "$EVENT_NAME" in
    after_specify)      _msg="${_prefix} [${_feature_name}] Specify" ;;
    after_plan)         _msg="${_prefix} [${_feature_name}] Plan" ;;
    after_tasks)        _msg="${_prefix} [${_feature_name}] Tasks" ;;
    after_review)
        if [ -n "$_feature_name" ]; then
            _msg="${_prefix} [${_feature_name}] Review"
        else
            _msg="${_prefix} Review"
        fi
        ;;
    after_implement)    _msg="${_prefix} [${_feature_name}] Implement" ;;
    verify_complete|after_verify)
        if [ -n "$_feature_name" ]; then
            _msg="${_prefix} [${_feature_name}] Verify"
        else
            _msg="${_prefix} Verify"
        fi
        ;;
    after_constitution) _msg="${_prefix} Update project constitution" ;;
    after_clarify)      _msg="${_prefix} [${_feature_name}] Clarify" ;;
    after_checklist)    _msg="${_prefix} [${_feature_name}] Checklist" ;;
    after_generate)
        if [ -n "$_feature_name" ]; then
            _msg="${_prefix} [${_feature_name}] Generate"
        else
            _msg="${_prefix} Generate"
        fi
        ;;
    after_scan)
        if [ -n "$_feature_name" ]; then
            _msg="${_prefix} [${_feature_name}] Scan"
        else
            _msg="${_prefix} Scan"
        fi
        ;;
    after_setup)
        if [ -n "$_feature_name" ]; then
            _msg="${_prefix} [${_feature_name}] Setup"
        else
            _msg="${_prefix} Setup project configuration"
        fi
        ;;
    *)                  _msg="${_prefix} Auto-commit after ${_command_name}" ;;
esac

# Build commit message body with summary, test plan, and spec reference
_nl=$'\n'
_body=""

# Add summary if provided via environment variable
if [ -n "${SPECKIT_COMMIT_SUMMARY:-}" ]; then
    _body="${_body}${_nl}${_nl}Summary:${_nl}${SPECKIT_COMMIT_SUMMARY}"
fi

# Add test plan if provided via environment variable
if [ -n "${SPECKIT_COMMIT_TEST_PLAN:-}" ]; then
    _body="${_body}${_nl}${_nl}Test Plan:${_nl}${SPECKIT_COMMIT_TEST_PLAN}"
fi

# Add spec reference (except for constitution commits). FEATURE_DIR is
# guaranteed under "$REPO_ROOT/specs/" here — _feature_name is only ever set
# after the specs/-containment check above — so the prefix strip below is
# always well-defined and keeps the trailer repo-relative, not machine-specific.
if [ -n "$_feature_name" ] && [ "$EVENT_NAME" != "after_constitution" ]; then
    _body="${_body}${_nl}${_nl}Spec: ${FEATURE_DIR#"$REPO_ROOT"/}/spec.md"
fi

sl commit "${_commit_paths[@]}" -m "${_msg}${_body}" 2>&1 || {
    echo "[specify] Warning: sl commit failed; changes remain uncommitted" >&2
    exit 0
}

echo "[OK] Spec artifacts committed after ${_command_name}" >&2
