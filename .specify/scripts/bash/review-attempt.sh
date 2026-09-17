#!/usr/bin/env bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Attempt lifecycle for the adversarial review panel: mint, resume, disclose,
# abandon, remove.
#
# Usage:
#   review-attempt.sh init --gate-type <primary|secondary|full-pass> \
#                          --roster "CR:Correctness Reviewer,CV:Coverage Reviewer,RK:Risk Reviewer" \
#                          --attended <true|false> [--ceiling-seconds 900]
#   review-attempt.sh resume --gate-type <primary|secondary|full-pass>
#   review-attempt.sh outstanding
#   review-attempt.sh abandon --attempt-dir <path> \
#                             --reason <ceiling|user-abort|synthesis-failure|infra-failure|partial-coverage> \
#                             --coverage <N/M>
#   review-attempt.sh cleanup --attempt-dir <path> (--gate-file <path> | --no-gate --completion-marker <path>)

set -euo pipefail

SCRIPT_DIR="$(CDPATH="" cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
[[ -f "$SCRIPT_DIR/common.sh" ]] || { echo "ERROR: common.sh not found — reinstall with 'speckit init'" >&2; exit 1; }
# shellcheck disable=SC1091  # common.sh is resolved at runtime, not statically
source "$SCRIPT_DIR/common.sh"

# The reinstall remedy text is shared verbatim with review-wait.sh — both scripts
# hard-depend on jq and must surface the same adopter-facing message rather than
# a raw shell error when it is missing.
# shellcheck disable=SC2016  # the backticks are literal message text, not a command substitution
JQ_MISSING_MSG='The reviewer templates appear to be out of date relative to the review command — no reviewer produced any output. Re-run `speckit init` in this project to reinstall, then re-run the review.'

command -v jq >/dev/null 2>&1 || { echo "$JQ_MISSING_MSG" >&2; exit 3; }

# Never ${TMPDIR:-/tmp} — see contracts/review-attempt-script.md § "Attempt root".
ATTEMPT_BASE="/tmp/speckit-review-$(id -u)"

DEFAULT_CEILING_SECONDS=900
MAX_CEILING_SECONDS=3600
STALENESS_SECONDS=300
AGE_CUTOFF_SECONDS=86400

usage() {
  echo "Usage: review-attempt.sh <init|resume|outstanding|abandon|cleanup> [flags]" >&2
}

# Portable mtime: try BSD `stat -f %m` (BSD/macOS: %m is mtime) first, then
# GNU `stat -c %Y` (GNU: %m is the mount point in both -f and -c mode; %Y is
# the mtime-as-epoch directive). A non-numeric result from the first attempt
# must fall through rather than be trusted, since GNU's `-f %m` succeeds but
# prints a mount point, not an epoch.
get_mtime() {
  local f="$1" m
  if m=$(stat -f %m "$f" 2>/dev/null) && [[ "$m" =~ ^[0-9]+$ ]]; then
    printf '%s' "$m"
    return 0
  fi
  if m=$(stat -c %Y "$f" 2>/dev/null) && [[ "$m" =~ ^[0-9]+$ ]]; then
    printf '%s' "$m"
    return 0
  fi
  return 1
}

get_latest_mtime() {
  local dir="$1" latest=0 f m
  while IFS= read -r f; do
    m=$(get_mtime "$f") || continue
    [ "$m" -gt "$latest" ] && latest=$m
  done < <(find "$dir" -type f 2>/dev/null)
  printf '%s' "$latest"
}

