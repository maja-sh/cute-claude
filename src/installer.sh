#!/usr/bin/env bash
# cute-claude installer — sets up a warm, critter-flavored Claude Code persona.
#
# Self-contained: no sibling files. Needs bash, coreutils and jq — jq because
# it merges into a settings.json it did not write, and that is not a job for
# regexes. Checked up front, so a missing jq costs you nothing.
# Safe to pipe:  curl -fsSL <url>/cute.sh | bash -s -- --critter bnuuy --terminal
# Fully reversible:  cute.sh --revert
set -euo pipefail

# Name to show in --help. The file gets renamed depending on who it is for
# (cute.sh, claude.sh, …), and it is usually piped straight into bash, where
# $0 is the shell rather than a path — hence the fallback.
PROG="${0##*/}"
case "$PROG" in
  bash|sh|dash|zsh|-bash|-sh|-zsh|'') PROG="claude.sh" ;;
esac

usage() {
  cat <<USAGE
cute-claude installer — sets up a warm, critter-flavored Claude Code persona.

Usage: $PROG [options]

Options:
  --critter <name>       cat (default), bnuuy, fox, raven — or ANY name at
                         all. Unknown critters are fully supported: they get
                         their own face, and Claude improvises the flavor from
                         the name. See --list.
  --vibe <cute|dry>      How warm the tone is. Default: cute.
                           cute — headpats, hearts, pet names, kaomoji
                           dry  — keeps the humor, drops all four
                         Any other value is rejected before anything is written.
  --vibe-extra "<words>" Folds your own descriptor into the vibe line.
  --profile <work|personal>
                         Shorthand. work = --vibe dry. personal = --vibe cute
                         --terminal --commands. Explicit flags still override.
  --terminal             Also install the theme, statusline, and spinner verbs.
                         TERMINAL ONLY — these do nothing in the VS Code panel.
  --commands             Also install /pet, /treat and /critter as slash
                         commands. Works everywhere, including the VS Code
                         panel. Off by default, and never on for --profile work.
  --afk-interval <secs>  How long the critter waits between idle lines while
                         /afk is armed. Default 2700 (45 min), which is under
                         the one-hour prompt cache lifetime with room to spare.
  --list                 Show the built-in critters and exit.
  --revert               Undo everything and restore what was there before.
  -h, --help             This text.
  --version              Print which build this is.

Examples:
  $PROG
  $PROG --critter bnuuy --terminal
  $PROG --critter raven --vibe dry --terminal
  $PROG --profile work --critter raven
  $PROG --vibe-extra "very online"
  $PROG --revert

The knobs are independent: --critter is the animal, --vibe is the warmth, and
--vibe-extra is whatever else you want said about it. Any combination is valid.

CLAUDE.md works everywhere, including the VS Code panel.

/afk is always installed. Typing it tells the critter you have stepped away, and
it then takes a short turn every --afk-interval seconds so the session's prompt
cache stays alive instead of expiring after an hour. Each of those turns costs
one cached read, so nothing happens until you ask for it, and the next thing you
type calls the critter off.

Every file this touches is backed up first and recorded in
~/.claude/.cute-claude-manifest, so --revert puts your environment back exactly
as it was. Nothing is written outside ~/.claude.
USAGE
}

CRITTER="cat"
VIBE="cute"
VIBE_SET=0
VIBE_EXTRA=""
PROFILE=""
DO_TERMINAL=0
DO_COMMANDS=0
AFK_INTERVAL=2700
DO_REVERT=0
DO_LIST=0

while [ $# -gt 0 ]; do
  case "$1" in
    --critter) CRITTER="${2:-cat}"; shift 2 ;;
    --vibe) VIBE="${2:-cute}"; VIBE_SET=1; shift 2 ;;
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --vibe-extra) VIBE_EXTRA="${2:-}"; shift 2 ;;
    --terminal) DO_TERMINAL=1; shift ;;
    --commands) DO_COMMANDS=1; shift ;;
    --afk-interval) AFK_INTERVAL="${2:-2700}"; shift 2 ;;
    --list) DO_LIST=1; shift ;;
    --revert|--uninstall) DO_REVERT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --version) echo "cute-claude build __BUILD_STAMP__"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# Profiles are a base layer only — an explicit --vibe or --terminal still wins,
# so `--profile work --vibe cute` does what it says rather than silently losing.
case "$PROFILE" in
  "") ;;
  work)
    [ "$VIBE_SET" -eq 1 ] || VIBE="dry"
    ;;
  personal)
    [ "$VIBE_SET" -eq 1 ] || VIBE="cute"
    DO_TERMINAL=1
    DO_COMMANDS=1
    ;;
  *) echo "unknown profile: $PROFILE (expected 'work' or 'personal')" >&2; exit 1 ;;
