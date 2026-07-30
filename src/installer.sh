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
  --append               If ~/.claude/CLAUDE.md already exists and is not ours,
                         add the tone guide below it instead of replacing it.
  --upgrade              Reinstall using the options recorded by the last run,
                         so you do not have to remember which flags you used.
                         Any flag you pass explicitly still overrides them.
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

CLAUDE.md works everywhere, including the VS Code panel and Zed's ACP adapter.

This installs no hooks. Without --terminal it writes CLAUDE.md and nothing else,
so settings.json is never opened and jq is never needed.

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
DO_REVERT=0
DO_LIST=0
DO_APPEND=0
DO_UPGRADE=0
# Which knobs were named on the command line. --upgrade replays what the last
# install recorded, but only for knobs this run did not set explicitly.
CRITTER_SET=0
EXTRA_SET=0
TERMINAL_SET=0
COMMANDS_SET=0

while [ $# -gt 0 ]; do
  case "$1" in
    --critter) CRITTER="${2:-cat}"; CRITTER_SET=1; shift 2 ;;
    --vibe) VIBE="${2:-cute}"; VIBE_SET=1; shift 2 ;;
    --profile) PROFILE="${2:-}"; shift 2 ;;
    --vibe-extra) VIBE_EXTRA="${2:-}"; EXTRA_SET=1; shift 2 ;;
    --terminal) DO_TERMINAL=1; TERMINAL_SET=1; shift ;;
    --commands) DO_COMMANDS=1; COMMANDS_SET=1; shift ;;
    --append) DO_APPEND=1; shift ;;
    --upgrade) DO_UPGRADE=1; shift ;;
    --list) DO_LIST=1; shift ;;
    --revert|--uninstall) DO_REVERT=1; shift ;;
    -h|--help) usage; exit 0 ;;
    --version) echo "cute-claude build __BUILD_STAMP__"; exit 0 ;;
    *) echo "unknown arg: $1" >&2; usage >&2; exit 1 ;;
  esac
done

# Profiles are a base layer only — an explicit --vibe or --terminal still wins,
# so `--profile work --vibe cute` does what it says rather than silently losing.
if [ "$DO_UPGRADE" -eq 1 ] && [ -n "$PROFILE" ]; then
  echo "--upgrade and --profile cannot be combined: both want to be the base" >&2
  echo "  layer under your explicit flags. pick one." >&2
  exit 1
fi

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

MANIFEST="$HOME/.claude/.cute-claude-manifest"
SETTINGS="$HOME/.claude/settings.json"

# Where /pet leaves its marker for the statusline to notice.
#
# NOT under ~/.claude, deliberately. A slash command's !`...` line is
# permission-checked, and Claude Code treats everything in ~/.claude as a
# sensitive file — so a marker there is refused outright:
#
#   Error: Shell command permission check failed ... which is a sensitive file.
#
# It is ephemeral UI state rather than config, so /tmp is where it belongs. The
# path is resolved once here and baked into both the command and the statusline,
# because $TMPDIR is not guaranteed to be the same in both shells. Losing the
# file to a reboot costs nothing: the face simply does not show.
PET_FILE="/tmp/cute-claude-petted-$(id -u 2>/dev/null || echo 0)"

stamp() { date +%Y%m%d-%H%M%S; }

# Does this run need to open settings.json at all?
#
# Two reasons it might. --terminal writes statusLine, spinnerVerbs and the theme
# there. And an install from before hooks were dropped left Stop and
# UserPromptSubmit entries pointing at a heartbeat script this version no longer
# writes, which have to be cleared out or they fire on every turn and fail.
#
# The grep is a cheap detector rather than a precise one: every hook we ever
# wrote has "critter" in its command, and a false positive costs one no-op jq
# pass. Nothing is parsed here, so it needs no jq of its own.
needs_settings() {
  [ "$DO_TERMINAL" -eq 1 ] && return 0
  [ -f "$SETTINGS" ] && grep -q critter "$SETTINGS" 2>/dev/null && return 0
  return 1
}

# jq is the one thing here that is not bash or coreutils, so it is required only
# when settings.json is genuinely in play — see needs_settings above. A plain
# install writes CLAUDE.md and nothing else and never calls this.
#
# When it IS needed, it is needed properly: merging into a settings.json we did
# not write and may not have seen — nested hook arrays, unicode, whatever a
# person has accumulated. A hand-rolled merge would be one regex away from eating
# that file, and this installer's whole promise is that --revert puts it back
# exactly. So: one real JSON tool, checked up front, so a missing dependency is a
# clear message rather than a half-finished install.
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
#   sum      — checksum of a file as we wrote it, to detect later user edits
#   opt      — one install option, so --upgrade can replay this run's flags
#
# Entries are never overwritten on reinstall: the first install's record is the
# one that points at the genuinely pristine file.

