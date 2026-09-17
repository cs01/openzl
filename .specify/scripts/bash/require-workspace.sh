#!/usr/bin/env bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Uniform workspace-initialization check for every guarded SpecKit entry
# point. Meta-owned (not routed through the upstream-vendored common.sh,
# though it sources and reuses common.sh's find_specify_root()).
#
# Usage: require-workspace.sh
# Success: exit 0, silent (no stdout, no stderr).
# Failure: exit non-zero, one fixed message on stderr — byte-identical to
# presets/meta/rules/speckit-detection.md's wrong-workspace instruction
# (checked mechanically by tests/unit/test_require_workspace.py).
#
# Escape hatch: SPECKIT_WORKSPACE_GUARD=off skips detection entirely and
# exits 0 silently. This is honored unconditionally, in both attended and
# unattended runs — this script has no way to observe which kind of run
# invoked it (that is a property of which agent flow dispatched the call,
# not something a bare script can read). This is a disclosed, known
# limitation named in this project's adopter-facing documentation, not an
# oversight.

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

FAILURE_MESSAGE="No initialized SpecKit workspace was found here. Navigate into an initialized SpecKit workspace, or run the initialization command, and try again."

# A single defaulted expansion, captured into a variable, branched on by
# case-analysis of the captured value only — never a bare $SPECKIT_WORKSPACE_GUARD
# reference (aborts under set -u) and never a branch on a command's exit
# status. An aborting read here would replace the one fixed failure message
# with a shell error on the very first invocation.
_guard_hatch="${SPECKIT_WORKSPACE_GUARD:-on}"

if [[ "$_guard_hatch" == "off" ]]; then
  # Observable trace: the enforcement-mode knob lives in a versioned file, so
  # its use is already recorded; this environment-variable hatch leaves no
  # trail unless this event is emitted.
  # shellcheck disable=SC1091  # telemetry.sh is resolved at runtime, not statically
  { ( source "$SCRIPT_DIR/telemetry.sh" && declare -F speckit_log_event >/dev/null && speckit_log_event workspace_guard_hatch_used "n/a" "unrecorded" "n/a" "skipped" ) || true; } 2>/dev/null
  exit 0
fi

# shellcheck disable=SC1091  # common.sh is resolved at runtime, not statically
if [[ -f "$SCRIPT_DIR/common.sh" ]]; then
  source "$SCRIPT_DIR/common.sh"
  if find_specify_root >/dev/null 2>&1; then
    exit 0
  fi
else
  # common.sh missing is itself "no initialized workspace reachable" for this
  # script's purposes — it does not reimplement find_specify_root's walk.
  :
fi

echo "$FAILURE_MESSAGE" >&2
exit 1
