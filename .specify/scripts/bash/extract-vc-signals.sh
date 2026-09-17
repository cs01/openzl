#!/usr/bin/env bash
# Extract deterministic version-control signals for scan diff archaeology.
#
# Emits JSON on stdout:
#   {
#     "reverts": [{"diff": "D123", "hash": "abc123", "date": "2026-05-15",
#                  "desc": "Backout of D120 — broke CI"}],
#     "commit_first_lines": ["[SpecKit] Add X", "..."]
#   }
#
# The revert queries live here (not inline in the command template) so the OR
# semantics are executable and unit-tested. Passing one `-k` a pipe-joined value
# never matches: Sapling's `-k`/`--keyword` is a literal, case-insensitive
# substring match and multiple `-k` flags are AND-ed, so the pipe is treated as a
# literal character. OR semantics require one scoped query per keyword variant.
#
# The Sapling binary is resolved via $SL_BIN (default: sl) so tests can inject a
# mock without a live repository.
#
# This script is installed from the SpecKit preset package. Edits made to the
# installed copy under .specify/ are overwritten the next time SpecKit is
# initialized — change the packaged source instead.

set -euo pipefail

SL_BIN="${SL_BIN:-sl}"

usage() {
  cat <<EOF
Usage: $0 --path PATH --start YYYY-MM-DD --end YYYY-MM-DD [--limit N]

Arguments:
  --path PATH    Project path to scope the queries to (required)
  --start DATE   Start of the time window, ISO date (required)
  --end DATE     End of the time window, ISO date (required)
  --limit N      Max commits per query (default: 200)
EOF
  exit 1
}

PATH_ARG=""
START=""
END=""
LIMIT=200

while [[ $# -gt 0 ]]; do
  case $1 in
    --path) PATH_ARG="$2"; shift 2 ;;
    --start) START="$2"; shift 2 ;;
    --end) END="$2"; shift 2 ;;
    --limit) LIMIT="$2"; shift 2 ;;
    -h|--help) usage ;;
    *) echo "Unknown argument: $1" >&2; usage ;;
  esac
done

if [[ -z "$PATH_ARG" || -z "$START" || -z "$END" ]]; then
  echo "Error: --path, --start, and --end are required" >&2
  usage
fi

if [[ ! "$LIMIT" =~ ^[0-9]+$ ]]; then
  echo "Error: --limit must be a positive integer (got '$LIMIT')" >&2
  usage
fi

# firstline keeps one record per line so the TSV parse below stays robust.
# shortdate emits a bare YYYY-MM-DD (isodate would append time + timezone).
REVERT_TMPL='{phabdiff}\t{node|short}\t{date|shortdate}\t{desc|firstline}\n'

# Each variant is a SEPARATE -k query (OR semantics). A single piped -k would be
# a literal AND-ed substring and never match.
REVERT_KEYWORDS=("backout" "revert" "back out")

run_revert_query() {
  local keyword="$1"
  # `--` terminates option parsing so a path starting with `-` can't be read as a
  # flag; the path therefore comes last, after all options.
  "$SL_BIN" log --date "$START to $END" -k "$keyword" \
    -T "$REVERT_TMPL" -l "$LIMIT" \
    --reason "scan diff archaeology revert detection - sl help log" \
    -- "$PATH_ARG"
}

# Per-keyword failures are tolerated so a single keyword variant yielding no
# matches doesn't abort the union under `set -e` — but a genuine per-keyword `sl`
# error is surfaced on stderr (fail visibly) instead of vanishing
# silently. This is deliberately asymmetric with the unguarded commit-conventions
# query below, where a real `sl` failure aborts the whole script rather than
# emitting a silently-empty result.
revert_raw="$(
  for kw in "${REVERT_KEYWORDS[@]}"; do
    run_revert_query "$kw" \
      || echo "WARNING: revert query for keyword '$kw' failed; skipping variant" >&2
  done
)"

# Union + dedup by diff id (phabdiff), falling back to short hash when empty.
# Require the full 4 fields (a short/empty record would yield null date/desc),
# and rejoin any trailing fields into desc so a literal tab inside the commit
# first line can't shift columns or truncate the description downstream.
reverts_json="$(
  printf '%s\n' "$revert_raw" \
    | awk -F'\t' '
        NF >= 4 {
          key = ($1 != "" ? $1 : $2)
          if (key == "" || key in seen) next
          seen[key] = 1
          desc = $4
          for (i = 5; i <= NF; i++) { desc = desc " " $i }
          printf "%s\t%s\t%s\t%s\n", $1, $2, $3, desc
        }' \
    | jq -R -s '
        split("\n")
        | map(select(length > 0) | split("\t"))
        | map({diff: .[0], hash: .[1], date: .[2], desc: .[3]})'
)"

commit_first_lines_json="$(
  "$SL_BIN" log --date "$START to $END" -l "$LIMIT" \
    -T '{desc|firstline}\n' \
    --reason "scan diff archaeology commit conventions - sl help log" \
    -- "$PATH_ARG" \
    | jq -R -s 'split("\n") | map(select(length > 0))'
)"

jq -n \
  --argjson reverts "$reverts_json" \
  --argjson commits "$commit_first_lines_json" \
  '{reverts: $reverts, commit_first_lines: $commits}'
