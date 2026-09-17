#!/usr/bin/env bash
# Append a gate override record to the stage's findings file.
#
# Three causes, three disjoint records:
#   --cause unresolved-findings (default) → `### Gate Override`
#       Subject is the derived unresolved MUST-ADDRESS set.
#   --cause check-failure                 → `### Composition Check Override`
#       Subject is the accepted composition defect, supplied via --subject.
#   --cause constitution_must             → `### Constitution Override`
#       Subject is the overridden constitution finding set, either derived via
#       the same awk-based derivation as unresolved-findings, or supplied
#       directly via --finding-ids (a comma-separated ID list). --finding-ids
#       exists because verify contexts carry V-NNN finding IDs, which the awk
#       derivation cannot identify by heading pattern the way it identifies
#       CC-prefixed review findings.
#
# The three headings are deliberately disjoint strings rather than a base and
# variants. `### Gate Override (check-failure)` contains the legacy heading as
# a substring, so every consumer matching the bare substring would conflate
# the two records — and all three records can now coexist in one run, which is
# a state no consumer saw when there was only one cause.
#
# Consumers: speckit.review-plan.md, speckit.review-spec.md,
# speckit.review-interactive.md, speckit.verify.md, speckit.verify-interactive.md,
# speckit.autopilot.md. The four that pass no --cause use the default and are
# unaffected by the cause dimension.
#
# Scope is the record only, never the state transition. This script does not
# touch review-gate.json and does not invoke write-review-gate-unified.sh — the
# gate rewrite stays in the consuming preset, which must run it only after this
# script exits 0. One mutation, one file, CWD-independent via common.sh.
#
# Exit codes: 0 success · 2 usage error · 3 refused (guard tripped, nothing written)

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/common.sh" ]] || { echo "ERROR: common.sh not found — reinstall with 'speckit init'" >&2; exit 1; }
source "$SCRIPT_DIR/common.sh"

_paths_output=$(get_feature_paths) || { echo "ERROR: Failed to resolve feature directory" >&2; exit 1; }
eval "$_paths_output"
unset _paths_output

usage() {
  cat >&2 <<EOF
Usage: $0 --quorum-met true|false
          [--stage review|verify]
          [--mode spec|constitution]
          [--cause unresolved-findings|check-failure|constitution_must]
          [--subject TEXT]
          [--finding-ids ID[,ID...]]

  --mode         Only meaningful with --stage verify; selects verification.md
                 (spec) vs constitution-verification.md (constitution).
  --cause        Selects the record kind. Defaults to unresolved-findings.
  --subject      Required under --cause check-failure. A usage error under
                 --cause unresolved-findings or --cause constitution_must,
                 whose subjects are derived.
  --finding-ids  Comma-separated finding IDs. Accepted only under
                 --cause constitution_must; when supplied, used directly
                 instead of deriving IDs via awk.
EOF
  exit 2
}

QUORUM_MET=""
STAGE="review"
MODE="spec"
CAUSE="unresolved-findings"
SUBJECT=""
SUBJECT_SUPPLIED="false"
FINDING_IDS=""
FINDING_IDS_SUPPLIED="false"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --quorum-met) QUORUM_MET="${2-}"; shift 2 || usage ;;
    --stage) STAGE="${2-}"; shift 2 || usage ;;
    --mode) MODE="${2-}"; shift 2 || usage ;;
    --cause) CAUSE="${2-}"; shift 2 || usage ;;
    --subject) SUBJECT="${2-}"; SUBJECT_SUPPLIED="true"; shift 2 || usage ;;
    --finding-ids) FINDING_IDS="${2-}"; FINDING_IDS_SUPPLIED="true"; shift 2 || usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$QUORUM_MET" ]] || usage
[[ "$QUORUM_MET" == "true" || "$QUORUM_MET" == "false" ]] || usage
[[ "$STAGE" == "review" || "$STAGE" == "verify" ]] || usage
[[ "$MODE" == "spec" || "$MODE" == "constitution" ]] || usage
[[ "$CAUSE" == "unresolved-findings" || "$CAUSE" == "check-failure" || "$CAUSE" == "constitution_must" ]] || usage

