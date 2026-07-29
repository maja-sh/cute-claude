#!/usr/bin/env bash
# cute-claude test suite.
#
# Every case runs the installer against a throwaway HOME, so nothing here can
# touch the real ~/.claude. Needs jq and nothing else, same as the installer.
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

REAL_HOME="$HOME"
trap 'HOME="$REAL_HOME"' EXIT

command -v jq >/dev/null 2>&1 || { echo "these tests need jq" >&2; exit 1; }

# The suite runs against the built artifact, so build first — otherwise a green
# run could be testing a stale dist/ that no longer matches src/.
bash "$ROOT/build.sh" >/dev/null || { echo "build failed" >&2; exit 1; }

# --------------------------------------------------------------------- cases --

echo "bare install"
sandbox
install
has   "CLAUDE.md written"                "$HOME/.claude/CLAUDE.md"
has   "heartbeat written"                "$HOME/.claude/critter-heartbeat.sh"
has   "/afk written"                     "$HOME/.claude/commands/afk.md"
has   "settings.json written"            "$(S)"
hasnt "no statusline without --terminal" "$HOME/.claude/statusline.sh"
hasnt "no /pet without --commands"       "$HOME/.claude/commands/pet.md"
is    "heartbeat is a Stop hook" \
      "$(q '.hooks.Stop[-1].hooks[0].command | split("/") | last')" "critter-heartbeat.sh"
is    "heartbeat timeout outlasts the interval" \
      "$(q '.hooks.Stop[-1].hooks[0].timeout')" "2760"
is    "no statusLine key without --terminal" "$(q '.statusLine // "none"')" "none"
cleanup

echo
echo "full install"
sandbox
install --terminal --commands --critter bnuuy
has  "statusline"          "$HOME/.claude/statusline.sh"
has  "theme"               "$HOME/.claude/themes/kitten.json"
has  "/pet"                "$HOME/.claude/commands/pet.md"
has  "/afk still there"    "$HOME/.claude/commands/afk.md"
is   "statusline knows the watching face" \
     "$(grep -c '^watching=' "$HOME/.claude/statusline.sh")" "1"
is   "settings.json is an object"  "$(q 'type')" "object"
is   "theme set"                   "$(q '.theme')" "custom:kitten"
is   "UserPromptSubmit stamps the prompt marker" \
     "$(q '.hooks.UserPromptSubmit[0].hooks[0].command | test("critter-prompt")')" "true"
is   "Stop has both awake and heartbeat" "$(q '.hooks.Stop | length')" "2"
is   "spinner verbs are bnuuy flavoured" \
     "$(q '.spinnerVerbs.verbs | map(select(. == "Binkying")) | length')" "1"
for f in pet treat critter afk; do
  is "/$f frontmatter is well formed" \
     "$(awk 'NR>1 && /^---$/{exit} NR>1 && /^disable-model-invocation: true$/{n++} END{print n+0}' \
        "$HOME/.claude/commands/$f.md")" "1"
done
cleanup

echo
echo "reinstall is idempotent"
sandbox
install --terminal --commands
first="$(cat "$(S)")"
install --terminal --commands
is "second run leaves settings identical" \
   "$([ "$(cat "$(S)")" = "$first" ] && echo same || echo changed)" "same"
is "hooks did not accumulate" "$(q '.hooks.Stop | length')" "2"
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
is    "our hooks all gone"    "$(q '.hooks.Stop | length')" "1"
is    "our statusLine gone"   "$(q '.statusLine // "none"')" "none"
is    "our spinnerVerbs gone" "$(q '.spinnerVerbs // "none"')" "none"
hasnt "heartbeat removed"     "$HOME/.claude/critter-heartbeat.sh"
hasnt "/afk removed"          "$HOME/.claude/commands/afk.md"
hasnt "statusline removed"    "$HOME/.claude/statusline.sh"
hasnt "manifest removed"      "$HOME/.claude/.cute-claude-manifest"
cleanup

echo
echo "revert of a settings.json we created deletes it"
sandbox
install
revert
hasnt "settings.json removed" "$(S)"
cleanup

echo
echo "heartbeat behaviour"
sandbox
install --afk-interval 60
HB="$HOME/.claude/critter-heartbeat.sh"
beat() { printf '{}' | HOME="$SANDBOX" CRITTER_AFK_GRACE="${GRACE:-15}" bash "$1"; }

is "silent when never armed" "$(beat "$HB")" ""

touch "$HOME/.claude/.critter-prompt"; sleep 1
touch "$HOME/.claude/.critter-afk"; sleep 1
touch "$HOME/.claude/.critter-prompt"          # you came back
is    "silent once you are back"  "$(GRACE=0 beat "$HB")" ""
hasnt "marker cleared on return"  "$HOME/.claude/.critter-afk"

# Armed, with the sleep stubbed out so the suite does not take a minute.
touch "$HOME/.claude/.critter-prompt"; sleep 1; touch "$HOME/.claude/.critter-afk"
sed 's/^sleep "\$interval"$/:/' "$HB" > "$SANDBOX/hb-nosleep.sh"
out="$(beat "$SANDBOX/hb-nosleep.sh")"
is "blocks the stop when armed" \
   "$(printf '%s' "$out" | jq -r '.decision' 2>/dev/null)" "block"
