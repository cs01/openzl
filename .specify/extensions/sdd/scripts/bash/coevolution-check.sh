#!/usr/bin/env bash
# SDD extension: coevolution-check.sh
# Warns when spec-covered code is modified without a corresponding spec update.
# Phase 2 pilot: warns only, does not block.
#
# Usage: coevolution-check.sh
# Exit: always 0 (informational only)

set -euo pipefail

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

REPO_ROOT=$(_find_project_root "$SCRIPT_DIR") || REPO_ROOT="$(pwd)"
cd "$REPO_ROOT"

if ! command -v sl >/dev/null 2>&1; then
    exit 0
fi

if [ ! -d "specs" ]; then
    exit 0
fi

# Parse source files from ### Source Files sections across all specs.
# Outputs one path per line, stripping backticks and inline comments.
_covered_files=""
for spec_file in specs/*/spec.md; do
    [ -f "$spec_file" ] || continue
    _files=$(awk '
        /^### Source Files/ { capture=1; next }
        /^###/ { if (capture) exit }
        capture && /^- / {
            line = $0
            sub(/^- /, "", line)
            gsub(/`/, "", line)
            sub(/ --.*$/, "", line)
            gsub(/^[[:space:]]+|[[:space:]]+$/, "", line)
            if (length(line) > 0) print line
        }
    ' "$spec_file")
    if [ -n "$_files" ]; then
        _covered_files="${_covered_files}${_covered_files:+$'\n'}${_files}"
    fi
done

if [ -z "$_covered_files" ]; then
    exit 0
fi

_status_output=$(sl status 2>/dev/null) || :
if [ -z "$_status_output" ]; then
    exit 0
fi

_changed_files=$(echo "$_status_output" | awk '{print $2}')

_spec_changed=false
while IFS= read -r f; do
    [ -z "$f" ] && continue
    case "$f" in
        specs/*) _spec_changed=true; break ;;
    esac
done <<< "$_changed_files"

if [ "$_spec_changed" = true ]; then
    exit 0
fi

_matches=()
while IFS= read -r covered; do
    [ -z "$covered" ] && continue
    while IFS= read -r changed; do
        [ -z "$changed" ] && continue
        if [ "$covered" = "$changed" ]; then
            _matches+=("$covered")
            break
        fi
    done <<< "$_changed_files"
done <<< "$_covered_files"

if [ ${#_matches[@]} -eq 0 ]; then
    exit 0
fi

echo "[specify] Warning: ${#_matches[@]} spec-covered file(s) modified without a spec update:" >&2
for f in "${_matches[@]}"; do
    echo "  - $f" >&2
done
echo "[specify] Consider updating the relevant spec in specs/ to keep code and specs in sync." >&2
exit 0
