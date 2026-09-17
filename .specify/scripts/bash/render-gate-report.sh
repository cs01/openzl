#!/usr/bin/env bash
# Render the blocked-gate report block — findings digest, gate-scope statement,
# carry-forward statement — to stdout. The consuming preset emits stdout
# verbatim.
#
# Consumers: speckit.review-plan.md, speckit.review-spec.md, speckit.verify.md.
#
# The script never exits non-zero on a data condition — only on a usage error
# (exit 2). A data problem must never suppress the caller's mode choice.

set -euo pipefail
SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/common.sh" ]] || { echo "ERROR: common.sh not found — reinstall with 'speckit init'" >&2; exit 1; }
source "$SCRIPT_DIR/common.sh"

_paths_output=$(get_feature_paths) || { echo "ERROR: Failed to resolve feature directory" >&2; exit 1; }
eval "$_paths_output"
unset _paths_output

usage() {
  cat >&2 <<EOF
Usage: $0 --gate-type primary|secondary --must-address N \\
          --quorum-met true|false --auto-mode true|false [--stage review|verify] \\
          [--coverage N/M]
EOF
  exit 2
}

GATE_TYPE=""
MUST_ADDRESS=""
QUORUM_MET=""
AUTO_MODE=""
STAGE="review"
COVERAGE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --gate-type) GATE_TYPE="${2-}"; shift 2 || usage ;;
    --must-address) MUST_ADDRESS="${2-}"; shift 2 || usage ;;
    --quorum-met) QUORUM_MET="${2-}"; shift 2 || usage ;;
    --auto-mode) AUTO_MODE="${2-}"; shift 2 || usage ;;
    --stage) STAGE="${2-}"; shift 2 || usage ;;
    --coverage) COVERAGE="${2-}"; shift 2 || usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

[[ -n "$GATE_TYPE" && -n "$MUST_ADDRESS" \
   && -n "$QUORUM_MET" && -n "$AUTO_MODE" ]] || usage
[[ "$QUORUM_MET" == "true" || "$QUORUM_MET" == "false" ]] || usage
[[ "$AUTO_MODE" == "true" || "$AUTO_MODE" == "false" ]] || usage
[[ "$MUST_ADDRESS" =~ ^[0-9]+$ ]] || usage
[[ "$STAGE" == "review" || "$STAGE" == "verify" ]] || usage
[[ -z "$COVERAGE" || "$COVERAGE" =~ ^[0-9]+/[0-9]+$ ]] || usage

# --gate-type carries the primary/secondary distinction, which only applies to
# the review stage. The verify stage has no such distinction — a caller-passed
# value (e.g. "verify") is accepted without validation, mirroring
# write-review-gate-unified.sh.
if [[ "$STAGE" == "review" ]]; then
  [[ "$GATE_TYPE" == "primary" || "$GATE_TYPE" == "secondary" ]] || usage
fi

if [[ "$STAGE" == "verify" ]]; then
  FINDINGS="$FEATURE_DIR/verification.md"
  GATE="$FEATURE_DIR/verify-gate.json"
elif [[ -f "$FEATURE_DIR/review/review-findings.md" || -f "$FEATURE_DIR/review/review-gate.json" ]]; then
  FINDINGS="$FEATURE_DIR/review/review-findings.md"
  GATE="$FEATURE_DIR/review/review-gate.json"
else
  FINDINGS="$FEATURE_DIR/review-findings.md"
  GATE="$FEATURE_DIR/review-gate.json"
fi