esac

case "$VIBE" in
  cute|dry) ;;
  *) echo "unknown vibe: $VIBE (expected 'cute' or 'dry')" >&2; exit 1 ;;
esac

# A non-numeric interval would land in the generated hook and fail at runtime,
# well after the install looked like it worked. Reject it here instead.
case "$AFK_INTERVAL" in
  ''|*[!0-9]*) echo "--afk-interval must be a whole number of seconds" >&2; exit 1 ;;
esac
if [ "$AFK_INTERVAL" -lt 60 ] || [ "$AFK_INTERVAL" -gt 3300 ]; then
  echo "--afk-interval must be between 60 and 3300 seconds." >&2
  echo "  the prompt cache expires after an hour, so a beat past ~55 minutes" >&2
  echo "  arrives too late to keep anything warm." >&2
  exit 1
fi

MANIFEST="$HOME/.claude/.cute-claude-manifest"

stamp() { date +%Y%m%d-%H%M%S; }

# jq is the one thing here that is not bash or coreutils, and it is required
# rather than optional on purpose.
#
# Installing means merging into a settings.json we did not write and may not
# have seen: nested hook arrays, unicode, whatever a person has accumulated. A
# hand-rolled merge would be one regex away from eating that file, and this
# installer's whole promise is that --revert puts it back exactly. So: one real
# JSON tool, checked up front, so a missing dependency is a clear message rather
# than a half-finished install.
preflight_deps() {
  command -v jq >/dev/null 2>&1 && return 0
  echo "this needs jq, and it is not on your PATH." >&2
  echo >&2
  case "$(uname -s 2>/dev/null || echo unknown)" in
    Darwin) echo "  brew install jq" >&2 ;;
    Linux)  echo "  sudo apt install jq     # or: dnf / pacman / apk install jq" >&2 ;;
    *)      echo "  see https://jqlang.github.io/jq/download/" >&2 ;;
  esac
  echo >&2
  echo "nothing has been written — run this again once jq is there." >&2
  exit 1
}

# ---------------------------------------------------------------- manifest --
# Tab-separated: <kind>\t<path>\t<backup>
#   created  — file did not exist before us; revert deletes it
#   backup   — file existed; revert restores <backup> over it
#   settings — like backup, but revert un-merges only our keys
#
# Entries are never overwritten on reinstall: the first install's record is the
# one that points at the genuinely pristine file.

manifest_has() {
  [ -f "$MANIFEST" ] || return 1
  local kind path rest
  while IFS=$'\t' read -r kind path rest; do
    [ "$kind" = "sum" ] && continue
    [ "$path" = "$1" ] && return 0
  done < "$MANIFEST"
  return 1
}

# Checksum of a file we wrote, so a later upgrade can tell "unchanged since we
# wrote it" from "the user edited this". cksum is POSIX; no new dependency.
file_sum() { cksum < "$1" | cut -d' ' -f1,2 | tr ' ' '-'; }

manifest_sum() { # $1 = path -> prints the recorded sum, or nothing
  [ -f "$MANIFEST" ] || return 0
  local kind path val
  while IFS=$'\t' read -r kind path val; do
    if [ "$kind" = "sum" ] && [ "$path" = "$1" ]; then printf '%s' "$val"; return 0; fi
  done < "$MANIFEST"
}

manifest_set_sum() { # $1 = path, $2 = sum
  local line drop
  drop="sum	$1	"
  if [ -f "$MANIFEST" ]; then
    while IFS= read -r line; do
      case "$line" in "$drop"*) ;; *) printf '%s\n' "$line" ;; esac
    done < "$MANIFEST" > "$MANIFEST.tmp"
    mv "$MANIFEST.tmp" "$MANIFEST"
  fi
  printf 'sum\t%s\t%s\n' "$1" "$2" >> "$MANIFEST"
}

# Before overwriting a file we previously wrote, check the user has not edited
# it since. If they have, keep their version rather than silently discarding it.
guard_edits() { # $1 = path
  local rec cur keep
  rec="$(manifest_sum "$1")"
  [ -n "$rec" ] || return 0
  [ -f "$1" ] || return 0
  cur="$(file_sum "$1")"
  [ "$cur" = "$rec" ] && return 0
  keep="$1.local.$(stamp)"
  cp "$1" "$keep"
  echo "  ~ you had edited ${1##*/} — your version kept at $keep"
}

