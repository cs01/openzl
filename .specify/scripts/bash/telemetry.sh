#!/usr/bin/env bash
# (c) Meta Platforms, Inc. and affiliates. Confidential and proprietary.
#
# Shared telemetry emitter for SpecKit pipeline scripts. This file is *sourced*,
# never executed: it defines speckit_log_event, which emits one typed Scuba
# sample to perfpipe_speckit_telemetry through a detached, time-bounded
# scribe_cat child.
#
# Every failure mode is a silent no-op: telemetry must never alter the caller's
# exit code, must never write to its stdout/stderr, and a missing
# scribe_cat is a no-op, not an error. The caller sources this file and
# calls the function inside one terminal safety group; see write-pipeline-state.sh.

_SPECKIT_TELEMETRY_CATEGORY="perfpipe_speckit_telemetry"

# Base field names are reserved. A *forwarded* key colliding with one
# is dropped; the base values arrive on the positional channel instead.
_SPECKIT_BASE_FIELDS=" time seq event_type stage status actor actor_class project feature hostname environment speckit_version upstream_speckit_version "

# Forwarded keys whose Scuba section is int; every other key falls back to
# normal/string. auto_mode/skip_review are booleans encoded 0/1.
_SPECKIT_INT_KEYS=" must_address should_consider minor total_findings agents_completed questions_asked questions_answered auto_resolved auto_mode skip_review constitution_gaps "

# Disabled when SPECKIT_TELEMETRY, trimmed and matched case-insensitively, is one
# of the four disabling tokens; enabled (on by default) for unset/empty/anything
# else. Read as ${SPECKIT_TELEMETRY:-} — an unguarded read aborts the caller
# under nounset, and it is the default path that breaks.
#
# The case arms spell out both cases rather than lowercasing via ${val,,}: that
# expansion is bash 4.0+, and this file must *parse* under the bash 3.2 that macOS
# ships as /bin/bash. A parse error here kills the whole emitter before
# speckit_log_event is even defined, and the caller's safety group swallows it
# silently — telemetry would be dark on that host class with no signal.
_speckit_telemetry_enabled() {
  local val="${SPECKIT_TELEMETRY:-}"
  val="${val#"${val%%[![:space:]]*}"}"
  val="${val%"${val##*[![:space:]]}"}"
  case "$val" in
    0 | [Ff][Aa][Ll][Ss][Ee] | [Nn][Oo] | [Oo][Ff][Ff]) return 1 ;;
    *) return 0 ;;
  esac
}

# SCRIBE_CAT_PATH, when set and non-empty, is an EXCLUSIVE override: resolve it
# or fail closed, with no fall-through to the absolute-path rungs. This diverges
# deliberately from clifoundation's get_scribe_cat_path(), which falls through —
# the divergence is what lets the test harness force a missing-binary no-op on a
# devserver where /usr/local/bin/scribe_cat exists. In production
# SCRIBE_CAT_PATH is unset, so the ladder below runs.
_speckit_resolve_scribe_cat() {
  local override="${SCRIBE_CAT_PATH:-}"
  if [[ -n "$override" ]]; then
    [[ -x "$override" ]] && printf '%s' "$override" && return 0
    return 1
  fi
  local candidate
  for candidate in /usr/local/bin/scribe_cat /host-mounts/sidecars/bin/scribe_cat; do
    [[ -x "$candidate" ]] && printf '%s' "$candidate" && return 0
  done
  command -v scribe_cat >/dev/null 2>&1 && printf '%s' scribe_cat && return 0
  return 1
}