# The closing sentence branches on whether a gate file is on disk. Claiming "no
# gate was recorded" while a gate sits on disk denies enforcement the pipeline
# does perform — a stale blocked gate still makes /speckit-plan refuse and
# /speckit-autopilot halt.
no_verdict_block() {
  cat <<'EOF'
**Review did not produce a findings set.**

The review stage recorded a blocked status but no usable findings were
synthesized — the agent panel failed to reach quorum, or the findings file is
absent or unparseable.

EOF
  if [[ -f "$GATE" ]]; then
    local status
    status=$(sed -n 's/.*"status"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' "$GATE" | head -1)
    [[ -n "$status" ]] || status="unknown"
    cat <<EOF
**This run recorded no gate.** A gate from a previous run is still on disk with
status \`${status}\` — that verdict, not this run, is what \`/speckit-plan\` and
\`/speckit-autopilot\` will act on. Re-run the review to replace it.
EOF
  else
    cat <<'EOF'
**No gate file was recorded, so no pipeline behaviour is affected.** Re-run the
review to get a verdict.
EOF
  fi
}

# Mode 1 — automatic resolution and autonomous runs stay byte-identical.
if [[ "$AUTO_MODE" == "true" ]]; then
  exit 0
fi

# Mode 2 — freshness guard, ordered before the gate-file check. On a re-run a
# stale gate and a stale findings file are both present and look synthesized.
if [[ "$QUORUM_MET" == "false" ]]; then
  no_verdict_block
  exit 0
fi

# Mode 3 — no gate recorded at all.
if [[ ! -f "$GATE" ]]; then
  no_verdict_block
  exit 0
fi

# The passed-gate short-circuit is checked before the empty-blocking-set
# check: a passed gate has zero parseable MUST-ADDRESS findings by
# construction, so checking the latter first would emit the no-verdict block
# on every clean pass, incorrectly — a passed/skip-review/all-PLAN-DEFERRED
# gate is left to the preset's own reporting, not this script's no-verdict
# block. The corruption case is unaffected: it is defined by a nonzero
# --must-address disagreeing with zero parsed.
if [[ "$MUST_ADDRESS" == "0" ]]; then
  exit 0
fi

# Tier extents terminate on any other `###` heading — never on a fixed
# allowlist — so RE-VALIDATION and Gate Override sections can never be absorbed
# into a tier regardless of section order.
parse_findings() {
  awk '
    function sanitize(s,   n) {
      gsub(/\r/, "", s)
      while (match(s, /```+/)) {
        s = substr(s, 1, RSTART - 1) "`" substr(s, RSTART + RLENGTH)
      }
      while (match(s, /^[[:space:]#>*`-]+/)) {
        s = substr(s, RSTART + RLENGTH)
      }
      gsub(/[[:space:]]+/, " ", s)
      sub(/^ /, "", s)
      sub(/ $/, "", s)
      if (length(s) > 200) {
        s = substr(s, 1, 200) "…"
      }
      return s
    }
    # Theme-group content sits between the group-id and the quoted summary as
    # either an em dash or an ASCII double-hyphen — synthesis output in the
    # wild uses both, so both are stripped rather than assumed to be one.
    function strip_theme(content,    q, gidpart, summary, len) {
      q = index(content, "\"")
      if (q == 0) { theme_group_id = ""; theme_summary = ""; return }
      gidpart = substr(content, 1, q - 1)
      summary = substr(content, q + 1)
      len = length(summary)
      if (len > 0 && substr(summary, len, 1) == "\"") {
        summary = substr(summary, 1, len - 1)
      }
      sub(/[ \t]+$/, "", gidpart)
      sub(/--$/, "", gidpart)
      sub(/—$/, "", gidpart)
      sub(/[ \t]+$/, "", gidpart)
      theme_group_id = gidpart
      theme_summary = summary
    }
    function flush() {
      if (id != "") {
        printf "%s\t%s\t%s\t%s\t%s\n", tier, id, sanitize(digest != "" ? digest : title), \
          theme_group_id, (theme_group_id != "" ? sanitize(theme_summary) : "")
      }
      id = ""; title = ""; digest = ""; theme_group_id = ""; theme_summary = ""
    }
    /^### / {
      flush()
      if ($0 ~ /^### MUST-ADDRESS/)         tier = "BLOCKING"
      else if ($0 ~ /^### SHOULD-CONSIDER/) tier = "ATTENTION"
      else if ($0 ~ /^### MINOR/)           tier = "TRIVIAL"
      else                                  tier = ""
      next
    }
    /^#### / {
      flush()
      if (tier != "" && match($0, /^#### [A-Z]+-[0-9]+: /)) {
        line = substr($0, 6)
        colon = index(line, ":")
        id = substr(line, 1, colon - 1)
        title = substr(line, colon + 2)
      }
      next
    }
    /^\*\*Digest\*\*:/ {
      if (id != "") {
        digest = substr($0, 13)
      }
      next
    }
    /^\*\*Theme Group\*\*:/ {
      if (id != "") {
        strip_theme(substr($0, 18))
      }
      next
    }
    END { flush() }
  ' "$1"
}

# Triage disposition — present only on findings files produced by a synthesis
# template that ports the shared triage pipeline (review-spec-synthesis.md,
# review-plan-synthesis.md). A findings file with no `#### By Triage
# Disposition` table parses to empty output, and the caller below treats
# that as "no triage data" rather than an error.
parse_triage_disposition() {
  awk '
    /^#### By Triage Disposition/ { in_table = 1; next }
    /^#### / { in_table = 0 }
    in_table && /^\| Auto-Applied \|/ { n = $0; gsub(/[^0-9]/, "", n); auto_applied = n }
    in_table && /^\| Discarded \|/    { n = $0; gsub(/[^0-9]/, "", n); discarded = n }
    in_table && /^\| Presented \|/    { n = $0; gsub(/[^0-9]/, "", n); presented = n }
    in_table && /^\| Escalated \|/    { n = $0; gsub(/[^0-9]/, "", n); escalated = n }
    END {
      if (auto_applied != "" || discarded != "" || presented != "" || escalated != "") {
        printf "%s\t%s\t%s\t%s\n", auto_applied + 0, discarded + 0, presented + 0, escalated + 0
      }
    }
  ' "$1"
}

RECORDS=""
if [[ -s "$FINDINGS" ]] && grep -q '^### MUST-ADDRESS' "$FINDINGS"; then
  RECORDS=$(parse_findings "$FINDINGS")
fi

BLOCKING=$(printf '%s\n' "$RECORDS" | awk -F'\t' '$1 == "BLOCKING"')

# Mode 4 — the heading may exist while nothing under it parses (heading-depth
# drift, a truncated write, a hand edit). Rendering `**Blocking (10)**` above
# zero lines is an empty severity grouping, which the report format forbids.
if [[ -z "$BLOCKING" ]]; then
  no_verdict_block
  exit 0
fi

# Mode 6 — digest block.
ATTENTION=$(printf '%s\n' "$RECORDS" | awk -F'\t' '$1 == "ATTENTION"')
TRIVIAL=$(printf '%s\n' "$RECORDS" | awk -F'\t' '$1 == "TRIVIAL"')

blocking_count=$(printf '%s\n' "$BLOCKING" | grep -c . || true)
attention_count=$(printf '%s\n' "$ATTENTION" | grep -c . || true)
trivial_count=$(printf '%s\n' "$TRIVIAL" | grep -c . || true)

echo "### Findings"
echo

# Theme grouping — rendering-layer only, built from the group-id/theme-
# summary fields parse_findings() appends to each row. A group-id shared by
# only one finding collapses back to an individual entry: a "theme" of one
# is the flat format, not a wrapper. Grouping and rendering run as a single
# awk pass (not bash associative arrays, which are bash 4+ only and would
# break under macOS's bundled bash 3.2) so the interleaving order matches
# the underlying finding order without a second read of the same data.
printf '%s\n' "$BLOCKING" | awk -F'\t' -v count="$blocking_count" '
  {
    n = NR
    id[n] = $2; digest[n] = $3; gid[n] = $4
    if ($4 != "") {
      group_count[$4]++
      if (!($4 in group_summary)) group_summary[$4] = $5
    }
  }
  END {
    theme_count = 0
    for (g in group_count) {
      if (group_count[g] >= 2) theme_count++
    }
    if (theme_count > 0) {
      word = (theme_count == 1) ? "theme" : "themes"
      printf "**Blocking: %d %s (%d findings)** — these must be addressed or explicitly overridden:\n", theme_count, word, count
    } else {
      printf "**Blocking (%d)** — these must be addressed or explicitly overridden:\n", count
    }
    print ""
    # No cap. Every blocking finding gets a line, either nested under its
    # theme heading (rendered at the position of the group'\''s first member)
    # or as a standalone entry.
    prev = "none"
    for (i = 1; i <= n; i++) {
      g = gid[i]
      if (g != "" && group_count[g] >= 2) {
        if (g in rendered) continue
        rendered[g] = 1
        if (prev != "none") print ""
        printf "**Theme: %s** (%d findings)\n", group_summary[g], group_count[g]
        for (j = 1; j <= n; j++) {
          if (gid[j] == g) printf "- **%s** — %s\n", id[j], digest[j]
        }
        prev = "theme"
      } else {
        if (prev == "theme") print ""
        printf "- **%s** — %s\n", id[i], digest[i]
        prev = "standalone"
      }
    }
  }
'

if [[ "$blocking_count" != "$MUST_ADDRESS" ]]; then
  echo
  echo "⚠️ Preset reported ${MUST_ADDRESS} blocking findings; ${blocking_count} parsed from the findings file."
fi

if [[ "$attention_count" -gt 0 ]]; then
  titles=$(printf '%s\n' "$ATTENTION" | awk -F'\t' '{ printf "%s%s", sep, $3; sep = "; " }')
  echo
  echo "**Worth attention (${attention_count})**: ${titles}"
fi

if [[ "$trivial_count" -gt 0 ]]; then
  [[ "$attention_count" -gt 0 ]] || echo
  echo "**Trivial (${trivial_count})** — see \`${FINDINGS}\`."
fi

# Triage disposition — only present on synthesis output from a template
# that ran triage. Fires on this blocked-gate path only; a passed gate's
# triage summary is surfaced by the dispatching command's own completion
# report instead.
TRIAGE_DISPOSITION=""
if [[ -s "$FINDINGS" ]] && grep -q '^#### By Triage Disposition' "$FINDINGS"; then
  TRIAGE_DISPOSITION=$(parse_triage_disposition "$FINDINGS")
fi

if [[ -n "$TRIAGE_DISPOSITION" ]]; then
  IFS=$'\t' read -r triage_auto_applied triage_discarded triage_presented triage_escalated <<< "$TRIAGE_DISPOSITION"
  echo
  echo "**Triage**: ${triage_auto_applied} auto-applied, ${triage_discarded} discarded, ${triage_presented} presented (${triage_escalated} escalated)"
fi

# Under-covered delivery only — an N==M attempt has nothing to disclose here.
if [[ -n "$COVERAGE" ]]; then
  COVERAGE_N="${COVERAGE%%/*}"
  COVERAGE_M="${COVERAGE#*/}"
  if [[ "$COVERAGE_N" -lt "$COVERAGE_M" ]]; then
    echo
    echo "**Coverage**: ${COVERAGE_N}/${COVERAGE_M} reviewers delivered findings."
  fi
fi

# Per-consumer inventory, not a per-execution-context sentence. Branching this
# on --auto-mode would be provably wrong inside autopilot.
cat <<'EOF'

**What this gate blocks**
- `/speckit-plan` is *instructed* to refuse while the gate is blocked — an agent
  instruction, not a mechanical guard.
- `/speckit-autopilot` reads the gate and halts the run before task generation
  and implementation.
- `/speckit-tasks`, `/speckit-implement` and `/speckit-verify` do not check this
  gate when run directly.
EOF

if [[ "$GATE_TYPE" == "secondary" ]]; then
  cat <<'EOF'
- Re-running `/speckit-review-plan` short-circuits at the secondary-review skip
  guard, so re-review is not an exit.
EOF
fi

cat <<EOF

**If you proceed without resolving**: the findings stay in \`${FINDINGS#"$FEATURE_DIR"/}\`,
annotated with a \`### Gate Override\` record naming them. No later stage reads or
re-surfaces them.
EOF
