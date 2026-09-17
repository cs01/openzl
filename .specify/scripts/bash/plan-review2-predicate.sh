#!/usr/bin/env bash

# Predicts the after_plan Plan Review dispatch outcome without dispatching it
# (Meta preset). Used by speckit.plan.md's "Review recommendation" section to
# report what will happen next without duplicating dispatch-hooks.sh's YAML
# parsing.
#
# Usage: bash plan-review2-predicate.sh
#
# Output: exactly one of the following tokens on stdout:
#   REVIEW2_AUTO     — a review-family hook is registered under hooks.after_plan
#                       and is mandatory (optional: false)
#   REVIEW2_OFFERED  — a review-family hook is registered and is optional
#                       (optional: true)
#   REVIEW2_MANUAL   — the dispatcher succeeded but no review-family command
#                       is registered under hooks.after_plan
#   REVIEW2_UNKNOWN  — the dispatcher failed; the actual outcome is unknown
#
# This script always exits 0 — its own exit status carries no meaning, the
# outcome is conveyed solely via the stdout token above. REVIEW2_UNKNOWN is a
# normal, successful exit, not a propagated failure.
#
# dispatch-hooks.sh is resolved as a sibling of this script's own installed
# location (matching dispatch-hooks.sh's own BASH_SOURCE-relative resolution
# pattern), not a CWD-relative path, so this file works correctly from both
# the source tree and the installed tree.

set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"

DISPATCH_STATUS=0
DISPATCH_OUTPUT=$(bash "${SCRIPT_DIR}/dispatch-hooks.sh" hooks.after_plan) || DISPATCH_STATUS=$?

if [[ $DISPATCH_STATUS -ne 0 ]]; then
  echo "REVIEW2_UNKNOWN"
else
  REVIEW2_FLAG=$(printf '%s\n' "$DISPATCH_OUTPUT" | awk -F'\t' '$1 ~ /^speckit-review(-plan|-spec)?$/ {print $2; exit}')
  if [[ -z "$REVIEW2_FLAG" ]]; then
    echo "REVIEW2_MANUAL"
  elif [[ "$REVIEW2_FLAG" == "true" ]]; then
    echo "REVIEW2_OFFERED"
  else
    echo "REVIEW2_AUTO"
  fi
fi

exit 0