# Bring the attempt root to mode 0700, or refuse to use it.
#
# Mode 0700 is what keeps one user's review findings private: the reviewers
# write as separately dispatched agents rather than as children of this script,
# so a umask set here would never reach them, and only the directory mode binds
# them. Everything below exists because the root's path is predictable and sits
# in a world-writable directory, so another account can get there first:
#
#   - A symlink is refused, never followed. `mkdir -p` is a no-op on one and a
#     chmod through it would retarget the mode change — and then the whole
#     attempt tree — onto a directory the other account chose.
#   - A root owned by anyone else is refused. Its owner could read the findings
#     and also rewrite them, and findings feed synthesis and the gate verdict.
#
# Creation uses `mkdir -m 700` without `-p`, so a root we create is never
# briefly world-readable and can never be an existing symlink: plain `mkdir`
# fails outright when the path exists. Only the already-exists branch validates
# and repairs, which is what tightens a root left permissive by an earlier run.
#
# Pass `create` to mint a missing root, or `existing-only` to leave it absent.
harden_attempt_base() {
  local mode="$1"

  # `existing-only` has to answer "is it there?" before `mkdir`, not after: an
  # unconditional `mkdir` would mint the root it promised to leave absent, so
  # merely listing or resuming would create one where no review had ever run.
  if [[ "$mode" != "create" && ! -e "$ATTEMPT_BASE" && ! -L "$ATTEMPT_BASE" ]]; then
    return 0
  fi

  if mkdir -m 700 "$ATTEMPT_BASE" 2>/dev/null; then
    return 0
  fi

  if [[ ! -e "$ATTEMPT_BASE" && ! -L "$ATTEMPT_BASE" ]]; then
    echo "ERROR: Could not create the attempt root: $ATTEMPT_BASE" >&2
    exit 3
  fi

  if [[ -L "$ATTEMPT_BASE" ]]; then
    echo "ERROR: attempt root is a symlink — refusing to use it: $ATTEMPT_BASE" >&2
    echo "  Remove it, then re-run the review." >&2
    exit 3
  fi

  if [[ ! -d "$ATTEMPT_BASE" ]]; then
    echo "ERROR: attempt root is not a directory — refusing to use it: $ATTEMPT_BASE" >&2
    echo "  Remove it, then re-run the review." >&2
    exit 3
  fi

  # `-O` is a shell builtin test for "owned by the effective uid". Deliberately
  # not `stat`: its owner directive is spelled differently on GNU and BSD, and a
  # probe that cannot read the owner would have to choose between refusing every
  # root (blocking all reviews on that platform) and trusting every root.
  if [[ ! -O "$ATTEMPT_BASE" ]]; then
    echo "ERROR: attempt root is owned by another user — refusing to use it: $ATTEMPT_BASE" >&2
    echo "  Ask its owner to remove it, then re-run the review." >&2
    exit 3
  fi

  if ! chmod 700 "$ATTEMPT_BASE" 2>/dev/null; then
    echo "ERROR: Could not secure the attempt root: $ATTEMPT_BASE" >&2
    exit 3
  fi
}

hex4() {
  printf '%02x%02x' $((RANDOM % 256)) $((RANDOM % 256))
}

