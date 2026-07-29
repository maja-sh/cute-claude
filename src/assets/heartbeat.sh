#!/usr/bin/env bash
# @build:strip-begin
# The cute-claude afk heartbeat. It is a Stop hook, so it reads the hook payload
# on stdin and prints a decision on stdout:
#
#   printf '{}' | bash src/assets/heartbeat.sh
#
# Everything between the strip markers is dropped at build time; the installer
# writes the chosen interval and critter in its place.
interval=2700
critter=cat
# @build:strip-end

# A Stop hook. When /afk has armed it, this waits out the interval and then
# blocks the stop, which starts one more turn in this same session. That turn is
# the whole point: the prompt cache is keyed on the conversation prefix, so the
# only thing that keeps THIS session warm is a real turn in THIS session. A
# background job talking to the API elsewhere builds a different prefix and does
# nothing for you.
#
# Disarmed by any prompt you type. UserPromptSubmit stamps .critter-prompt, and
# a stamp at least as new as .critter-afk means you are back at the keyboard.
set -euo pipefail

# Drain the hook payload. We do not need it, but leaving it unread can hand the
# caller a broken pipe.
cat >/dev/null 2>&1 || true

afk="$HOME/.claude/.critter-afk"
prompt="$HOME/.claude/.critter-prompt"

mtime() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || printf 0; }

armed() {
  [ -f "$afk" ] || return 1
  local a p now
  a=$(mtime "$afk"); p=$(mtime "$prompt"); now=$(date +%s)
  local grace="${CRITTER_AFK_GRACE:-15}"
  case "$a" in ''|*[!0-9]*) a=0 ;; esac
  case "$p" in ''|*[!0-9]*) p=0 ;; esac
  # Typing /afk also fires the hook that stamps .critter-prompt, and the two run
  # in an order this script cannot depend on — so for the first few seconds a
  # fresh marker counts as armed no matter which stamp won. After that the
  # comparison is honest, and any prompt you type outranks the marker.
  [ $(( now - a )) -lt "$grace" ] && return 0
  [ "$a" -ge "$p" ]
}

# Clearing the marker on the way out keeps the statusline honest and means a
# forgotten /afk cannot quietly re-arm itself days later.
if ! armed; then rm -f "$afk"; exit 0; fi
sleep "$interval"
if ! armed; then rm -f "$afk"; exit 0; fi

# No quotes or backslashes in here, so it needs no JSON escaping.
reason="Nobody is at the keyboard right now. Reply with one short line of idle ${critter} noise, or some small thing you are doing while you wait, in character. Under ten words. No work, no questions, no offering to help, no summary of what we were doing. Vary it - do not reuse your last idle line."
printf '{"decision":"block","reason":"%s"}\n' "$reason"