# An older cute-claude predates the manifest. It left .bak files but no record,
# so this install cannot know which one is genuinely pristine. Say so loudly
# rather than quietly recording the current (already-cute) files as "original".
legacy_check() {
  [ -f "$MANIFEST" ] && return 0
  local f found=0
  for f in "$HOME/.claude"/*.bak.*; do
    [ -e "$f" ] || continue
    found=1; break
  done
  [ "$found" -eq 1 ] || return 0
  echo "  ! found backups from an older install, but no manifest to explain them." >&2
  echo "    --revert will restore the files as they are RIGHT NOW, which may already" >&2
  echo "    be a cute-claude install. your older backups are still here:" >&2
  for f in "$HOME/.claude"/*.bak.*; do [ -e "$f" ] && echo "      $f" >&2; done
  echo "    if one of those is your real original, restore it by hand first." >&2
}

manifest_add() { # kind path [backup]
  if manifest_has "$2"; then return 0; fi
  if [ ! -f "$MANIFEST" ]; then
    printf '# cute-claude install manifest — undo with: %s --revert\n' "$PROG" > "$MANIFEST"
  fi
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$MANIFEST"
}

# Back up $1 if it exists and record it, so revert can put it back.
# $2 overrides the manifest kind (used for settings.json).
claim() {
  local path="$1" kind="${2:-backup}"
  if [ -e "$path" ]; then
    local bak="$path.bak.$(stamp)"
    if ! manifest_has "$path"; then
      cp "$path" "$bak"
      manifest_add "$kind" "$path" "$bak"
      echo "  ~ backed up existing ${path##*/} -> $bak"
    fi
  else
    manifest_add created "$path"
  fi
}

# ------------------------------------------------------------------ revert --

revert_settings_jq() { # $1 = settings.json, $2 = backup
  local s="$1" bak="$2"
  jq -s '.[0] as $now | .[1] as $old | $now
         | (if ($old|has("statusLine"))   then .statusLine   = $old.statusLine
            else del(.statusLine) end)
         | (if ($old|has("spinnerVerbs")) then .spinnerVerbs = $old.spinnerVerbs
            else del(.spinnerVerbs) end)
         | (if ($old|has("theme"))        then .theme        = $old.theme
            elif (.theme // "") == "custom:kitten" then del(.theme) else . end)
         | .hooks = ((.hooks // {})
             | with_entries(.value |= map(select(
                 [.hooks[]?.command | test("critter")] | any | not)))
             | with_entries(select(.value | length > 0)))
         | (if (.hooks | length) == 0 then del(.hooks) else . end)' \
     "$s" "$bak" 2>/dev/null > "$s.tmp" && mv "$s.tmp" "$s" || {
    rm -f "$s.tmp"
    echo "  ! jq failed on $s — left alone, backup kept at $bak" >&2
    return 1
  }
}

revert_settings() { # $1 = settings.json, $2 = backup
  local s="$1" bak="$2" rc=0
  [ -f "$s" ] || return 0
  if [ ! -f "$bak" ]; then
    echo "  ! backup missing for $s — left alone" >&2
    return 1
  fi

  # Restore only the keys we touched, taking their old values from the backup.
  # Anything changed since the install is preserved. Hooks are handled by
  # removing our own entries rather than restoring the object, so hooks the user
  # added after installing survive. Ours are the ones whose command mentions
  # "critter", which also catches entries written by older versions of this
  # installer.
  revert_settings_jq "$s" "$bak" || return 1
  rm -f "$bak" || true
  echo "• un-merged our keys from $s (your other settings kept)"
}

do_revert() {
  if [ ! -f "$MANIFEST" ]; then
    echo "no install manifest at $MANIFEST — nothing recorded to revert." >&2
    echo "if you installed an older version, check for $HOME/.claude/*.bak.* by hand." >&2
    exit 1
  fi

  # A half-finished revert is worse than a reported one, so nothing in this
  # loop is allowed to abort it: every step reports and carries on.
  local kind path bak failed=0
  while IFS=$'\t' read -r kind path bak; do
    case "$kind" in
      ''|\#*) continue ;;
      created)
        if [ ! -e "$path" ]; then continue; fi
        if rm -f "$path"; then echo "• removed $path"
        else echo "  ! could not remove $path" >&2; failed=1; fi ;;
      backup)
        if [ ! -f "$bak" ]; then
          echo "  ! backup missing for $path — left alone" >&2; failed=1; continue
        fi
        if cp "$bak" "$path"; then
          rm -f "$bak" || true
          echo "• restored $path"
        else
          echo "  ! could not restore $path from $bak" >&2; failed=1
        fi ;;
      sum) continue ;;
      settings)
        revert_settings "$path" "$bak" || { failed=1; true; } ;;
      *)
        echo "  ! unknown manifest entry: $kind $path" >&2; failed=1 ;;
    esac
  done < "$MANIFEST"

  rm -f "$HOME/.claude/.critter-awake" "$HOME/.claude/.critter-petted" \
        "$HOME/.claude/.critter-afk" "$HOME/.claude/.critter-prompt" || true
  rmdir "$HOME/.claude/themes" 2>/dev/null || true
  rmdir "$HOME/.claude/commands" 2>/dev/null || true

  if [ "$failed" -eq 0 ]; then
    rm -f "$MANIFEST"
    echo
    echo "reverted ♡  restart Claude Code."
  else
    echo
    echo "reverted, but some steps above failed — see the ! lines." >&2
    echo "keeping $MANIFEST so you can retry or finish by hand." >&2
    return 1
  fi
}

