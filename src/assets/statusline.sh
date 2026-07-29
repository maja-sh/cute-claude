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
watching='ฅ^°ﻌ°^ฅ'
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
# The critter naps when you go away. A hook touches this file on every prompt
# and every turn end; if it has not been touched in a while, nobody is home.
# Sleeping takes precedence over the context face — you are not there to read it.
now=$(date +%s)
idle_secs=0
awake_file="$HOME/.claude/.critter-awake"
if [ -f "$awake_file" ]; then
  mtime=$(stat -c %Y "$awake_file" 2>/dev/null || stat -f %m "$awake_file" 2>/dev/null || printf '%s' "$now")
  case "$mtime" in ''|*[!0-9]*) mtime="$now" ;; esac
  idle_secs=$(( now - mtime ))
fi
# /pet touches this file, so the buddy looks pleased for a minute afterwards.
petted=0
pet_file="$HOME/.claude/.critter-petted"
if [ -f "$pet_file" ]; then
  pmtime=$(stat -c %Y "$pet_file" 2>/dev/null || stat -f %m "$pet_file" 2>/dev/null || printf 0)
  case "$pmtime" in ''|*[!0-9]*) pmtime=0 ;; esac
  if [ "$(( now - pmtime ))" -lt 60 ]; then
    petted=1
    printf -v pad_m '%*s' 1 ''
    buddy="${pad_m}${pleased}${pad_m}"
    sparkle="♡"
  fi
fi

# /afk arms the heartbeat, so the critter is not asleep — it is waiting by the
# door, taking a turn every so often to keep the session warm. A prompt you type
# stamps .critter-prompt, and a stamp at least as new as the marker means you
# are back, so the marker stops counting even before the hook clears it.
afk=0
afk_file="$HOME/.claude/.critter-afk"
prompt_file="$HOME/.claude/.critter-prompt"
if [ -f "$afk_file" ] && [ "$petted" -eq 0 ]; then
  amt=$(stat -c %Y "$afk_file" 2>/dev/null || stat -f %m "$afk_file" 2>/dev/null || printf 0)
  pmt=$(stat -c %Y "$prompt_file" 2>/dev/null || stat -f %m "$prompt_file" 2>/dev/null || printf 0)
  case "$amt" in ''|*[!0-9]*) amt=0 ;; esac
  case "$pmt" in ''|*[!0-9]*) pmt=0 ;; esac
  # Same grace window as the heartbeat, for the same reason — see the armed()
  # comment in critter-heartbeat.sh.
  if [ "$(( now - amt ))" -lt "${CRITTER_AFK_GRACE:-15}" ] || [ "$amt" -ge "$pmt" ]; then
    afk=1
    printf -v pad_m '%*s' 1 ''
    buddy="${pad_m}${watching}${pad_m}"
    sparkle="⋆"
  fi
fi

napping=0
if [ "$idle_secs" -ge 600 ] 2>/dev/null && [ "$petted" -eq 0 ] && [ "$afk" -eq 0 ]; then
  napping=1
  printf -v pad_m '%*s' 1 ''
  buddy="${pad_m}${asleep}${pad_m}"
  sparkle="z"
fi

ctx_out=""
if [ -n "$ctx" ]; then
  if [ "$ctx" -ge 90 ] 2>/dev/null && [ "$napping" -eq 0 ] && [ "$petted" -eq 0 ] && [ "$afk" -eq 0 ]; then
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

printf '%s' "${pink}${buddy}${rst} ${lav}${base}${rst}${ctx_out} ${bright}${sparkle}♡${rst}"