# --subject is a usage error rather than silently ignored under the derived
# causes: the causes are mutually exclusive behaviours, and ignoring it would
# let a caller lose a subject it meant to record.
if [[ "$CAUSE" == "unresolved-findings" && "$SUBJECT_SUPPLIED" == "true" ]]; then
  echo "--subject is not accepted under --cause unresolved-findings (its subject is derived)." >&2
  usage
fi
if [[ "$CAUSE" == "constitution_must" && "$SUBJECT_SUPPLIED" == "true" ]]; then
  echo "--subject is not accepted under --cause constitution_must (its subject is derived)." >&2
  usage
fi
if [[ "$CAUSE" == "check-failure" && -z "$SUBJECT" ]]; then
  echo "--subject is required under --cause check-failure." >&2
  usage
fi

# --finding-ids only makes sense where the awk derivation can't identify
# constitution findings by heading pattern (verify contexts, V-NNN IDs) — it
# is meaningless, not merely redundant, under the other two causes.
if [[ "$FINDING_IDS_SUPPLIED" == "true" && "$CAUSE" != "constitution_must" ]]; then
  echo "--finding-ids is only accepted under --cause constitution_must." >&2
  usage
fi

if [[ "$STAGE" == "verify" ]]; then
  if [[ "$MODE" == "constitution" ]]; then
    FINDINGS="$FEATURE_DIR/constitution-verification.md"
  else
    FINDINGS="$FEATURE_DIR/verification.md"
  fi
elif [[ -f "$FEATURE_DIR/review/review-findings.md" ]]; then
  FINDINGS="$FEATURE_DIR/review/review-findings.md"
else
  FINDINGS="$FEATURE_DIR/review-findings.md"
fi

# Guard 1 — freshness. The existence of a findings file is not evidence that
# this run produced one; on a re-run a stale file is present and looks
# synthesized. Applies to all three causes.
if [[ "$QUORUM_MET" == "false" ]]; then
  echo "Review produced no verdict this run — nothing to override. Re-run the review." >&2
  exit 3
fi

# Guard 2 — idempotence, scoped to the cause. All three records may coexist in
# one run: a skipped-findings override, a composition-check override, and a
# constitution override are different decisions about different subjects. A
# second record of the SAME cause is still refused, and the refusal names the
# cause so the caller can surface it rather than swallow it.
#
# The legacy heading match is anchored to a full line: an unanchored prefix
# would also match any heading beginning `### Gate Override` — wrong on its
# own terms, and it
# would refuse the genuine legacy override once a second record kind exists.
if [[ "$CAUSE" == "check-failure" ]]; then
  if [[ -f "$FINDINGS" ]] && grep -q '^### Composition Check Override$' "$FINDINGS"; then
    echo "Composition check override already recorded." >&2
    exit 3
  fi
elif [[ "$CAUSE" == "constitution_must" ]]; then
  if [[ -f "$FINDINGS" ]] && grep -q '^### Constitution Override$' "$FINDINGS"; then
    echo "Constitution override already recorded." >&2
    exit 3
  fi
else
  if [[ -f "$FINDINGS" ]] && grep -q '^### Gate Override$' "$FINDINGS"; then
    echo "Gate already overridden." >&2
    exit 3
  fi
fi

TIMESTAMP=$(date -u +%Y-%m-%dT%H:%M:%SZ)

# Shared by --cause unresolved-findings and --cause constitution_must (when
# --finding-ids is not supplied). The checkbox test is an anchored full-line
# match, never a substring: a finding whose prose quotes the marker while its
# own checkbox reads [x] would otherwise be counted unresolved, fabricating a
# record that names already-resolved findings.
derive_unresolved() {
  if [[ -s "$FINDINGS" ]]; then
    awk '
      function flush() {
        if (id != "" && unresolved) {
          printf "%s: %s\n", id, title
        }
        id = ""; title = ""; unresolved = 0
      }
      /^### / {
        flush()
        tier = ($0 ~ /^### MUST-ADDRESS/) ? "BLOCKING" : ""
        next
      }
      /^#### / {
        flush()
        if (tier == "BLOCKING" && match($0, /^#### [A-Z]+-[0-9]+: /)) {
          line = substr($0, 6)
          colon = index(line, ":")
          id = substr(line, 1, colon - 1)
          title = substr(line, colon + 2)
        }
        next
      }
      /^- \[ \] Resolved[[:space:]]*$/ {
        if (id != "") {
          unresolved = 1
        }
        next
      }
      END { flush() }
    ' "$FINDINGS"
  fi
}

