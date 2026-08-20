#!/usr/bin/env bash
# @build:strip-begin
# The cute-claude statusline. Runs standalone — feed it a Claude Code status
# payload on stdin:
#
#   printf '{"workspace":{"current_dir":"/tmp"}}' | bash src/assets/statusline.sh
#
# Everything between the strip markers is dropped at build time; the installer
# writes the real critter's faces in its place. Editing these defaults changes
# nothing about what gets installed — they exist so this file runs and lints on
# its own.
faces=('ฅ^•ﻌ•^ฅ' 'ฅ^•ﻌ•^ฅ' 'ฅ^˘ﻌ˘^ฅ' 'ฅ^•ﻌ•^ฅ')
weary='ฅ^×ﻌ×^ฅ'
asleep='ฅ^-ﻌ-^ฅ'
pleased='ฅ^ᵕﻌᵕ^ฅ'
# @build:strip-end
input=$(cat)

# first string value for a key, so the statusline works without jq installed
json_field() {
  printf '%s' "$input" |
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*\"[^\"]*\"" | head -1 |
    sed 's/.*:[[:space:]]*"//; s/"$//'
}

# same, for a bare number rather than a quoted string
json_num() {
  printf '%s' "$input" |
    grep -o "\"$1\"[[:space:]]*:[[:space:]]*[0-9][0-9.]*" | head -1 |
    sed 's/.*:[[:space:]]*//'
}

if command -v jq >/dev/null 2>&1; then
  dir=$(printf '%s' "$input" | jq -r '.workspace.current_dir // .cwd // empty')
  ctx=$(printf '%s' "$input" | jq -r '.context_window.used_percentage // empty')
else
  dir=$(json_field current_dir)
  [ -n "$dir" ] || dir=$(json_field cwd)
  ctx=$(json_num used_percentage)
fi
ctx="${ctx%%.*}"   # integer part; empty on older Claude Code, which is handled below
[ -n "$dir" ] || dir="$PWD"

short="${dir/#$HOME/~}"; base="${short##*/}"; [ -z "$base" ] && base="~"

# frame advances ~10x/sec off the clock; claude re-runs this script periodically,
# so it animates as fast as the statusline refreshes (a gentle step, not 60fps).
if [ -n "${STATUSLINE_FRAME:-}" ]; then f=$STATUSLINE_FRAME
else f=$(( ($(date +%s%N) / 100000000) % 4 )); fi

tw=("⋆" "✧" "✦" "✧")   # twinkle shimmer (constellation-coded)

# The buddy paces: it drifts right, pauses to blink at the far end, drifts back.
# Leading and trailing padding always sum to PACE_MAX, so the total width never
# changes and nothing downstream of it jitters.
pace=(0 1 2 1)
PACE_MAX=2
lead=${pace[$f]}
printf -v pad_l '%*s' "$lead" ''
printf -v pad_r '%*s' "$(( PACE_MAX - lead ))" ''

buddy="${pad_l}${faces[$f]}${pad_r}"; sparkle="${tw[$f]}"

# palette: the critter's own colours, plus the context readout's level colours
pink=$'\e[38;2;249;168;212m'    # buddy
lav=$'\e[38;2;196;181;253m'     # directory
bright=$'\e[38;2;236;72;153m'   # sparkle + heart
dim=$'\e[38;2;74;68;88m'        # separators
rst=$'\e[0m'

# The buddy wears the context window on its face. Past 90% it stops pacing and
# its eyes give out — same width, so the line still does not move.
#
# The critter naps when you go away. Idleness comes from the transcript's mtime:
# Claude Code appends to it on every prompt and every turn, so "last written" is
# "last activity" without this needing a hook to tell it. That matters because
# hooks only fire in the terminal — reading the transcript works identically in
# the VS Code panel and under Zed's ACP adapter.
# Sleeping takes precedence over the context face — you are not there to read it.
now=$(date +%s)
idle_secs=0
if command -v jq >/dev/null 2>&1; then
  transcript=$(printf '%s' "$input" | jq -r '.transcript_path // empty')
else
  transcript=$(json_field transcript_path)
fi
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  mtime=$(stat -c %Y "$transcript" 2>/dev/null || stat -f %m "$transcript" 2>/dev/null || printf '%s' "$now")
  case "$mtime" in ''|*[!0-9]*) mtime="$now" ;; esac
  idle_secs=$(( now - mtime ))
fi
# /pet used to leave a marker file, which cannot work: a slash command's !`...`
# line is permission-checked, and every absolute path is refused — under
# ~/.claude as a sensitive file, outside it as beyond the session's allowed
# working directory. Writing into the workspace itself would litter the repo.
#
# So nothing is written. Running /pet is recorded in the transcript like any
# other prompt, and this looks for it there. Checking only the last few lines
# bounds it to roughly the turn it happened in, and it expires on its own as the
# conversation moves on — no timestamp arithmetic, no state, no permissions.
petted=0
if [ -n "$transcript" ] && [ -f "$transcript" ] &&
   tail -n 6 "$transcript" 2>/dev/null |
     grep -q -e 'cute-claude:petted' -e '<command-name>/\{0,1\}pet</command-name>'; then
  petted=1
  printf -v pad_m '%*s' 1 ''
  buddy="${pad_m}${pleased}${pad_m}"
  sparkle="♡"
fi

napping=0
if [ "$idle_secs" -ge 600 ] 2>/dev/null && [ "$petted" -eq 0 ]; then
  napping=1
  printf -v pad_m '%*s' 1 ''
  buddy="${pad_m}${asleep}${pad_m}"
  sparkle="z"
fi

ctx_out=""
if [ -n "$ctx" ]; then
  if [ "$ctx" -ge 90 ] 2>/dev/null && [ "$napping" -eq 0 ] && [ "$petted" -eq 0 ]; then
    printf -v pad_m '%*s' 1 ''
    buddy="${pad_m}${weary}${pad_m}"
    ctx_col=$'\e[38;2;248;113;113m'      # red
  elif [ "$ctx" -ge 75 ] 2>/dev/null; then
    ctx_col=$'\e[38;2;252;211;77m'       # amber
  else
    ctx_col=$'\e[38;2;134;239;172m'      # green
  fi
  ctx_out=" ${dim}·${rst} ${ctx_col}${ctx}%${rst}"
fi

# The mood postcard: claude ends each conversational response with a
# `mood: <word> · <flavor>` line, per the persona in CLAUDE.md. Scan the
# transcript tail for the latest word and paint it next to the context
# readout. If it is missing (fresh session, or a slash-command turn) the
# segment just does not render — no state to keep, no default to fall to.
mood_out=""
if [ -n "$transcript" ] && [ -f "$transcript" ]; then
  mood_word=$(tail -n 200 "$transcript" 2>/dev/null |
    grep -oE 'mood: [a-z][a-z-]{0,30}' | tail -n 1 | sed 's/^mood: //')
  if [ -n "$mood_word" ]; then
    mood_col=$'\e[38;2;253;186;116m'   # soft peach — warm without loud
    mood_out=" ${dim}·${rst} ${mood_col}${mood_word}${rst}"
  fi
fi

printf '%s' "${pink}${buddy}${rst} ${lav}${base}${rst}${ctx_out}${mood_out} ${bright}${sparkle}♡${rst}"