# repo-dir-basename:path-from-repo-root, via a pure-bash upward walk for .hg/.git
# (no subprocess). Falls back to the working-dir basename when no
# repo root is found.
_speckit_project() {
  local dir="$PWD" root=""
  while [[ -n "$dir" ]]; do
    if [[ -e "$dir/.hg" || -e "$dir/.git" ]]; then
      root="$dir"
      break
    fi
    [[ "$dir" == "/" ]] && break
    dir="${dir%/*}"
    [[ -z "$dir" ]] && dir="/"
  done
  if [[ -n "$root" ]]; then
    local base="${root##*/}" rel="${PWD#"$root"}"
    rel="${rel#/}"
    if [[ -n "$rel" ]]; then
      printf '%s:%s' "$base" "$rel"
    else
      printf '%s' "$base"
    fi
  else
    printf '%s' "${PWD##*/}"
  fi
}

# Closed vocabulary (human|service|ci|test|unknown), never inferred past a
# matched signal. The override is clamped: an out-of-vocabulary value maps to
# unknown, not to itself.
_speckit_actor_class() {
  local override="${SPECKIT_TELEMETRY_ACTOR_CLASS:-}"
  if [[ -n "$override" ]]; then
    case "$override" in
      human | service | ci | test | unknown) printf '%s' "$override" ;;
      *) printf 'unknown' ;;
    esac
    return 0
  fi
  if [[ -n "${SANDCASTLE:-}" || -n "${SANDCASTLE_NEXUS_ID:-}" ]]; then
    printf 'ci'
  elif [[ -n "${TW_JOB_USER:-}" || -n "${TW_JOB_NAME:-}" || "${USER:-}" == svc:* ]]; then
    printf 'service'
  elif [[ -n "${USER:-}" ]]; then
    printf 'human'
  else
    printf 'unknown'
  fi
}

# Open-ended classification, defaulting to unknown rather than any named value.
# The OnDemand pattern is unconfirmed, so it degrades safely to unknown.
_speckit_environment() {
  if [[ -n "${SANDCASTLE:-}" || -n "${SANDCASTLE_NEXUS_ID:-}" ]]; then
    printf 'sandcastle'
    return 0
  fi
  if [[ -n "${TW_JOB_NAME:-}" ]]; then
    printf 'tupperware'
    return 0
  fi
  case "${HOSTNAME:-}" in
    devvm*) printf 'devserver' ;;
    *) printf 'unknown' ;;
  esac
}