if [[ "$CAUSE" == "check-failure" ]]; then
  # Sanitise the subject. It is unstructured prose describing a composition
  # defect, so it will frequently quote the artifact — and it is appended to a
  # markdown file this same script's awk later re-parses on column-zero
  # patterns.
  #
  # A newline is rejected rather than collapsed: a second line can land at
  # column zero, where `### `, `#### ` and `- [ ] Resolved` all change how the
  # derivation and the rendered gate report read the file.
  if [[ "$SUBJECT" == *$'\n'* ]]; then
    echo "--subject must be a single line (embedded newline rejected)." >&2
    usage
  fi
  # Leading markdown structure characters are stripped as defence in depth —
  # the subject is emitted after a `**Accepted Defect**: ` prefix and so cannot
  # reach column zero, but nothing about that prefix is guaranteed by a future
  # edit. There is no length cap: truncating a defect description would lose
  # the record's only content, and length is not a corruption vector.
  SUBJECT=$(printf '%s' "$SUBJECT" | sed -E 's/^[[:space:]]*[#>-]+[[:space:]]*//')

  {
    echo
    echo "### Composition Check Override"
    echo
    echo "**Timestamp**: ${TIMESTAMP}"
    echo "**User Acknowledgment**: Gate overridden to PASSED over a composition defect the consistency check could not repair"
    echo "**Accepted Defect**: ${SUBJECT}"
  } >> "$FINDINGS"

  echo "Recorded composition check override."
  exit 0
fi

if [[ "$CAUSE" == "constitution_must" ]]; then
  if [[ -n "$FINDING_IDS" ]]; then
    # Bypass the awk derivation entirely — the caller already identified these
    # IDs via its own dual-signal check, which is precisely the case (verify
    # contexts with V-NNN IDs) the awk derivation cannot handle.
    OVERRIDDEN=$(printf '%s' "$FINDING_IDS" | tr ',' '\n')
  else
    OVERRIDDEN=$(derive_unresolved)
  fi

  if [[ -z "$OVERRIDDEN" ]]; then
    echo "No unresolved blocking findings — gate needs no override." >&2
    exit 3
  fi

  COUNT=$(printf '%s\n' "$OVERRIDDEN" | grep -c . || true)

  {
    echo
    echo "### Constitution Override"
    echo
    echo "**Timestamp**: ${TIMESTAMP}"
    echo "**User Acknowledgment**: Gate overridden to PASSED with ${COUNT} overridden constitution MUST findings"
    echo "**Overridden Constitution Findings**:"
    printf '%s\n' "$OVERRIDDEN" | sed 's/^/- /'
  } >> "$FINDINGS"

  echo "Recorded override of ${COUNT} constitution findings."
  exit 0
fi

UNRESOLVED=$(derive_unresolved)

# Guard 3 — an empty unresolved set means there is nothing for this cause to
# record. It applies to the derived cause only: a composition-check override
# arises precisely when every contributing finding was accepted.
if [[ -z "$UNRESOLVED" ]]; then
  echo "No unresolved blocking findings — gate needs no override." >&2
  exit 3
fi

COUNT=$(printf '%s\n' "$UNRESOLVED" | grep -c . || true)

{
  echo
  echo "### Gate Override"
  echo
  echo "**Timestamp**: ${TIMESTAMP}"
  echo "**User Acknowledgment**: Gate overridden to PASSED with ${COUNT} unresolved MUST-ADDRESS findings"
  echo "**Unresolved MUST-ADDRESS Findings**:"
  printf '%s\n' "$UNRESOLVED" | sed 's/^/- /'
} >> "$FINDINGS"

echo "Recorded override of ${COUNT} unresolved findings."