is "reason names the critter" \
   "$(printf '%s' "$out" | jq -r '.reason | test("cat")' 2>/dev/null)" "true"
is "reason has no embedded newlines" "$(printf '%s' "$out" | wc -l | tr -d ' ')" "0"
cleanup

echo
echo "statusline renders"
sandbox
install --terminal
SL="$HOME/.claude/statusline.sh"
payload='{"workspace":{"current_dir":"/tmp/proj"},"context_window":{"used_percentage":12}}'
render() { printf '%s' "$payload" | STATUSLINE_FRAME=0 HOME="$SANDBOX" \
             CRITTER_AFK_GRACE="${GRACE:-15}" bash "$SL" | sed 's/\x1b\[[0-9;]*m//g'; }
# wc -m, not awk length: the faces differ in byte count but not in display
# width, and it is display width that decides whether the line jitters.
width()  { render | wc -m | tr -d ' '; }

is "shows the directory"   "$(render | grep -c 'proj')" "1"
is "awake face by default" "$(render | grep -c 'ฅ\^•ﻌ•\^ฅ')" "1"
base_width="$(width)"

touch "$HOME/.claude/.critter-prompt"; sleep 1; touch "$HOME/.claude/.critter-afk"
is "afk face while armed"  "$(render | grep -c 'ฅ\^°ﻌ°\^ฅ')" "1"
is "afk keeps the line width" "$(width)" "$base_width"

# Past the grace window a prompt outranks the marker. The sleep is load-bearing:
# a same-second tie deliberately still counts as armed, because at arming time
# /afk and the prompt hook stamp within the same second.
sleep 1; touch "$HOME/.claude/.critter-prompt"
is "back to awake once you type" "$(GRACE=0 render | grep -c 'ฅ\^•ﻌ•\^ฅ')" "1"

touch "$HOME/.claude/.critter-petted"
is "petted outranks afk"      "$(render | grep -c 'ฅ\^ᵕﻌᵕ\^ฅ')" "1"
is "petted keeps the width"   "$(width)" "$base_width"
rm -f "$HOME/.claude/.critter-petted"
cleanup

echo
echo "dependencies"
sandbox
SHIM="$SANDBOX/shim"; mkdir -p "$SHIM"
for b in bash cat cp mv rm rmdir mkdir chmod date stat grep sed awk tr cut cksum uname sleep touch printf env; do
  src="$(command -v "$b" 2>/dev/null)" && ln -sf "$src" "$SHIM/$b"
done
# No jq on PATH at all: must refuse before writing anything.
out="$(HOME="$SANDBOX" PATH="$SHIM" bash "$INSTALLER" 2>&1)"; rc=$?
is    "refuses without jq"          "$rc" "1"
is    "says what to install"        "$(printf '%s' "$out" | grep -ci 'jq')" "$(printf '%s' "$out" | grep -ci 'jq')"
is    "mentions jq"                 "$([ "$(printf '%s' "$out" | grep -ci jq)" -gt 0 ] && echo yes)" "yes"
hasnt "wrote nothing at all"        "$HOME/.claude/CLAUDE.md"
hasnt "no settings.json either"     "$(S)"
# python3 is not needed by the installer.
ln -sf "$(command -v jq)" "$SHIM/jq"
HOME="$SANDBOX" PATH="$SHIM" bash "$INSTALLER" --terminal >/dev/null 2>&1
is    "installs fine without python3" "$(q '.hooks.Stop | length')" "2"
HOME="$SANDBOX" PATH="$SHIM" bash "$INSTALLER" --revert >/dev/null 2>&1
hasnt "reverts fine without python3"  "$HOME/.claude/.cute-claude-manifest"
cleanup

echo
echo "rejects nonsense"
sandbox
if install --afk-interval banana; then bad "non-numeric interval rejected"; else ok "non-numeric interval rejected"; fi
if install --afk-interval 99999; then bad "interval past the cache lifetime rejected"; else ok "interval past the cache lifetime rejected"; fi
if install --vibe sideways;      then bad "unknown vibe rejected";      else ok "unknown vibe rejected"; fi
if install --profile sideways;   then bad "unknown profile rejected";   else ok "unknown profile rejected"; fi
cleanup

echo
echo "critter with a name that would break json"
sandbox
install --critter 'we"ird'
is "quote stripped from the heartbeat prompt" \
   "$(grep -c 'critter=weird' "$HOME/.claude/critter-heartbeat.sh")" "1"
is "settings.json still parses" "$(q 'type')" "object"
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
for a in statusline heartbeat; do
  is "$a is valid bash"  "$(bash -n "$ROOT/src/assets/$a.sh" 2>&1 | wc -l | tr -d ' ')" "0"
done
sandbox
is "statusline asset renders" \
   "$(printf '%s' '{"workspace":{"current_dir":"/tmp/proj"}}' \
      | HOME="$SANDBOX" bash "$ROOT/src/assets/statusline.sh" | sed 's/\x1b\[[0-9;]*m//g' | grep -c proj)" "1"
is "heartbeat asset is silent unarmed" \
   "$(printf '{}' | HOME="$SANDBOX" bash "$ROOT/src/assets/heartbeat.sh")" ""
cleanup

echo
printf '\n%s passed, %s failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