# Read line 1 (META_VERSION) from the stamp file when present and non-empty, else
# unknown. Fork-free: bash 3.2 parameter expansion only (macOS ships bash 3.2).
_speckit_version() {
  local f=".specify/.speckit-version" content v
  if [[ -f "$f" ]]; then
    content=$(<"$f")
    v="${content%%$'\n'*}"
    v="${v#"${v%%[![:space:]]*}"}"
    v="${v%"${v##*[![:space:]]}"}"
    [[ -n "$v" ]] && printf '%s' "$v" && return 0
  fi
  printf 'unknown'
}

# Read line 2 (upstream_speckit_version=<value>) from the stamp file when present,
# else unknown. Stamp files written before this field existed have no line 2 —
# absence is expected, not an error.
_speckit_upstream_version() {
  local f=".specify/.speckit-version" content rest line v
  if [[ -f "$f" ]]; then
    content=$(<"$f")
    rest="${content#*$'\n'}"
    [[ "$rest" == "$content" ]] && rest=""
    line="${rest%%$'\n'*}"
    if [[ "$line" == upstream_speckit_version=* ]]; then
      v="${line#upstream_speckit_version=}"
      v="${v#"${v%%[![:space:]]*}"}"
      v="${v%"${v##*[![:space:]]}"}"
      [[ -n "$v" ]] && printf '%s' "$v" && return 0
    fi
  fi
  printf 'unknown'
}

# speckit_log_event <event_type> <stage> <seq> <feature> <status> [key=value ...]
#
# Base fields travel on the reserved positional channel; forwarded
# key=value metadata is typed through the int-key table above. Pass an empty string for a
# base field that does not apply (init has no seq or feature).
speckit_log_event() {
  _speckit_telemetry_enabled || return 0

  # Resolve the binary before the jq fork so a missing-binary host short-circuits
  # without paying for payload assembly (fork budget).
  local scribe_cat
  scribe_cat=$(_speckit_resolve_scribe_cat) || return 0
  [[ -n "$scribe_cat" ]] || return 0

  local event_type="${1:-}" stage="${2:-}" seq="${3:-}" feature="${4:-}" status="${5:-}"
  shift 5 2>/dev/null || true

  # Fork-free identity/time derivation.
  local time="${EPOCHSECONDS:-$(date +%s)}"
  local actor="${USER:-}"
  [[ -n "$actor" ]] || actor="unknown"
  local hostname="${HOSTNAME:-}"
  [[ -n "$hostname" ]] || hostname="unknown"
  [[ -n "$event_type" ]] || event_type="unknown"
  [[ -n "$stage" ]] || stage="unknown"

  # Status normalization: completed -> complete, empty -> unset.
  case "$status" in
    completed) status="complete" ;;
    "") status="unset" ;;
  esac

  # Flat (section, key, value) triples handed to jq as positional args, so no
  # value is ever interpolated into the JSON text (avoids every escaping hazard).
  local -a fields=(
    int time "$time"
    normal event_type "$event_type"
    normal stage "$stage"
    normal status "$status"
    normal actor "$actor"
    normal actor_class "$(_speckit_actor_class)"
    normal project "$(_speckit_project)"
    normal hostname "$hostname"
    normal environment "$(_speckit_environment)"
    normal speckit_version "$(_speckit_version)"
    normal upstream_speckit_version "$(_speckit_upstream_version)"
  )
  # seq only when present and integer; feature only when present (init omits both).
  [[ "$seq" =~ ^-?[0-9]+$ ]] && fields+=(int seq "$seq")
  [[ -n "$feature" ]] && fields+=(normal feature "$feature")

  # Forwarded metadata. An arg failing the writer's filter is silently
  # ignored so the event and the JSONL record agree. A key colliding with
  # a base field is dropped.
  local arg key value
  for arg in "$@"; do
    [[ "$arg" =~ ^([a-z_]+)=(.+)$ ]] || continue
    key="${BASH_REMATCH[1]}"
    value="${BASH_REMATCH[2]}"
    case "$_SPECKIT_BASE_FIELDS" in *" $key "*) continue ;; esac
    if [[ "$_SPECKIT_INT_KEYS" == *" $key "* ]]; then
      case "$value" in
        true) value=1 ;;
        false) value=0 ;;
      esac
      # A non-integer value for an int-typed key would produce INVALID_SCUBA_JSON;
      # drop it rather than corrupt the whole sample.
      [[ "$value" =~ ^-?[0-9]+$ ]] || continue
      fields+=(int "$key" "$value")
    else
      fields+=(normal "$key" "$value")
    fi
  done

  # Single synchronous fork. errexit is suppressed inside the caller's
  # ( … ) || true group, so a failed jq does NOT stop execution on its own —
  # the explicit checks are mandatory or an empty sample reaches scribe_cat and
  # is silently dropped by Scuba for lacking int.time.
  local payload
  payload=$(jq -n -c --args '
    reduce range(0; ($ARGS.positional | length); 3) as $i
      ({};
       .[$ARGS.positional[$i]][$ARGS.positional[$i + 1]] =
         (if $ARGS.positional[$i] == "int"
          then ($ARGS.positional[$i + 2] | tonumber)
          else $ARGS.positional[$i + 2]
          end))
  ' "${fields[@]}") || return 0
  [[ -n "$payload" ]] || return 0

  # Detached, fully-redirected, time-bounded child. Degrade gracefully if
  # setsid or timeout is unresolvable rather than disabling telemetry
  # for the whole host class (macOS has no setsid).
  local -a launcher=()
  command -v setsid >/dev/null 2>&1 && launcher+=(setsid)
  command -v timeout >/dev/null 2>&1 && launcher+=(timeout 10)
  ("${launcher[@]}" "$scribe_cat" --minloglevel=5 "$_SPECKIT_TELEMETRY_CATEGORY" <<<"$payload" >/dev/null 2>&1 &) || true
}