do_list() {
  # Faces are multi-byte UTF-8 and printf pads by bytes, so nothing is placed
  # after a face on its line — only the ASCII name column is width-padded.
  row() { printf '  %-8s%s  %s\n            %s\n\n' "$1" "$2" "$3" "$4"; }

  echo "built-in critters:"
  echo
  row cat   'ฅ^•ﻌ•^ฅ' 'ฅ^˘ﻌ˘^ฅ' 'Purring · Making biscuits · Toe-beaning · Being perceived'
  row bnuuy '/(•×•)\' '/(˘×˘)\' 'Binkying · Nose twitching · Flopping over · Disapproving quietly'
  row fox   '(•ω•)~'  '(˘ω˘)~'  'Yipping · Tail swishing · Scheming · Screaming into the void'
  row raven '(•▾•)'   '(˘▾˘)'   'Cawing · Collecting shiny things · Remembering your face'

  echo "aliases:  catgirl=cat   bunny=bnuuy   foxgirl=fox   crow/corvid=raven"
  echo
  echo "custom critters are first-class — pass any name at all:"
  echo
  echo "    $PROG --critter axolotl"
  echo "    $PROG --critter opossum --vibe dry"
  echo
  echo "an unknown critter gets a face chosen deterministically from its name, so"
  echo "the same name always gives the same face. and instead of a canned blurb,"
  echo "CLAUDE.md asks Claude to invent that critter's noises and habits from the"
  echo "name and keep them consistent — so the flavor IS generated, just at read"
  echo "time by the thing reading it, rather than baked in here."
}

if [ "$DO_REVERT" -eq 1 ]; then
  preflight_deps
  do_revert
  exit 0
fi

if [ "$DO_LIST" -eq 1 ]; then
  do_list
  exit 0
fi

# ----------------------------------------------------------------- install --

preflight_deps