# Reads --roster "PFX:Role,PFX:Role,…" into a jq array of {prefix, role}.
parse_roster() {
  local raw="$1" entry prefix role
  local -a json_items=()
  local IFS=','
  for entry in $raw; do
    prefix="${entry%%:*}"
    role="${entry#*:}"
    if [ -z "$prefix" ] || [ "$prefix" = "$entry" ]; then
      echo "ERROR: malformed --roster entry: $entry" >&2
      return 2
    fi
    json_items+=("$(jq -n --arg p "$prefix" --arg r "$role" '{prefix: $p, role: $r}')")
  done
  if [ ${#json_items[@]} -eq 0 ]; then
    echo "ERROR: --roster must contain at least one entry" >&2
    return 2
  fi
  printf '%s\n' "${json_items[@]}" | jq -s .
}

require_feature_dir() {
  local _paths_output
  _paths_output=$(get_feature_paths) || { echo "ERROR: Failed to resolve feature directory" >&2; exit 2; }
  eval "$_paths_output"
}

cmd_init() {
  local gate_type="" roster_raw="" attended="" ceiling_seconds="$DEFAULT_CEILING_SECONDS"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --gate-type) gate_type="$2"; shift 2 ;;
      --roster) roster_raw="$2"; shift 2 ;;
      --attended) attended="$2"; shift 2 ;;
      --ceiling-seconds) ceiling_seconds="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
  done

  if [[ "$gate_type" != "primary" && "$gate_type" != "secondary" && "$gate_type" != "full-pass" ]]; then
    echo "ERROR: --gate-type must be 'primary', 'secondary', or 'full-pass'" >&2
    exit 2
  fi
  if [[ -z "$roster_raw" ]]; then
    echo "ERROR: --roster is required" >&2
    exit 2
  fi
  if [[ "$attended" != "true" && "$attended" != "false" ]]; then
    echo "ERROR: --attended must be 'true' or 'false'" >&2
    exit 2
  fi
  if ! [[ "$ceiling_seconds" =~ ^[0-9]+$ ]]; then
    echo "ERROR: --ceiling-seconds must be a non-negative integer" >&2
    exit 2
  fi
  if [ "$ceiling_seconds" -gt "$MAX_CEILING_SECONDS" ]; then
    echo "ERROR: --ceiling-seconds exceeds the permitted maximum ($MAX_CEILING_SECONDS)" >&2
    exit 2
  fi

  local roster_json
  roster_json=$(parse_roster "$roster_raw") || exit 2

  require_feature_dir
  local feature_slug
  feature_slug="$(basename "$FEATURE_DIR")"

  local attempt_id attempt_dir
  attempt_id="${gate_type}-$(date -u +%Y%m%dT%H%M%SZ)-$(hex4)"
  attempt_dir="$ATTEMPT_BASE/$feature_slug/$attempt_id"

  harden_attempt_base create

  if ! mkdir -p "$attempt_dir/findings" 2>/dev/null; then
    echo "ERROR: Could not create attempt directory: $attempt_dir" >&2
    exit 3
  fi
  mkdir -p "$attempt_dir/debug-signals"

  if ! chmod 700 "$ATTEMPT_BASE/$feature_slug" "$attempt_dir" "$attempt_dir/findings" 2>/dev/null; then
    echo "ERROR: Could not secure the attempt directory: $attempt_dir" >&2
    exit 3
  fi

  local panel_size quorum_required dispatched_at deadline_epoch
  panel_size=$(printf '%s' "$roster_json" | jq 'length')
  quorum_required=$(( panel_size > 1 ? panel_size - 1 : 1 ))
  dispatched_at=$(date +%s)
  deadline_epoch=$((dispatched_at + ceiling_seconds))

  local json
  json=$(cat <<EOF
{
  "attempt_id": "$attempt_id",
  "attempt_dir": "$attempt_dir",
  "gate_type": "$gate_type",
  "feature_dir": "$FEATURE_DIR",
  "roster": $roster_json,
  "panel_size": $panel_size,
  "quorum_required": $quorum_required,
  "dispatched_at": $dispatched_at,
  "ceiling_seconds": $ceiling_seconds,
  "deadline_epoch": $deadline_epoch,
  "synthesis_deadline_epoch": null,
  "extended_seconds": 0,
  "attended": $attended
}
EOF
)

  if ! echo "$json" | jq . > "$attempt_dir/manifest.json"; then
    echo "ERROR: Could not write manifest to: $attempt_dir/manifest.json" >&2
    exit 3
  fi

  echo "ATTEMPT_ID=$attempt_id"
  echo "ATTEMPT_DIR=$attempt_dir"
  echo "PANEL_SIZE=$panel_size"
  echo "QUORUM_REQUIRED=$quorum_required"
  echo "DEADLINE_EPOCH=$deadline_epoch"
  exit 0
}