manifest_has() {
  [ -f "$MANIFEST" ] || return 1
  local kind path rest
  while IFS=$'\t' read -r kind path rest; do
    case "$kind" in sum|opt) continue ;; esac
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

# Install options are recorded one per line rather than as a single flag string,
# so --upgrade can restore them without eval and without caring that a critter
# name might contain spaces or quotes.
manifest_set_opt() { # $1 = name, $2 = value
  local line drop
  drop="opt	$1	"
  if [ -f "$MANIFEST" ]; then
    while IFS= read -r line; do
      case "$line" in "$drop"*) ;; *) printf '%s\n' "$line" ;; esac
    done < "$MANIFEST" > "$MANIFEST.tmp"
    mv "$MANIFEST.tmp" "$MANIFEST"
  fi
  printf 'opt\t%s\t%s\n' "$1" "$2" >> "$MANIFEST"
}

manifest_opt() { # $1 = name -> prints the recorded value, or nothing
  [ -f "$MANIFEST" ] || return 0
  local kind name val
  while IFS=$'\t' read -r kind name val; do
    if [ "$kind" = "opt" ] && [ "$name" = "$1" ]; then printf '%s' "$val"; return 0; fi
  done < "$MANIFEST"
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
      sum|opt) continue ;;
      settings)
        revert_settings "$path" "$bak" || { failed=1; true; } ;;
      *)
        echo "  ! unknown manifest entry: $kind $path" >&2; failed=1 ;;
    esac
  done < "$MANIFEST"

  # Runtime markers, not installed files, so they are cleaned up rather than
  # restored. The ~/.claude ones are from versions that still used hooks.
  rm -f "$PET_FILE" \
        "$HOME/.claude/.critter-awake" "$HOME/.claude/.critter-petted" \
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

if [ "$DO_UPGRADE" -eq 1 ]; then
  if [ ! -f "$MANIFEST" ]; then
    echo "--upgrade needs a previous install to read options from, and there is" >&2
    echo "  no manifest at $MANIFEST. run it once with the flags you want." >&2
    exit 1
  fi
  v="$(manifest_opt critter)"; [ -n "$v" ] && [ "$CRITTER_SET" -eq 0 ] && CRITTER="$v"
  v="$(manifest_opt vibe)";    [ -n "$v" ] && [ "$VIBE_SET" -eq 0 ] && VIBE="$v"
  v="$(manifest_opt vibe-extra)"; [ -n "$v" ] && [ "$EXTRA_SET" -eq 0 ] && VIBE_EXTRA="$v"
  v="$(manifest_opt terminal)"; [ -n "$v" ] && [ "$TERMINAL_SET" -eq 0 ] && DO_TERMINAL="$v"
  v="$(manifest_opt commands)"; [ -n "$v" ] && [ "$COMMANDS_SET" -eq 0 ] && DO_COMMANDS="$v"
  # A recorded vibe was valid when it was recorded, but the manifest is a plain
  # text file a person can edit, so do not trust it into the generated output.
  case "$VIBE" in
    cute|dry) ;;
    *) echo "the recorded vibe ('$VIBE') is not one this version knows." >&2
       echo "  pass --vibe cute or --vibe dry explicitly." >&2; exit 1 ;;
  esac
  echo "• --upgrade: replaying recorded options (critter: $CRITTER, vibe: $VIBE)"
fi

if [ "$DO_REVERT" -eq 1 ]; then
  # Only the settings entry needs jq to undo; a CLAUDE.md-only install reverts
  # with nothing but cp and rm, so do not demand a dependency it never used.
  if [ -f "$MANIFEST" ] && cut -f1 "$MANIFEST" | grep -qx settings; then
    preflight_deps
  fi
  do_revert
  exit 0
fi

if [ "$DO_LIST" -eq 1 ]; then
  do_list
  exit 0
fi

# ----------------------------------------------------------------- install --

# Checked before anything is written, so a missing jq costs nothing — but only
# asked for when settings.json is actually going to be opened.
needs_settings && preflight_deps

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

# The strained face shown when the context window is nearly full. Eyes become ×,
# which works for every built-in and every pooled face since they all use •.
WEARY="${FACE//•/×}"
if [ "$CRITTER" = "bnuuy" ]; then WEARY='/(×_×)\'; fi
HAPPY="${FACE//•/ᵕ}"
SLEEP="${FACE//•/-}"
if [ "$CRITTER" = "bnuuy" ]; then SLEEP='/(-_-)\'; fi

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

# A CLAUDE.md we have no recorded checksum for is one we never wrote — someone's
# own global instructions. Replacing it is the single most destructive thing
# this script does, and unlike everything else it is a file people hand-write.
# It is still backed up and still revertible, so this warns rather than refuses:
# refusing by default would break the one-line install for the exact people most
# likely to have opinions about it. --append keeps theirs and adds ours below.
FOREIGN_MD=0
if [ -f "$TARGET" ] && [ -z "$(manifest_sum "$TARGET")" ]; then FOREIGN_MD=1; fi

