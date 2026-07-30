#!/usr/bin/env bash
# cute-claude test suite.
#
# Every case runs the installer against a throwaway HOME, so nothing here can
# touch the real ~/.claude. Needs jq and nothing else.
#
#   bash tests/run.sh
set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
INSTALLER="$HERE/../dist/cute.sh"
ROOT="$HERE/.."
PASS=0
FAIL=0

ok()   { PASS=$((PASS + 1)); printf '  ok   %s\n' "$1"; }
bad()  { FAIL=$((FAIL + 1)); printf '  FAIL %s\n' "$1"; [ $# -gt 1 ] && printf '       %s\n' "$2"; }
is()   { if [ "$2" = "$3" ]; then ok "$1"; else bad "$1" "expected [$3], got [$2]"; fi; }
has()  { if [ -e "$2" ]; then ok "$1"; else bad "$1" "missing: $2"; fi; }
hasnt(){ if [ ! -e "$2" ]; then ok "$1"; else bad "$1" "should not exist: $2"; fi; }

# Each case gets a fresh HOME and runs the installer inside it.
sandbox() { SANDBOX="$(mktemp -d)"; export HOME="$SANDBOX"; mkdir -p "$HOME/.claude"; }
cleanup() { [ -n "${SANDBOX:-}" ] && rm -rf "$SANDBOX"; }
install() { HOME="$SANDBOX" bash "$INSTALLER" "$@" >/dev/null 2>&1; }
revert()  { HOME="$SANDBOX" bash "$INSTALLER" --revert >/dev/null 2>&1; }

S() { printf '%s/.claude/settings.json' "$SANDBOX"; }
q() { jq -r "$1" "$(S)" 2>/dev/null; }

# The marker /pet writes. Deliberately outside ~/.claude — see PET_FILE in the
# installer — so the tests have to look for it where it really lives.
PET="/tmp/cute-claude-petted-$(id -u 2>/dev/null || echo 0)"

# Backdate a file. GNU touch takes -d @epoch; BSD needs -t with a formatted
# stamp, so try both rather than assuming which platform this is running on.
age_file() { # $1 = path, $2 = seconds ago
  local when=$(( $(date +%s) - $2 ))
  touch -d "@$when" "$1" 2>/dev/null && return 0
  touch -t "$(date -r "$when" +%Y%m%d%H%M.%S 2>/dev/null)" "$1" 2>/dev/null
}

REAL_HOME="$HOME"
trap 'HOME="$REAL_HOME"; rm -f "$PET"' EXIT

command -v jq >/dev/null 2>&1 || { echo "these tests need jq" >&2; exit 1; }

# The suite runs against the built artifact, so build first — otherwise a green
# run could be testing a stale dist/ that no longer matches src/.
bash "$ROOT/build.sh" >/dev/null || { echo "build failed" >&2; exit 1; }

# --------------------------------------------------------------------- cases --

echo "bare install"
sandbox
install
has   "CLAUDE.md written"                "$HOME/.claude/CLAUDE.md"
hasnt "no statusline without --terminal" "$HOME/.claude/statusline.sh"
hasnt "no /pet without --commands"       "$HOME/.claude/commands/pet.md"
# The whole point of dropping the hooks: a default install is one file.
hasnt "settings.json left alone"         "$(S)"
hasnt "no heartbeat any more"            "$HOME/.claude/critter-heartbeat.sh"
hasnt "no /afk any more"                 "$HOME/.claude/commands/afk.md"
has   "manifest written"                 "$HOME/.claude/.cute-claude-manifest"
cleanup

echo
echo "full install"
sandbox
install --terminal --commands --critter bnuuy
has  "statusline"                 "$HOME/.claude/statusline.sh"
has  "theme"                      "$HOME/.claude/themes/kitten.json"
has  "/pet"                       "$HOME/.claude/commands/pet.md"
has  "settings.json written"      "$(S)"
is   "settings.json is an object" "$(q 'type')" "object"
is   "theme set"                  "$(q '.theme')" "custom:kitten"
is   "statusLine points at our script" \
     "$(q '.statusLine.command | split("/") | last')" "statusline.sh"
is   "spinner verbs are bnuuy flavoured" \
     "$(q '.spinnerVerbs.verbs | map(select(. == "Binkying")) | length')" "1"
# No hooks, in any form, ever again.
is   "installs no hooks"          "$(q '.hooks // "none"')" "none"
for f in pet treat critter; do
  is "/$f frontmatter is well formed" \
     "$(awk 'NR>1 && /^---$/{exit} NR>1 && /^disable-model-invocation: true$/{n++} END{print n+0}' \
        "$HOME/.claude/commands/$f.md")" "1"
done
cleanup

echo
echo "/pet writes outside ~/.claude"
# Regression test. A slash command's !\`...\` line is permission-checked, and
# Claude Code refuses writes anywhere under ~/.claude as sensitive files, so a
# marker there makes /pet fail outright for every user.
sandbox
install --commands --terminal
is "marker path is not under ~/.claude" \
   "$(grep -c '\.claude' "$HOME/.claude/commands/pet.md")" "0"
is "marker path is the shared /tmp one" \
   "$(grep -cF "touch \"$PET\"" "$HOME/.claude/commands/pet.md")" "1"
is "statusline looks for the same path" \
   "$(grep -cF "pet_file='$PET'" "$HOME/.claude/statusline.sh")" "1"
cleanup

echo
echo "upgrading from a version that had /afk"
# Those installs left Stop and UserPromptSubmit hooks behind. This version does
# not write them, so it has to actively clear them or they invoke a heartbeat
# script that is no longer there, on every single turn.
sandbox
cat > "$(S)" <<'OLD'
{
  "mine": [1, 2],
  "hooks": {
    "Stop": [
      { "hooks": [ { "type": "command", "command": "echo mine" } ] },
      { "hooks": [ { "type": "command", "command": "bash /home/u/.claude/critter-heartbeat.sh" } ] }
    ],
    "UserPromptSubmit": [
      { "hooks": [ { "type": "command", "command": "touch /home/u/.claude/.critter-awake" } ] }
    ]
  }
}
OLD
install
is    "stale critter hook removed"  "$(q '.hooks.Stop | length')" "1"
is    "user hook survived"          "$(q '.hooks.Stop[0].hooks[0].command')" "echo mine"
is    "empty hook group dropped"    "$(q '.hooks.UserPromptSubmit // "none"')" "none"
is    "unrelated key kept"          "$(jq -c '.mine' "$(S)" 2>/dev/null)" "[1,2]"
cleanup

echo
echo "reinstall is idempotent"
sandbox
install --terminal --commands
first="$(cat "$(S)")"
install --terminal --commands
is "second run leaves settings identical" \
   "$([ "$(cat "$(S)")" = "$first" ] && echo same || echo changed)" "same"
cleanup

echo
echo "revert restores what was there"
sandbox
printf '{\n  "theme": "dark",\n  "mine": [1, 2],\n  "hooks": {\n    "Stop": [ { "hooks": [ { "type": "command", "command": "echo mine" } ] } ]\n  }\n}\n' \
  > "$(S)"
printf '# my own notes\n' > "$HOME/.claude/CLAUDE.md"
before_md="$(cat "$HOME/.claude/CLAUDE.md")"
before_settings="$(cat "$(S)")"
install --terminal --commands
is "install changed settings.json" \
   "$([ "$(cat "$(S)")" = "$before_settings" ] && echo same || echo changed)" "changed"
revert
is    "CLAUDE.md restored"    "$(cat "$HOME/.claude/CLAUDE.md")" "$before_md"
is    "user theme restored"   "$(q '.theme')" "dark"
is    "unrelated key kept"    "$(jq -c '.mine' "$(S)" 2>/dev/null)" "[1,2]"
is    "user hook survived"    "$(q '.hooks.Stop[0].hooks[0].command')" "echo mine"
is    "our statusLine gone"   "$(q '.statusLine // "none"')" "none"
is    "our spinnerVerbs gone" "$(q '.spinnerVerbs // "none"')" "none"
hasnt "statusline removed"    "$HOME/.claude/statusline.sh"
hasnt "/pet removed"          "$HOME/.claude/commands/pet.md"
hasnt "manifest removed"      "$HOME/.claude/.cute-claude-manifest"
cleanup

echo
echo "revert of a settings.json we created deletes it"
sandbox
install --terminal
has   "settings.json created"  "$(S)"
revert
hasnt "settings.json removed"  "$(S)"
cleanup

echo
echo "statusline renders"
sandbox
install --terminal
SL="$HOME/.claude/statusline.sh"
TR="$SANDBOX/transcript.jsonl"; : > "$TR"
payload="{\"workspace\":{\"current_dir\":\"/tmp/proj\"},\"context_window\":{\"used_percentage\":12},\"transcript_path\":\"$TR\"}"
render() { printf '%s' "$payload" | STATUSLINE_FRAME=0 HOME="$SANDBOX" bash "$SL" \
             | sed 's/\x1b\[[0-9;]*m//g'; }
# wc -m, not awk length: the faces differ in byte count but not in display
# width, and it is display width that decides whether the line jitters.
width()  { render | wc -m | tr -d ' '; }

rm -f "$PET"
is "shows the directory"   "$(render | grep -c 'proj')" "1"
is "awake face by default" "$(render | grep -c 'ฅ\^•ﻌ•\^ฅ')" "1"
base_width="$(width)"

# Idleness is read from the transcript's mtime, so no hook has to report it.
age_file "$TR" 1200
is "naps when the transcript goes quiet" "$(render | grep -c 'ฅ\^-ﻌ-\^ฅ')" "1"
is "napping keeps the line width"        "$(width)" "$base_width"

: > "$TR"
is "wakes when the transcript moves" "$(render | grep -c 'ฅ\^•ﻌ•\^ฅ')" "1"

# A missing transcript must not read as "idle forever" — no signal means awake.
payload='{"workspace":{"current_dir":"/tmp/proj"},"context_window":{"used_percentage":12}}'
is "no transcript still renders awake" "$(render | grep -c 'ฅ\^•ﻌ•\^ฅ')" "1"

payload="{\"workspace\":{\"current_dir\":\"/tmp/proj\"},\"context_window\":{\"used_percentage\":12},\"transcript_path\":\"$TR\"}"
touch "$PET"
is "petted outranks napping"  "$(age_file "$TR" 1200; render | grep -c 'ฅ\^ᵕﻌᵕ\^ฅ')" "1"
is "petted keeps the width"   "$(width)" "$base_width"
rm -f "$PET"
cleanup

echo
echo "--upgrade replays recorded options"
sandbox
install --critter raven --vibe dry --terminal
install --upgrade
is  "critter remembered"  "$(grep -c 'raven' "$HOME/.claude/CLAUDE.md")" "1"
is  "vibe remembered"     "$(grep -c 'dry wit is the register' "$HOME/.claude/CLAUDE.md")" "1"
has "--terminal remembered" "$HOME/.claude/statusline.sh"
# An explicit flag still wins over the recorded value.
install --upgrade --critter fox
is  "explicit flag overrides the record" "$(grep -c 'fox' "$HOME/.claude/CLAUDE.md")" "1"
is  "unset knobs still come from the record" \
    "$(grep -c 'dry wit is the register' "$HOME/.claude/CLAUDE.md")" "1"
cleanup

sandbox
if install --upgrade; then bad "--upgrade needs a manifest"; else ok "--upgrade needs a manifest"; fi
install
if install --upgrade --profile work; then bad "--upgrade rejects --profile"
else ok "--upgrade rejects --profile"; fi
cleanup

echo
echo "a CLAUDE.md we did not write"
sandbox
printf '# my own rules\n' > "$HOME/.claude/CLAUDE.md"
out="$(HOME="$SANDBOX" bash "$INSTALLER" 2>&1)"
is "warns it was not ours" \
   "$(printf '%s' "$out" | grep -c 'was not written by cute-claude')" "1"
is "points at --append" "$(printf '%s' "$out" | grep -c ' --append')" "1"
is "replaced by default"  "$(grep -c 'how to talk to me' "$HOME/.claude/CLAUDE.md")" "1"
revert
is "revert brings it back" "$(cat "$HOME/.claude/CLAUDE.md")" "# my own rules"
cleanup

sandbox
printf '# my own rules\n' > "$HOME/.claude/CLAUDE.md"
install --append
is "--append keeps the original"   "$(grep -c 'my own rules' "$HOME/.claude/CLAUDE.md")" "1"
is "--append adds the tone guide"  "$(grep -c 'how to talk to me' "$HOME/.claude/CLAUDE.md")" "1"
is "the original stays on top" \
   "$(awk '/my own rules/{a=NR} /how to talk to me/{b=NR} END{print (a<b) ? "yes" : "no"}' \
      "$HOME/.claude/CLAUDE.md")" "yes"
# Once we have written it, it is ours — a second run must not stack another copy.
install --append
is "second --append does not duplicate" \
   "$(grep -c 'how to talk to me' "$HOME/.claude/CLAUDE.md")" "1"
is "and does not re-prepend"       "$(grep -c 'my own rules' "$HOME/.claude/CLAUDE.md")" "0"
cleanup

echo
echo "--doctor"
doctor() { HOME="$SANDBOX" bash "$INSTALLER" --doctor 2>&1; }
sandbox
install --terminal --commands
out="$(doctor)"; rc=$?
is "healthy install passes"   "$rc" "0"
is "says so"                  "$(printf '%s' "$out" | grep -c 'all wired up')" "1"

# The failure this exists for: files present, wiring silently gone.
jq 'del(.statusLine)' "$(S)" > "$SANDBOX/t" && mv "$SANDBOX/t" "$(S)"
out="$(doctor)"; rc=$?
is "unwired statusLine is caught" "$rc" "1"
is "and named"                    "$(printf '%s' "$out" | grep -c 'statusLine is not set')" "1"

install --upgrade
out="$(doctor)"; rc=$?
is "--upgrade repairs it" "$rc" "0"

rm -f "$HOME/.claude/themes/kitten.json"
is "a missing recorded file is caught" "$(doctor >/dev/null 2>&1; echo $?)" "1"
cleanup

# Orphaned hooks from a pre-drop install must be reported, not ignored.
sandbox
install --terminal
jq '.hooks.Stop = [{hooks:[{type:"command",command:"bash ~/.claude/critter-heartbeat.sh"}]}]' \
   "$(S)" > "$SANDBOX/t" && mv "$SANDBOX/t" "$(S)"
out="$(doctor)"
is "leftover hooks reported" "$(printf '%s' "$out" | grep -c 'leftover hook')" "1"
cleanup

# A pre-manifest install is the one most likely to have drifted, so the wiring
# checks still have to run rather than bailing out.
sandbox
install --terminal
rm -f "$HOME/.claude/.cute-claude-manifest"
out="$(doctor)"; rc=$?
is "no manifest still checks wiring" "$rc" "0"
is "and says the manifest is absent" "$(printf '%s' "$out" | grep -c 'no manifest')" "1"
is "and still verified statusLine"   "$(printf '%s' "$out" | grep -c 'statusLine runs')" "1"
cleanup

sandbox
is "nothing installed at all" "$(doctor >/dev/null 2>&1; echo $?)" "1"
cleanup

echo
echo "dependencies"
sandbox
SHIM="$SANDBOX/shim"; mkdir -p "$SHIM"
for b in bash cat cp mv rm rmdir mkdir chmod date stat grep sed awk tr cut cksum uname id touch printf env; do
  src="$(command -v "$b" 2>/dev/null)" && ln -sf "$src" "$SHIM/$b"
done
# A default install never opens settings.json, so it must not ask for jq.
HOME="$SANDBOX" PATH="$SHIM" bash "$INSTALLER" >/dev/null 2>&1; rc=$?
is  "bare install succeeds without jq" "$rc" "0"
has "CLAUDE.md written without jq"     "$HOME/.claude/CLAUDE.md"
cleanup

sandbox
SHIM="$SANDBOX/shim"; mkdir -p "$SHIM"
for b in bash cat cp mv rm rmdir mkdir chmod date stat grep sed awk tr cut cksum uname id touch printf env; do
  src="$(command -v "$b" 2>/dev/null)" && ln -sf "$src" "$SHIM/$b"
done
# --terminal does open it, so there it is a hard requirement, refused up front.
out="$(HOME="$SANDBOX" PATH="$SHIM" bash "$INSTALLER" --terminal 2>&1)"; rc=$?
is    "--terminal refuses without jq" "$rc" "1"
is    "mentions jq"                   "$([ "$(printf '%s' "$out" | grep -ci jq)" -gt 0 ] && echo yes)" "yes"
hasnt "wrote nothing at all"          "$HOME/.claude/CLAUDE.md"
hasnt "no settings.json either"       "$(S)"
ln -sf "$(command -v jq)" "$SHIM/jq"
HOME="$SANDBOX" PATH="$SHIM" bash "$INSTALLER" --terminal >/dev/null 2>&1
is    "installs fine without python3" "$(q '.statusLine.type')" "command"
HOME="$SANDBOX" PATH="$SHIM" bash "$INSTALLER" --revert >/dev/null 2>&1
hasnt "reverts fine without python3"  "$HOME/.claude/.cute-claude-manifest"
cleanup

echo
echo "rejects nonsense"
sandbox
if install --vibe sideways;    then bad "unknown vibe rejected";    else ok "unknown vibe rejected"; fi
if install --profile sideways; then bad "unknown profile rejected"; else ok "unknown profile rejected"; fi
if install --nonsense;         then bad "unknown flag rejected";    else ok "unknown flag rejected"; fi
cleanup

echo
echo "critter with a name that would break json"
sandbox
install --terminal --critter 'we"ird'
is "settings.json still parses" "$(q 'type')" "object"
is "critter name reached CLAUDE.md" \
   "$(grep -c 'we"ird' "$HOME/.claude/CLAUDE.md")" "1"
cleanup

echo
echo "build"
is "dist matches src"  "$(bash "$ROOT/build.sh" --check >/dev/null 2>&1 && echo fresh || echo stale)" "fresh"

# Determinism is what makes --check meaningful: if a rebuild could differ, a
# stale dist/ would be indistinguishable from a noisy one.
a="$(cat "$ROOT/dist/cute.sh")"; bash "$ROOT/build.sh" >/dev/null
is "rebuild is byte-identical" "$([ "$a" = "$(cat "$ROOT/dist/cute.sh")" ] && echo same || echo differs)" "same"

is "hand-edited dist is caught" \
   "$(t=$(mktemp); cp "$ROOT/dist/cute.sh" "$t"; echo '# tampered' >> "$ROOT/dist/cute.sh"
      bash "$ROOT/build.sh" --check >/dev/null 2>&1 && echo missed || echo caught
      cp "$t" "$ROOT/dist/cute.sh"; rm -f "$t")" "caught"

is "reports a build id" \
   "$(bash "$INSTALLER" --version | grep -c '^cute-claude build [0-9][0-9]*$')" "1"
is "no build placeholder survives" "$(grep -c '__BUILD_STAMP__' "$ROOT/dist/cute.sh")" "0"
is "no build markers survive" \
   "$(grep -cE '@inline|@build:strip' "$ROOT/dist/cute.sh")" "0"

echo
echo "assets stand alone"
is "statusline is valid bash" "$(bash -n "$ROOT/src/assets/statusline.sh" 2>&1 | wc -l | tr -d ' ')" "0"
sandbox
is "statusline asset renders" \
   "$(printf '%s' '{"workspace":{"current_dir":"/tmp/proj"}}' \
      | HOME="$SANDBOX" bash "$ROOT/src/assets/statusline.sh" | sed 's/\x1b\[[0-9;]*m//g' | grep -c proj)" "1"
cleanup

echo
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
