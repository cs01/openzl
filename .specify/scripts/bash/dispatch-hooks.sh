#!/usr/bin/env bash

# Deterministic hook dispatcher (Meta preset).
#
# Parses .specify/extensions.yml with a dependency-free awk state machine and
# emits tab-delimited (command, optional, description) lines for a given hook
# key. Replaces agent-improvised YAML parsing, which caused hooks to silently
# fail in some sessions while working in others.
#
# Usage: bash dispatch-hooks.sh <hook_key>
#   <hook_key> is a dot-separated key, e.g. "hooks.after_plan". A leading
#   "hooks." prefix is stripped to obtain the YAML sub-key looked up under
#   the top-level `hooks:` mapping.
#
# Output: zero or more tab-delimited lines, one per dispatchable hook, in
# extensions.yml declaration order:
#   <command-with-hyphens>\t<optional true|false>\t<description>
#
# Exit codes:
#   0 — success. This includes the key not existing, the key having no
#       entries (block-style empty list or flow-style `key: []`), and all
#       entries being filtered out. Also 0 when .specify/extensions.yml is
#       missing entirely, but with a one-line non-fatal stderr note in that
#       case only.
#   non-zero — .specify/extensions.yml exists but is unreadable/not a
#       regular file, has no top-level `hooks:` mapping, a hook entry never
#       yields a `command:` field before its boundary, a hook entry has an
#       empty `command:` value, a `enabled`/`optional` field has a value
#       other than `true`/`false` (including trailing comments), a hook key
#       uses flow-style populated list syntax (`key: [{...}]`) which this
#       parser cannot faithfully dispatch, or no `.specify/` directory can
#       be located above this script at all.
#
# SPECKIT_EXTENSIONS_FILE (test-only): when set, this exact path is read
# instead of resolving .specify/extensions.yml from the project root, and is
# subject to the identical missing/unreadable rules as the default path.
# Production callers (the preset appendix) never set this.

set -u

HOOK_KEY="${1:-}"
if [ -z "$HOOK_KEY" ]; then
  echo "dispatch-hooks.sh: missing required <hook_key> argument (e.g. hooks.after_plan)" >&2
  exit 1
fi

case "$HOOK_KEY" in
  hooks.*) TARGET_KEY="${HOOK_KEY#hooks.}" ;;
  *) TARGET_KEY="$HOOK_KEY" ;;
esac

if ! printf '%s' "$TARGET_KEY" | grep -qE '^[A-Za-z0-9_]+$'; then
  echo "dispatch-hooks.sh: invalid hook key '$HOOK_KEY' — sub-key must contain only alphanumeric characters and underscores" >&2
  exit 1
fi

# Resolve the extensions.yml path. The appendix always invokes this script
# with CWD at the project root already (the standing convention every
# sibling script relies on) — this resolution is a secondary safety net that
# locates the file relative to the script's own installed location instead
# of trusting `pwd`, so it also works if that assumption is ever violated.
resolve_extensions_file() {
  if [ -n "${SPECKIT_EXTENSIONS_FILE:-}" ]; then
    printf '%s\n' "$SPECKIT_EXTENSIONS_FILE"
    return 0
  fi

  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" >/dev/null 2>&1 && pwd)"
  walk_dir="$script_dir"
  while [ -n "$walk_dir" ] && [ "$walk_dir" != "/" ]; do
    if [ -d "$walk_dir/.specify" ]; then
      printf '%s\n' "$walk_dir/.specify/extensions.yml"
      return 0
    fi
    walk_dir="$(dirname "$walk_dir")"
  done
  return 1
}

if ! EXTENSIONS_FILE="$(resolve_extensions_file)"; then
  echo "dispatch-hooks.sh: cannot locate project root — no .specify/ directory found above $(dirname "${BASH_SOURCE[0]}")" >&2
  exit 1
fi

# Distinguish "no dirent at all" (exit 0 — a missing file means zero
# extensions are registered, a valid state) from "a dirent exists but is not
# a valid readable regular file" (exit non-zero): a directory at the
# expected path, a dangling symlink, or an unreadable file.
if [ -L "$EXTENSIONS_FILE" ] && [ ! -e "$EXTENSIONS_FILE" ]; then
  echo "dispatch-hooks.sh: $EXTENSIONS_FILE is a broken symlink" >&2
  exit 1
fi
if [ ! -e "$EXTENSIONS_FILE" ]; then
  echo "dispatch-hooks.sh: no extension registry found at $EXTENSIONS_FILE — no hooks will run" >&2
  exit 0
fi
if [ -d "$EXTENSIONS_FILE" ]; then
  echo "dispatch-hooks.sh: $EXTENSIONS_FILE is a directory, not a file" >&2
  exit 1
fi
if [ ! -r "$EXTENSIONS_FILE" ]; then
  echo "dispatch-hooks.sh: $EXTENSIONS_FILE is not readable" >&2
  exit 1
fi

awk -v target="$TARGET_KEY" -v hookkey="$HOOK_KEY" '
function leading_ws(s) {
  match(s, /^[[:space:]]*/)
  return RLENGTH
}

