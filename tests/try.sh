#!/usr/bin/env bash
# Spin a throwaway $HOME, install cute-claude into it with the flags you pass,
# then launch Claude Code inside that sandbox. The temp dir auto-cleans on exit.
#
# Usage:   bash tests/try.sh [installer flags...]
# Example: bash tests/try.sh --critter bnuuy --commands --terminal
#
# Needs `claude` on PATH (Claude Code CLI).
set -euo pipefail

cd "$(dirname "$0")/.."
./build.sh >/dev/null

tmp=$(mktemp -d -t cute-XXXXXX)
trap 'rm -rf "$tmp"' EXIT

HOME="$tmp" ./dist/cute.sh "$@"

echo
echo "→ launching claude in $tmp (temp HOME auto-cleans on exit)"
HOME="$tmp" claude