cmd_resume() {
  local gate_type=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --gate-type) gate_type="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
  done
  if [[ "$gate_type" != "primary" && "$gate_type" != "secondary" && "$gate_type" != "full-pass" ]]; then
    echo "ERROR: --gate-type must be 'primary', 'secondary', or 'full-pass'" >&2
    exit 2
  fi

  # A resume short-circuits init, so without this a pre-fix attempt would be
  # resumed and keep collecting findings under a root this version never
  # tightened. `existing-only`: a missing root means there is nothing to resume,
  # which is the caller's exit-1 case, not a reason to mint a directory here.
  harden_attempt_base existing-only

  require_feature_dir
  local feature_slug attempt_root
  feature_slug="$(basename "$FEATURE_DIR")"
  attempt_root="$ATTEMPT_BASE/$feature_slug"

  [ -d "$attempt_root" ] || exit 1

  local now best_dir="" best_dispatched=-1
  now=$(date +%s)

  shopt -s nullglob
  local d
  for d in "$attempt_root"/*/; do
    d="${d%/}"
    local manifest="$d/manifest.json"
    [ -f "$manifest" ] || continue

    local m_gate_type
    m_gate_type=$(jq -r '.gate_type // empty' "$manifest" 2>/dev/null) || continue
    [ "$m_gate_type" = "$gate_type" ] || continue

    [ -f "$d/abandoned.json" ] && continue

    local m_deadline
    m_deadline=$(jq -r '.deadline_epoch // empty' "$manifest" 2>/dev/null) || continue
    [ -n "$m_deadline" ] || continue
    [ "$now" -le "$m_deadline" ] || continue

    local has_outstanding=false prefix
    while IFS= read -r prefix; do
      [ -f "$d/$prefix.done.json" ] || { has_outstanding=true; break; }
    done < <(jq -r '.roster[].prefix' "$manifest" 2>/dev/null)

    # A fully-marked attempt with no synthesis marker is the
    # session-died-before-synthesis case: every reviewer delivered, so resuming
    # means going straight to synthesis. It is quiet by definition, so the
    # staleness window must not be applied to it — doing so would discard a
    # complete panel five minutes after it finished, which is the recovery this
    # exists for. A fully-marked attempt that *has* synthesised is a concluded
    # run whose directory was merely retained (cleanup refuses at partial
    # coverage, and no abandonment record is written on that path); resuming it
    # would re-synthesise over a previous run's findings while dispatching no
    # reviewers at all.
    if [ "$has_outstanding" = true ]; then
      local latest
      latest=$(get_latest_mtime "$d")
      [ $((now - latest)) -le "$STALENESS_SECONDS" ] || continue
    else
      [ -f "$d/synthesis.done.json" ] && continue
    fi

    local m_dispatched
    m_dispatched=$(jq -r '.dispatched_at // 0' "$manifest" 2>/dev/null)
    if [ "$m_dispatched" -gt "$best_dispatched" ]; then
      best_dispatched=$m_dispatched
      best_dir="$d"
    fi
  done
  shopt -u nullglob

  [ -n "$best_dir" ] || exit 1

  local manifest="$best_dir/manifest.json"
  jq -r '"ATTEMPT_ID=" + .attempt_id,
         "ATTEMPT_DIR=" + .attempt_dir,
         "PANEL_SIZE=" + (.panel_size | tostring),
         "QUORUM_REQUIRED=" + (.quorum_required | tostring),
         "DEADLINE_EPOCH=" + (.deadline_epoch | tostring)' "$manifest"

  # The caller must know whether resuming means waiting for reviewers or going
  # straight to synthesis. Empty means every reviewer already delivered.
  local -a resume_remainder=()
  local rprefix
  while IFS= read -r rprefix; do
    [ -f "$best_dir/$rprefix.done.json" ] || resume_remainder+=("$rprefix")
  done < <(jq -r '.roster[].prefix' "$manifest" 2>/dev/null)
  if [ ${#resume_remainder[@]} -eq 0 ]; then
    echo "RESUME_OUTSTANDING="
  else
    echo "RESUME_OUTSTANDING=$(IFS=,; echo "${resume_remainder[*]}")"
  fi
  exit 0
}

cmd_outstanding() {
  # The review commands run `outstanding` before they mint or resume anything,
  # so this is the first command to touch the root — repairing here tightens a
  # root left permissive by an earlier version at the earliest point in the run,
  # rather than leaving retained attempts exposed until a later init or resume.
  harden_attempt_base existing-only

  require_feature_dir
  local feature_slug attempt_root
  feature_slug="$(basename "$FEATURE_DIR")"
  attempt_root="$ATTEMPT_BASE/$feature_slug"

  [ -d "$attempt_root" ] || exit 0

  local now
  now=$(date +%s)

  local total=0
  local out=""
  shopt -s nullglob
  local d
  for d in "$attempt_root"/*/; do
    d="${d%/}"
    local manifest="$d/manifest.json"
    [ -f "$manifest" ] || continue

    local dispatched_at
    dispatched_at=$(jq -r '.dispatched_at // 0' "$manifest" 2>/dev/null)
    [ $((now - dispatched_at)) -le "$AGE_CUTOFF_SECONDS" ] || continue

    local -a remainder=()
    local prefix
    while IFS= read -r prefix; do
      [ -f "$d/$prefix.done.json" ] || remainder+=("$prefix")
    done < <(jq -r '.roster[].prefix' "$manifest" 2>/dev/null)

    # A fully-marked attempt still sitting here delivered every reviewer and
    # never reached synthesis: its abandonment is missing synthesis, not
    # missing markers. Skipping it is what made a complete panel discarded by a
    # superseding re-dispatch invisible to the pre-dispatch report.
    local awaiting=""
    if [ ${#remainder[@]} -eq 0 ]; then
      [ -f "$d/synthesis.done.json" ] && continue
      awaiting=" awaiting=synthesis"
    fi

    # Counts terminal markers, which includes a `failed` reviewer — deliberately
    # not the data model's coverage, which counts only delivered reviewers. The
    # label says `concluded` so the two figures cannot be read as the same thing.
    local attempt_id panel_size concluded
    attempt_id=$(jq -r '.attempt_id' "$manifest")
    panel_size=$(jq -r '.panel_size' "$manifest")
    concluded=$((panel_size - ${#remainder[@]}))

    local remainder_csv
    if [ ${#remainder[@]} -eq 0 ]; then
      remainder_csv="(none)"
    else
      remainder_csv=$(IFS=,; echo "${remainder[*]}")
    fi

    local detail=""
    if [ -f "$d/abandoned.json" ]; then
      local reason coverage
      reason=$(jq -r '.reason // empty' "$d/abandoned.json" 2>/dev/null)
      coverage=$(jq -r '.coverage // empty' "$d/abandoned.json" 2>/dev/null)
      detail=" reason=$reason abandoned_coverage=$coverage"
    fi

    out="${out}${attempt_id} outstanding=${remainder_csv} concluded=${concluded}/${panel_size}${awaiting}${detail}\n"
    total=$((total + 1))
  done
  shopt -u nullglob

  [ "$total" -eq 0 ] && exit 0

  printf '%b' "$out"
  echo "Total outstanding attempts: $total"
  exit 0
}

cmd_abandon() {
  local attempt_dir="" reason="" coverage=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --attempt-dir) attempt_dir="$2"; shift 2 ;;
      --reason) reason="$2"; shift 2 ;;
      --coverage) coverage="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
  done

  if [[ -z "$attempt_dir" ]]; then
    echo "ERROR: --attempt-dir is required" >&2
    exit 2
  fi
  case "$reason" in
    ceiling|user-abort|synthesis-failure|infra-failure|partial-coverage) ;;
    *) echo "ERROR: --reason must be one of: ceiling, user-abort, synthesis-failure, infra-failure, partial-coverage" >&2; exit 2 ;;
  esac
  if ! [[ "$coverage" =~ ^[0-9]+/[0-9]+$ ]]; then
    echo "ERROR: --coverage must be of the form N/M" >&2
    exit 2
  fi

  local manifest="$attempt_dir/manifest.json"
  [ -f "$manifest" ] || { echo "ERROR: No manifest at: $manifest" >&2; exit 2; }

  local -a outstanding=()
  local prefix
  while IFS= read -r prefix; do
    [ -f "$attempt_dir/$prefix.done.json" ] || outstanding+=("$prefix")
  done < <(jq -r '.roster[].prefix' "$manifest" 2>/dev/null)

  local outstanding_json
  if [ ${#outstanding[@]} -eq 0 ]; then
    outstanding_json="[]"
  else
    outstanding_json=$(printf '%s\n' "${outstanding[@]}" | jq -R . | jq -s .)
  fi

  local attempt_id ended_at
  attempt_id=$(jq -r '.attempt_id' "$manifest")
  ended_at=$(date +%s)

  local json
  json=$(cat <<EOF
{
  "attempt_id": "$attempt_id",
  "ended_at": $ended_at,
  "reason": "$reason",
  "outstanding": $outstanding_json,
  "coverage": "$coverage"
}
EOF
)

  if ! echo "$json" | jq . > "$attempt_dir/abandoned.json"; then
    echo "ERROR: Could not write abandonment record to: $attempt_dir/abandoned.json" >&2
    exit 3
  fi

  echo "$attempt_dir"
  exit 0
}

cmd_cleanup() {
  local attempt_dir="" gate_file="" no_gate="false" completion_marker=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --attempt-dir) attempt_dir="$2"; shift 2 ;;
      --gate-file) gate_file="$2"; shift 2 ;;
      --no-gate) no_gate="true"; shift 1 ;;
      --completion-marker) completion_marker="$2"; shift 2 ;;
      *) echo "ERROR: Unknown argument: $1" >&2; usage; exit 2 ;;
    esac
  done

  if [[ -z "$attempt_dir" ]]; then
    echo "ERROR: --attempt-dir is required" >&2
    exit 2
  fi
  if [[ "$no_gate" == "true" ]]; then
    if [[ -n "$gate_file" || -z "$completion_marker" ]]; then
      echo "ERROR: --no-gate requires --completion-marker and precludes --gate-file" >&2
      exit 2
    fi
  else
    if [[ -z "$gate_file" || -n "$completion_marker" ]]; then
      echo "ERROR: exactly one of --gate-file or (--no-gate --completion-marker) is required" >&2
      exit 2
    fi
  fi

  # Path refusal — must be a single attempt directory directly under the
  # per-feature-slug directory, never the base or a feature-slug directory itself.
  local resolved
  resolved=$(cd -- "$attempt_dir" 2>/dev/null && pwd -P) || {
    echo "ERROR: attempt directory does not exist: $attempt_dir" >&2
    exit 4
  }
  if [[ "$resolved" == "$ATTEMPT_BASE" ]]; then
    echo "ERROR: refusing to remove the attempt root: $resolved" >&2
    exit 4
  fi
  local rel="${resolved#"$ATTEMPT_BASE"/}"
  if [[ "$rel" == "$resolved" ]]; then
    echo "ERROR: path is not under the attempt root: $resolved" >&2
    exit 4
  fi
  local slash_count
  slash_count=$(printf '%s' "$rel" | tr -cd '/' | wc -c)
  if [[ "$slash_count" -ne 1 ]]; then
    echo "ERROR: path is not a single attempt directory: $resolved" >&2
    exit 4
  fi

  local dir_manifest="$resolved/manifest.json"
  local dir_attempt_id=""
  [ -f "$dir_manifest" ] && dir_attempt_id=$(jq -r '.attempt_id // empty' "$dir_manifest" 2>/dev/null)

  local source_file source_attempt_id agents_completed panel_size
  if [[ "$no_gate" == "true" ]]; then
    source_file="$completion_marker"
  else
    source_file="$gate_file"
  fi

  if [[ ! -f "$source_file" ]]; then
    echo "ERROR: attribution source not found: $source_file" >&2
    exit 4
  fi
  source_attempt_id=$(jq -r '.attempt_id // empty' "$source_file" 2>/dev/null)
  if [[ -z "$dir_attempt_id" || "$source_attempt_id" != "$dir_attempt_id" ]]; then
    echo "ERROR: attempt-id mismatch — refusing to clean up: $resolved" >&2
    exit 4
  fi

  agents_completed=$(jq -r '.agents_completed // empty' "$source_file" 2>/dev/null)
  panel_size=$(jq -r '.panel_size // empty' "$source_file" 2>/dev/null)
  if [[ -z "$agents_completed" || -z "$panel_size" || "$agents_completed" -lt "$panel_size" ]]; then
    echo "ERROR: coverage incomplete ($agents_completed/$panel_size) — refusing to clean up: $resolved" >&2
    exit 4
  fi

  if [[ -f "$resolved/abandoned.json" ]]; then
    echo "ERROR: attempt was abandoned — refusing to clean up: $resolved" >&2
    exit 4
  fi

  rm -rf -- "$resolved"
  exit 0
}

[ $# -ge 1 ] || { usage; exit 2; }
subcommand="$1"
shift

case "$subcommand" in
  init) cmd_init "$@" ;;
  resume) cmd_resume "$@" ;;
  outstanding) cmd_outstanding "$@" ;;
  abandon) cmd_abandon "$@" ;;
  cleanup) cmd_cleanup "$@" ;;
  *) echo "ERROR: Unknown subcommand: $subcommand" >&2; usage; exit 2 ;;
esac