function is_blank_or_comment(s,    t) {
  t = s
  sub(/^[[:space:]]*/, "", t)
  return (t == "" || t ~ /^#/)
}

function reset_entry() {
  cur_command = ""
  cur_enabled = ""
  cur_optional = ""
  cur_description = ""
  cur_condition = ""
  entry_has_command = 0
}

function strip_comment(s,    t) {
  t = s
  if (match(t, /[[:space:]]#/)) {
    t = substr(t, 1, RSTART - 1)
    sub(/[[:space:]]+$/, "", t)
  }
  return t
}

function apply_field(fieldline,    colon, key, val) {
  colon = index(fieldline, ":")
  if (colon == 0) return
  key = substr(fieldline, 1, colon - 1)
  val = substr(fieldline, colon + 1)
  sub(/^[[:space:]]+/, "", val)
  sub(/[[:space:]]+$/, "", val)
  if (key == "command") { cur_command = strip_comment(val); entry_has_command = 1 }
  else if (key == "enabled") cur_enabled = strip_comment(val)
  else if (key == "optional") cur_optional = strip_comment(val)
  else if (key == "description") cur_description = val
  else if (key == "condition") cur_condition = strip_comment(val)
  # "extension" and "prompt" are intentionally not matched — prompt text
  # must never leak into the description output.
  # "description" is not comment-stripped — it is display-only output and
  # stripping would silently mutilate a quoted value containing " #".
}

function flush_entry(    enabled_ok, condition_ok, cmdout, opt, desc) {
  if (!in_entry) return
  if (!entry_has_command) {
    printf("dispatch-hooks.sh: malformed hook entry under %s — no command: field found before entry boundary\n", hookkey) > "/dev/stderr"
    err = 1
  } else if (cur_command == "") {
    printf("dispatch-hooks.sh: malformed hook entry under %s — empty command: value\n", hookkey) > "/dev/stderr"
    err = 1
  } else if (cur_enabled != "" && cur_enabled != "true" && cur_enabled != "false") {
    printf("dispatch-hooks.sh: hook %s under %s has unrecognized enabled value \"%s\" — must be true, false, or absent\n", cur_command, hookkey, cur_enabled) > "/dev/stderr"
    err = 1
  } else if (cur_optional != "" && cur_optional != "true" && cur_optional != "false") {
    printf("dispatch-hooks.sh: hook %s under %s has unrecognized optional value \"%s\" — must be true, false, or absent\n", cur_command, hookkey, cur_optional) > "/dev/stderr"
    err = 1
  } else {
    enabled_ok = (cur_enabled != "false")
    condition_ok = (cur_condition == "" || cur_condition == "null")
    if (!condition_ok) {
      printf("dispatch-hooks.sh: hook %s under %s excluded — non-null condition\n", cur_command, hookkey) > "/dev/stderr"
    }
    if (enabled_ok && condition_ok) {
      cmdout = cur_command
      gsub(/\./, "-", cmdout)
      opt = (cur_optional == "" ? "false" : cur_optional)
      desc = cur_description
      gsub(/\t/, " ", desc)
      gsub(/\n/, " ", desc)
      printf("%s\t%s\t%s\n", cmdout, opt, desc)
    }
  }
  in_entry = 0
  reset_entry()
}

BEGIN {
  in_hooks = 0
  hooks_indent = -1
  found_target = 0
  target_indent = -1
  target_done = 0
  in_entry = 0
  err = 0
  reset_entry()
}

{
  if (target_done) next

  line = $0
  if (is_blank_or_comment(line)) next
  indent = leading_ws(line)
  stripped = line
  sub(/^[[:space:]]*/, "", stripped)

  if (!in_hooks) {
    if (indent == 0 && stripped ~ /^hooks:[[:space:]]*$/) {
      in_hooks = 1
      hooks_indent = indent
    }
    next
  }

  if (!found_target) {
    if (indent <= hooks_indent && stripped !~ /^-/) {
      target_done = 1
      next
    }
    if (stripped ~ ("^" target ":[[:space:]]*\\[\\][[:space:]]*$")) {
      found_target = 1
      target_done = 1
      next
    }
    if (stripped ~ ("^" target ":[[:space:]]*\\[")) {
      printf("dispatch-hooks.sh: flow-style list under %s is not supported — use block-style YAML (indented entries starting with -)\n", hookkey) > "/dev/stderr"
      err = 1
      target_done = 1
      next
    }
    if (stripped ~ ("^" target ":[[:space:]]*$")) {
      found_target = 1
      target_indent = indent
      next
    }
    next
  }

  if (stripped ~ /^-/) {
    flush_entry()
    in_entry = 1
    rest = stripped
    sub(/^-[[:space:]]*/, "", rest)
    if (rest != "") apply_field(rest)
    next
  }

  if (indent <= target_indent) {
    flush_entry()
    target_done = 1
    next
  }

  if (in_entry) apply_field(stripped)
  next
}

END {
  if (!in_hooks) {
    printf("dispatch-hooks.sh: no top-level hooks mapping found in %s\n", FILENAME) > "/dev/stderr"
    err = 1
  } else {
    flush_entry()
  }
  exit (err ? 1 : 0)
}
' "$EXTENSIONS_FILE"
exit $?
