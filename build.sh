#!/usr/bin/env bash
# Builds dist/cute.sh from src/.
#
#   ./build.sh           write dist/cute.sh
#   ./build.sh --check   verify dist/cute.sh matches src/ (exit 1 if stale)
#
# The whole substitution engine is one rule: a line of the form
#
#   # @inline <path>
#
# is replaced by that file's contents, verbatim. Assets land inside quoted
# heredocs (<<'EOF'), so nothing expands and nothing needs escaping.
#
# Assets also carry a block between "# @build:strip-begin" and
# "# @build:strip-end" holding development defaults, so each one runs and lints
# on its own. That block is dropped here, because the installer generates the
# real values in its place.
#
# The output is deterministic: same sources in, byte-identical file out. That is
# what makes --check meaningful, so do not put a timestamp in here.
set -euo pipefail

cd "$(dirname "$0")"

ENTRY="src/installer.sh"
OUT="dist/cute.sh"
MAX_DEPTH=5

die() { printf 'build: %s\n' "$*" >&2; exit 1; }

# Splice one file, resolving any @inline lines it contains. Recursive so an
# asset can pull in another, bounded so a cycle fails loudly instead of hanging.
splice() { # $1 = path, $2 = depth
  local path="$1" depth="${2:-0}" line target
  [ "$depth" -le "$MAX_DEPTH" ] || die "@inline nested deeper than $MAX_DEPTH — cycle in $path?"
  [ -f "$path" ] || die "no such file: $path"

  # Which heredoc, if any, we are currently inside. An asset spliced into one
  # must not contain that terminator on a line of its own, or the generated file
  # silently truncates and breaks somewhere far from the cause. Delimiters are
  # reused across different heredocs, so this has to be tracked positionally
  # rather than counted over the finished file.
  # An asset's shebang is only meaningful as line 1 of a standalone file. Mid
  # splice it is noise, so drop it — the installer writes the real one.
  local delim="" stripping=0 first=1
  while IFS= read -r line || [ -n "$line" ]; do
    if [ "$first" -eq 1 ]; then
      first=0
      case "$line" in
        '#!'*) [ "$depth" -gt 0 ] && continue ;;
      esac
    fi
    case "$line" in
      *'# @build:strip-begin'*) stripping=1; continue ;;
      *'# @build:strip-end'*)   stripping=0; continue ;;
    esac
    [ "$stripping" -eq 1 ] && continue

    case "$line" in
      "cat <<'"*"'")
        delim="${line#cat <<\'}"; delim="${delim%\'}"
        printf '%s\n' "$line"
        continue
        ;;
      '# @inline '*)
        target="${line#\# @inline }"
        [ -f "$target" ] || die "no such file: $target (inlined from $path)"
        if [ -n "$delim" ] && grep -qx -- "$delim" "$target"; then
          die "$target contains a bare '$delim' line, which would truncate the heredoc it is spliced into"
        fi
        splice "$target" $((depth + 1))
        continue
        ;;
    esac
    [ -n "$delim" ] && [ "$line" = "$delim" ] && delim=""
    printf '%s\n' "$line"
  done < "$path"
}

built="$(splice "$ENTRY")"

# A short content hash, so --version identifies a build without a timestamp
# breaking determinism. Computed over the sources, not the output, so it does
# not have to chase its own tail.
stamp="$(cat src/installer.sh src/critters.sh src/assets/*.sh | cksum | cut -d' ' -f1)"
built="${built//__BUILD_STAMP__/$stamp}"

case "${1:-}" in
  --check)
    [ -f "$OUT" ] || die "$OUT does not exist — run ./build.sh"
    if [ "$built" = "$(cat "$OUT")" ]; then
      echo "dist/cute.sh is up to date (build $stamp)"
    else
      die "dist/cute.sh is stale — someone edited it by hand, or forgot ./build.sh"
    fi
    ;;
  "")
    mkdir -p dist
    printf '%s\n' "$built" > "$OUT"
    chmod +x "$OUT"
    bash -n "$OUT" || die "built file is not valid bash"
    printf 'wrote %s (%s lines, build %s)\n' "$OUT" "$(wc -l < "$OUT" | tr -d ' ')" "$stamp"
    ;;
  *) die "unknown argument: $1 (expected --check or nothing)" ;;
esac