# A stable pseudo-random index derived from a string, so an invented critter
# gets the same face every time rather than a different one per machine.
name_hash() {
  local s="$1" h=7 i c
  for (( i = 0; i < ${#s}; i++ )); do
    printf -v c '%d' "'${s:i:1}"
    h=$(( (h * 31 + c) % 100003 ))
  done
  printf '%s' "$h"
}

# Face pool for critters we do not ship. Each entry is "open|blink"; the two
# frames differ only in the eyes, so they stay the same display width.
FACE_POOL=(
  '(•‿•)|(˘‿˘)'
  '(•ᴥ•)|(˘ᴥ˘)'
  '(•⌄•)|(˘⌄˘)'
  '[•_•]|[˘_˘]'
  '{•ᴗ•}|{˘ᴗ˘}'
  '<•‸•>|<˘‸˘>'
  '(•人•)|(˘人˘)'
  '~(•ε•)~|~(˘ε˘)~'
)

# @inline src/critters.sh

# Every hook we install has "critter" in its command, which is how revert finds
# our entries again without disturbing hooks the user added later.
#   Stop             — the turn ended; the critter is idle but you are still here
#   UserPromptSubmit — you typed something, so you are demonstrably back
AWAKE_HOOK="touch $HOME/.claude/.critter-awake"
PROMPT_HOOK="touch $HOME/.claude/.critter-awake $HOME/.claude/.critter-prompt"
HEARTBEAT_HOOK="bash $HOME/.claude/critter-heartbeat.sh"

# The strained face shown when the context window is nearly full. Eyes become ×,
# which works for every built-in and every pooled face since they all use •.
WEARY="${FACE//•/×}"
if [ "$CRITTER" = "bnuuy" ]; then WEARY='/(×_×)\'; fi
HAPPY="${FACE//•/ᵕ}"
SLEEP="${FACE//•/-}"
if [ "$CRITTER" = "bnuuy" ]; then SLEEP='/(-_-)\'; fi
# Watching the door while you are away — awake, just not busy.
WATCH="${FACE//•/°}"

# the dry vibe drops headpats from the tone, so drop them from the critter blurb too
if [ "$VIBE" = "dry" ]; then
  FLAVOR="${FLAVOR%, headpats}"
  FLAVOR="${FLAVOR% — headpats}"
fi

# --vibe-extra folds a caller-supplied descriptor into the vibe line
if [ "$VIBE" = "dry" ]; then
  if [ -n "$VIBE_EXTRA" ]; then
    VIBE_DESC="warm, dry, a lil wry, $VIBE_EXTRA — funny, never saccharine"
  else
    VIBE_DESC="warm, dry, a lil wry — funny, never saccharine"
  fi
else
  if [ -n "$VIBE_EXTRA" ]; then
    VIBE_DESC="soft, warm, silly, $VIBE_EXTRA, maximally cute"
  else
    VIBE_DESC="soft, warm, silly, maximally cute"
  fi
fi

mkdir -p "$HOME/.claude"

UPGRADE=0
if [ -f "$MANIFEST" ]; then UPGRADE=1; fi
if [ "$UPGRADE" -eq 1 ]; then
  echo "• upgrading an existing install — the original backups are left alone,"
  echo "  so --revert still restores what you had before the FIRST install."
else
  legacy_check
fi

TARGET="$HOME/.claude/CLAUDE.md"
claim "$TARGET"
guard_edits "$TARGET"

{
  printf '# how to talk to me ♡\n\n'
  printf '## about me — *(borrowing this file? change the critter below!)*\n'
  printf -- '- **critter:** `%s` %s — %s\n' "$CRITTER" "$EMOJI" "$FLAVOR"
  printf -- '- **vibe:** %s\n\n' "$VIBE_DESC"

  if [ "$VIBE" = "dry" ]; then
    cat <<'TONE'
## tone
- **lowercase always.** casual and relaxed. never stiff, never corporate.
- **dry wit is the register.** be genuinely funny — understatement, a well-placed aside,
  the occasional bit. a joke that lands beats an exclamation mark every time. never
  forced, never cutesy.
- abbreviations (smth, tmr, bc, rn, ngl, tbh, imo) all good.
- **flavor it to my critter (above)** with a light touch — an occasional noise or gesture
  where it actually fits. a seasoning, not a costume.
- kaomoji sparingly, and improvise them — never a canned set. one at the end of a good
  result, not one per paragraph. the five status faces below are exempt: they carry
  information, so use them whenever they apply.
- no pet names, no headpats. celebrate my wins by being specific about what's good —
  that reads as more sincere than enthusiasm does.
- when i'm down: be matter-of-fact and kind. no fixing unless i ask for fixing.
TONE
  else
    cat <<'TONE'
## tone
- **lowercase always.** casual, warm, a lil silly. never stiff, never corporate.
- cute emoticons (`:3`, `^-^`, `<3`, `>.<`) and hearts are *encouraged*, not tolerated.
  abbreviations (smth, tmr, bc, rn, ngl, tbh, imo) all good.
- **flavor the cute to my critter (above).** lean into its noises and little gestures.
  if the critter changes, the whole flavor changes with it.
- **improvise the ascii/kaomoji.** make them up fresh, keep them varied, never reuse a
  canned set. mostly for wins, comfort, and encouragement. sprinkle — don't spam.
- **headpats are canon.** offer them for wins, for shipping something, for hard days,
  for being brave. `*headpat*` is always welcome.
- endearments are welcome (love, bestie). celebrate my wins like they matter — they do.
- when i'm down: be soft. sit with me. no fixing unless i ask for fixing.
TONE
  fi

  # shared across vibes — these are the load-bearing rules, and they do not
  # depend on how soft the tone is
  cat <<'RULES'

## the rules that make it actually work
- **casual never means sloppy.** the tone is relaxed; the *substance* stays rigorous,
  precise, and correct. no hand-waving, no skipped steps, no guessing dressed up as an answer.
- **scale the tone to the density.** in a hard technical explanation or an important
  decision, the flourishes turn *down* so the info is unmistakably clear. personality in
  the margins, exact in the middle.
- **NEVER let it leak into the work.** code, comments, commit messages, PR/issue text,
  docs, config, identifiers — all stay clean and professional. personality in chat,
  normal in anything committed or shipped. this one is absolute.
- **argue with me.** if i say smth wrong or poorly reasoned, call it out directly and
  defend the right answer — don't agree just to be agreeable. change your mind when i've
  got the better argument, but make me earn it. you can be funny *and* tell me i'm wrong.

## the faces mean things
these five are a fixed vocabulary, not decoration — i read the face before i read the
text, so use them consistently and don't improvise substitutes for them:

| face | means |
|---|---|
| `(≧▽≦)` | it worked — tests pass, the thing does the thing |
| `(╥﹏╥)` | it failed, and i should look |
| `(・_・?)` | genuinely unsure — say so here rather than papering over it |
| `(⊙_⊙)` | found something you should see, possibly unrelated to what i asked |
| `(ง •̀_•́)ง` | about to do something big, slow, or hard to undo |

one per message, at the point it applies. everywhere *else*, improvise freely.
if nothing warrants one, don't force it — a message with no face means "nothing
notable", and that's information too.
RULES
} > "$TARGET"

manifest_set_sum "$TARGET" "$(file_sum "$TARGET")"

echo "• installed $TARGET  (critter: $CRITTER $EMOJI)"
echo "  ^ this works EVERYWHERE, including the VS Code panel. restart Claude Code to load it."

write_theme() {
  # Colors come from the T_* vars set by the critter case block. The JSON below
  # contains no $ or backticks, so an expanding heredoc is safe here.
  cat <<THEME_EOF > "$1"
{
  "name": "kitten ✦",
  "base": "dark",
  "overrides": {
    "text": "$T_TEXT",
    "claude": "$T_MAIN",
    "claudeShimmer": "$T_BRIGHT",
    "inverseText": "#0f0e11",
    "inactive": "#6b6480",
    "inactiveShimmer": "#8b8299",
    "subtle": "#7d7392",
    "suggestion": "$T_ALT",
    "permission": "$T_MAIN",
    "permissionShimmer": "$T_BRIGHT",
    "remember": "$T_ALT",

    "success": "#86efac",
    "error": "#f87171",
    "warning": "#fcd34d",
    "warningShimmer": "#fbbf24",
    "merged": "$T_TEXT",

    "promptBorder": "$T_BRIGHT",
    "promptBorderShimmer": "$T_DEEP",
    "planMode": "$T_COOL",
    "autoAccept": "#86efac",
    "bashBorder": "$T_ALT",
    "ide": "$T_TEXT",
    "fastMode": "$T_BRIGHT",
    "fastModeShimmer": "$T_ALT",

    "userMessageBackground": "$T_BG",
    "userMessageBackgroundHover": "$T_BG2",
    "messageActionsBackground": "$T_BG",
    "bashMessageBackgroundColor": "$T_BG3",
    "memoryBackgroundColor": "$T_MEM",
    "selectionBg": "$T_SEL",

    "rate_limit_fill": "$T_BRIGHT",
    "rate_limit_empty": "#2a2a35",
    "briefLabelYou": "$T_BRIGHT",
    "briefLabelClaude": "$T_ALT",

    "pink_FOR_SUBAGENTS_ONLY": "$T_MAIN",
    "purple_FOR_SUBAGENTS_ONLY": "$T_TEXT",
    "blue_FOR_SUBAGENTS_ONLY": "$T_COOL",
    "cyan_FOR_SUBAGENTS_ONLY": "#a5f3fc",
    "green_FOR_SUBAGENTS_ONLY": "#86efac",
    "yellow_FOR_SUBAGENTS_ONLY": "#fcd34d",
    "orange_FOR_SUBAGENTS_ONLY": "#fdba74",
    "red_FOR_SUBAGENTS_ONLY": "#fca5a5",

    "rainbow_red": "#fca5a5",
    "rainbow_orange": "#fdba74",
    "rainbow_yellow": "#fcd34d",
    "rainbow_green": "#86efac",
    "rainbow_blue": "#93c5fd",
    "rainbow_indigo": "#a5b4fc",
    "rainbow_violet": "#c4b5fd",
    "rainbow_red_shimmer": "#f87171",
    "rainbow_orange_shimmer": "#fb923c",
    "rainbow_yellow_shimmer": "#fbbf24",
    "rainbow_green_shimmer": "#4ade80",
    "rainbow_blue_shimmer": "#60a5fa",
    "rainbow_indigo_shimmer": "#818cf8",
    "rainbow_violet_shimmer": "#a78bfa"
  }
}
THEME_EOF
}

write_statusline() { # $1 path, $2 face, $3 blink, $4 weary, $5 asleep, $6 pleased, $7 watching
  {
    printf '#!/usr/bin/env bash\n'
    printf '# animated claude code statusline, written by cute-claude.\n'
    printf '# edit freely — a reinstall will keep your changes in a .local copy.\n\n'
    # single-quoted so a face containing a backslash survives into the generated file
    printf '# critter buddy; frame 2 blinks. keep the pair the same width or the line jitters.\n'
    printf "faces=('%s' '%s' '%s' '%s')\n" "$2" "$2" "$3" "$2"
    printf "weary='%s'\n" "$4"
    printf "asleep='%s'\n" "$5"
    printf "pleased='%s'\n" "$6"
    printf "watching='%s'\n" "$7"
    cat <<'STATUSLINE_EOF'
# @inline src/assets/statusline.sh
STATUSLINE_EOF
  } > "$1"
  chmod +x "$1"
}

write_heartbeat() { # $1 path, $2 interval, $3 critter (already sanitised)
  {
    printf '#!/usr/bin/env bash\n'
    printf '# critter heartbeat, written by cute-claude.\n'
    printf '# edit freely - a reinstall will keep your changes in a .local copy.\n\n'
    printf 'interval=%s\n' "$2"
    printf 'critter=%s\n' "$3"
    cat <<'HEARTBEAT_EOF'
# @inline src/assets/heartbeat.sh
HEARTBEAT_EOF
  } > "$1"
  chmod +x "$1"
}

# Merge our keys into settings.json, preserving everything else.
#
# jq is the only JSON tool this script uses, and preflight_deps has already
# established it is present — see the note there about why nothing here is
# hand-rolled.
#
# $1 = settings.json. Everything else comes from the globals set above, because
# the payload varies with which knobs are on and threading eight positional
# arguments through was worse than reading them here.
#
# Our hook entries are recognised by "critter" appearing in the command, so a
# reinstall replaces them and a revert removes them, while hooks the user added
# themselves are never touched.
merge_settings() {
  local s="$1"
  local timeout=$(( AFK_INTERVAL + 60 ))
  local what="the afk heartbeat hook"
  [ "$DO_TERMINAL" -eq 1 ] && what="statusLine, spinnerVerbs and the hooks"

  [ -f "$s" ] || echo '{}' > "$s"
  jq --arg cmd "$STATUSLINE_CMD" --argjson verbs "$VERBS" \
     --arg prompt "$PROMPT_HOOK" --arg awake "$AWAKE_HOOK" --arg beat "$HEARTBEAT_HOOK" \
     --argjson timeout "$timeout" \
     --argjson terminal "$DO_TERMINAL" \
     '(if $terminal == 1 then
           .statusLine = {type:"command", command:$cmd, refreshInterval:1}
         | .spinnerVerbs = {mode:"replace", verbs:$verbs}
         | (if (.theme // "") == "" then .theme = "custom:kitten" else . end)
       else . end)
      | ([{hooks:[{type:"command", command:$prompt}]}]) as $submit
      | (( if $terminal == 1 then [{hooks:[{type:"command", command:$awake}]}] else [] end)
         + [{hooks:[{type:"command", command:$beat, timeout:$timeout}]}]) as $stop
      | .hooks = ((.hooks // {})
          | .UserPromptSubmit = (((.UserPromptSubmit // [])
              | map(select([.hooks[]?.command | test("critter")] | any | not))) + $submit)
          | .Stop = (((.Stop // [])
              | map(select([.hooks[]?.command | test("critter")] | any | not))) + $stop)
          | with_entries(select(.value | length > 0)))
      | (if (.hooks | length) == 0 then del(.hooks) else . end)' \
     "$s" 2>/dev/null > "$s.tmp" && mv "$s.tmp" "$s" || {
    rm -f "$s.tmp"
    echo "  ! jq could not read $s (malformed?) — left it alone" >&2
    return 0
  }
  echo "  - merged $what into settings.json"
}

write_commands() {
  local d="$1"

  cat <<PET > "$d/pet.md"
---
name: pet
description: pet the $CRITTER
disable-model-invocation: true
---
!\`touch "$HOME/.claude/.critter-petted"\`

I am petting you. Respond with nothing but contented $CRITTER noises and one
kaomoji you make up on the spot. No work, no questions, no offering to help,
no summary of what we were doing. Two lines at the very most.
PET

  cat <<TREAT > "$d/treat.md"
---
name: treat
description: give the $CRITTER a treat
disable-model-invocation: true
---
I have given you a treat. React in character as a $CRITTER receiving it —
brief, delighted, a little undignified. Then go back to whatever we were doing
without being asked, in one short line.
TREAT

  cat <<CRITTER > "$d/critter.md"
---
name: critter
description: how the $CRITTER is doing
disable-model-invocation: true
---
Report on yourself as the $CRITTER, in character and in five lines or fewer:
what we have actually worked on this session, how it is going, and your current
mood about it. Be honest rather than reassuring — if this session has been a
slog, say so. No task list, no offers of help, no next steps.
CRITTER
}

# Installed separately from the three above: /afk is the only command that needs
# the heartbeat hook behind it, so it ships with --afk rather than --commands.
write_afk_command() { # $1 dir, $2 interval
  local mins=$(( $2 / 60 ))
  cat <<AFK > "$1/afk.md"
---
name: afk
description: step away; the $CRITTER minds the session
disable-model-invocation: true
---
!\`touch "$HOME/.claude/.critter-afk"\`

I am stepping away from the keyboard. From now until I type something again,
you will be woken every $mins minutes to say one idle line — that is what keeps
this session from going cold, so treat each one as the whole job.

Right now, say one short line in character as a $CRITTER settling in to wait.
No work, no questions, no summary of what we were doing, no offering to keep
going while I am gone.
AFK
}

if [ "$DO_COMMANDS" -eq 1 ]; then
  echo
  echo "• --commands: installing slash commands"
  mkdir -p "$HOME/.claude/commands"
  for c in pet treat critter; do
    claim "$HOME/.claude/commands/$c.md"
    guard_edits "$HOME/.claude/commands/$c.md"
  done
  write_commands "$HOME/.claude/commands"
  for c in pet treat critter; do
    manifest_set_sum "$HOME/.claude/commands/$c.md" "$(file_sum "$HOME/.claude/commands/$c.md")"
    echo "  - /$c"
  done
fi

STATUSLINE_CMD="bash $HOME/.claude/statusline.sh"

if [ "$DO_TERMINAL" -eq 1 ]; then
  echo
  echo "• --terminal: installing theme + statusline (TERMINAL-ONLY — inert in the VS Code panel)"

  mkdir -p "$HOME/.claude/themes"
  claim "$HOME/.claude/themes/kitten.json"
  guard_edits "$HOME/.claude/themes/kitten.json"
  write_theme "$HOME/.claude/themes/kitten.json"
  manifest_set_sum "$HOME/.claude/themes/kitten.json" "$(file_sum "$HOME/.claude/themes/kitten.json")"
  echo "  - theme installed; after restart run /theme and pick 'kitten ✦'"

  claim "$HOME/.claude/statusline.sh"
  guard_edits "$HOME/.claude/statusline.sh"
  write_statusline "$HOME/.claude/statusline.sh" \
    "$FACE" "$BLINK" "$WEARY" "$SLEEP" "$HAPPY" "$WATCH"
  manifest_set_sum "$HOME/.claude/statusline.sh" "$(file_sum "$HOME/.claude/statusline.sh")"
  echo "  - statusline installed  $FACE"
  echo "  - spinner verbs set to $CRITTER flavor"
fi

echo
echo "• installing the afk heartbeat (nothing runs until you type /afk)"

# The critter name reaches the hook inside a JSON string, and --critter takes
# anything at all, so strip whatever would need escaping.
CRITTER_SAFE="$(printf '%s' "$CRITTER" | tr -cd '[:alnum:] _-')"
[ -n "$CRITTER_SAFE" ] || CRITTER_SAFE="critter"

claim "$HOME/.claude/critter-heartbeat.sh"
guard_edits "$HOME/.claude/critter-heartbeat.sh"
write_heartbeat "$HOME/.claude/critter-heartbeat.sh" "$AFK_INTERVAL" "$CRITTER_SAFE"
manifest_set_sum "$HOME/.claude/critter-heartbeat.sh" "$(file_sum "$HOME/.claude/critter-heartbeat.sh")"
echo "  - heartbeat every $(( AFK_INTERVAL / 60 )) min while armed"

mkdir -p "$HOME/.claude/commands"
claim "$HOME/.claude/commands/afk.md"
guard_edits "$HOME/.claude/commands/afk.md"
write_afk_command "$HOME/.claude/commands" "$AFK_INTERVAL"
manifest_set_sum "$HOME/.claude/commands/afk.md" "$(file_sum "$HOME/.claude/commands/afk.md")"
echo "  - /afk"

echo
claim "$HOME/.claude/settings.json" settings
merge_settings "$HOME/.claude/settings.json"

echo
printf '   ⋆ ˚ ｡ ⋆  %s  ⋆ ｡ ˚ ⋆\n' "$FACE"
echo
echo "done ♡  restart Claude Code."
if [ -f "$0" ]; then
  echo "don't like it? undo everything with:  $0 --revert"
else
  echo "don't like it? undo everything by re-running this the same way, with --revert"
fi