PREFIX_MD=""
if [ "$FOREIGN_MD" -eq 1 ]; then
  if [ "$DO_APPEND" -eq 1 ]; then
    PREFIX_MD="$(cat "$TARGET")"
  else
    echo "  ! $TARGET already exists and was not written by cute-claude."
    echo "    it is backed up below and about to be replaced."
    echo "    to keep yours and add the tone guide underneath instead:"
    echo "        $PROG --append"
  fi
fi

claim "$TARGET"
guard_edits "$TARGET"

{
  if [ -n "$PREFIX_MD" ]; then
    printf '%s\n\n' "$PREFIX_MD"
    printf -- '---\n\n'
  fi
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

# Recorded after the first successful write, so --upgrade replays a run that
# actually got somewhere rather than one that died halfway.
manifest_set_opt critter    "$CRITTER"
manifest_set_opt vibe       "$VIBE"
manifest_set_opt vibe-extra "$VIBE_EXTRA"
manifest_set_opt terminal   "$DO_TERMINAL"
manifest_set_opt commands   "$DO_COMMANDS"

echo "• installed $TARGET  (critter: $CRITTER $EMOJI)"
echo "  ^ this works EVERYWHERE — terminal, VS Code panel, Zed. restart Claude Code to load it."

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

write_statusline() { # $1 path, $2 face, $3 blink, $4 weary, $5 asleep, $6 pleased
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
    # Read from the global rather than threaded through as an argument: it must
    # be byte-identical to the path baked into /pet, so there is one source.
    printf "pet_file='%s'\n" "$PET_FILE"
    cat <<'STATUSLINE_EOF'
# @inline src/assets/statusline.sh
STATUSLINE_EOF
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
  local s="$1" had_hooks=0 what

  [ -f "$s" ] || echo '{}' > "$s"
  grep -q critter "$s" 2>/dev/null && had_hooks=1

  jq --arg cmd "$STATUSLINE_CMD" --argjson verbs "$VERBS" \
     --argjson terminal "$DO_TERMINAL" \
     '(if $terminal == 1 then
           .statusLine = {type:"command", command:$cmd, refreshInterval:1}
         | .spinnerVerbs = {mode:"replace", verbs:$verbs}
         | (if (.theme // "") == "" then .theme = "custom:kitten" else . end)
       else . end)
      # This version installs no hooks. Versions that had /afk left Stop and
      # UserPromptSubmit entries behind, and they would now invoke a heartbeat
      # script that no longer exists, on every turn. Ours are the ones whose
      # command mentions "critter"; anything the user added is untouched.
      | (if has("hooks") then
             .hooks = (.hooks
               | with_entries(.value |= map(select(
                   [.hooks[]?.command | test("critter")] | any | not)))
               | with_entries(select(.value | length > 0)))
           | (if (.hooks | length) == 0 then del(.hooks) else . end)
         else . end)' \
     "$s" 2>/dev/null > "$s.tmp" && mv "$s.tmp" "$s" || {
    rm -f "$s.tmp"
    echo "  ! jq could not read $s (malformed?) — left it alone" >&2
    return 0
  }

  if [ "$DO_TERMINAL" -eq 1 ]; then
    what="statusLine, spinnerVerbs and the theme"
  else
    what="nothing new"
  fi
  echo "  - merged $what into settings.json"
  [ "$had_hooks" -eq 1 ] && echo "  - removed hooks left by an older install (/afk is gone)"
  return 0
}

write_commands() {
  local d="$1"

  cat <<PET > "$d/pet.md"
---
name: pet
description: pet the $CRITTER
disable-model-invocation: true
---
!\`touch "$PET_FILE"\`

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
    "$FACE" "$BLINK" "$WEARY" "$SLEEP" "$HAPPY"
  manifest_set_sum "$HOME/.claude/statusline.sh" "$(file_sum "$HOME/.claude/statusline.sh")"
  echo "  - statusline installed  $FACE"
  echo "  - spinner verbs set to $CRITTER flavor"
fi

# settings.json is opened only when there is a reason to — see needs_settings.
# A default install has none, and never touches it.
if needs_settings; then
  echo
  claim "$SETTINGS" settings
  merge_settings "$SETTINGS"
fi

echo
printf '   ⋆ ˚ ｡ ⋆  %s  ⋆ ｡ ˚ ⋆\n' "$FACE"
echo
echo "done ♡  restart Claude Code."
if [ -f "$0" ]; then
  echo "don't like it? undo everything with:  $0 --revert"
else
  echo "don't like it? undo everything by re-running this the same way, with --revert"
fi
