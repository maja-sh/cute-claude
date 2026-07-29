# cute-claude

Sets up a warm, critter-flavored Claude Code persona: a tone guide in
`CLAUDE.md`, and optionally a theme, an animated statusline, critter-flavored
spinner verbs, and a handful of slash commands.

Everything it writes lives under `~/.claude`, is backed up first, and is
recorded in a manifest, so `--revert` puts your environment back exactly as it
was — including un-merging only its own keys from a `settings.json` you already
had.

## Install

```sh
curl -fsSL <url>/dist/cute.sh | bash
```

Pipe it flags the same way:

```sh
curl -fsSL <url>/dist/cute.sh | bash -s -- --critter bnuuy --terminal
```

Or clone and run `dist/cute.sh` directly. Restart Claude Code afterwards.

Requires `bash`, coreutils and **`jq`**. jq is checked before anything is
written, so a missing dependency costs you nothing but the message telling you
to install it. It is required rather than optional because installing means
merging into a `settings.json` this script did not write, and that is not a job
for regexes — see the note above `preflight_deps` in `src/installer.sh`.

## What it writes

| Path | What | Needs |
|---|---|---|
| `~/.claude/CLAUDE.md` | tone guide — the persona itself | always |
| `~/.claude/critter-heartbeat.sh` | the `/afk` hook | always |
| `~/.claude/commands/afk.md` | `/afk` | always |
| `~/.claude/settings.json` | hooks, and with `--terminal` the statusline, spinner verbs and theme | always (merged, never replaced) |
| `~/.claude/statusline.sh` | the animated statusline | `--terminal` |
| `~/.claude/themes/kitten.json` | the color theme | `--terminal` |
| `~/.claude/commands/{pet,treat,critter}.md` | `/pet`, `/treat`, `/critter` | `--commands` |

`CLAUDE.md` and the slash commands work everywhere. The theme, statusline and
spinner verbs are **terminal-only** — they do nothing in the VS Code panel.

## Options

| Flag | Meaning |
|---|---|
| `--critter <name>` | `cat` (default), `bnuuy`, `fox`, `raven`, or any name at all |
| `--vibe <cute\|dry>` | how warm the tone is. `dry` keeps the humor, drops the hearts |
| `--vibe-extra "<words>"` | folds your own descriptor into the vibe line |
| `--profile <work\|personal>` | shorthand. `work` = `--vibe dry`; `personal` = cute + `--terminal --commands` |
| `--terminal` | theme, statusline, spinner verbs |
| `--commands` | `/pet`, `/treat`, `/critter` |
| `--afk-interval <secs>` | seconds between idle lines. Default 2700 (45 min) |
| `--list` | show the built-in critters |
| `--revert` | undo everything |
| `--version` | which build this is |

An unknown critter is fully supported, not a fallback: it gets a face chosen
deterministically from its name, and `CLAUDE.md` asks Claude to invent that
critter's noises and habits and keep them consistent. The flavor is generated at
read time by the thing reading it.

## `/afk`

Type `/afk` when you step away. The critter then says one short idle line every
45 minutes until you type something again.

This is not only decorative. Claude's prompt cache expires an hour after last
use, and **reading a cache entry refreshes its lifetime** — so a turn every 45
minutes keeps an idle session warm indefinitely instead of letting it go cold
while you are at lunch.

The mechanism matters: the cache is keyed on the conversation prefix, not on a
session id. Only a real turn *in that session* refreshes it. A background job
talking to the API builds a different prefix and does nothing for the session
you left open. So `/afk` arms a `Stop` hook that waits out the interval and then
blocks the stop, which starts one more turn in the same conversation.

Cost: each beat is one cached read of the conversation so far, plus a few output
tokens. On a large session that is not nothing. Nothing is armed until you ask,
and the next prompt you type disarms it.

With `--terminal`, the statusline shows a distinct waiting face while armed.

## Reverting

```sh
dist/cute.sh --revert
```

Files it created are deleted; files it replaced are restored from their backups;
`settings.json` has only cute-claude's own keys and hooks removed, so anything
you changed since installing survives. If you edited a file it wrote, a reinstall
keeps your version alongside as `<name>.local.<timestamp>` rather than
discarding it.

## Development

```
build.sh                    src/ -> dist/cute.sh
src/installer.sh            args, preflight, manifest, claim/revert, install flow
src/critters.sh             the critter table — faces, spinner verbs, palettes
src/assets/statusline.sh    the statusline program
src/assets/heartbeat.sh     the /afk heartbeat hook
dist/cute.sh                the built artifact — this is what you install
tests/run.sh                the suite
```

**Edit `src/`, never `dist/cute.sh`.** The artifact is generated and committed;
hand-editing it is silently undone by the next build. `./build.sh --check`
fails if `dist/` does not match `src/`, and the suite runs that check.

```sh
./build.sh           # write dist/cute.sh
./build.sh --check   # is dist/ current?
bash tests/run.sh    # builds first, then tests the artifact
```

The build is a single rule: a line reading `# @inline <path>` is replaced by
that file's contents. Assets land inside quoted heredocs, so nothing expands and
nothing needs escaping. Each asset also carries a `# @build:strip-begin` /
`# @build:strip-end` block holding development defaults, dropped at build time —
which is what lets you run them directly while iterating:

```sh
printf '{"workspace":{"current_dir":"/tmp"}}' | bash src/assets/statusline.sh
printf '{}' | bash src/assets/heartbeat.sh
```

The build is deterministic — same sources in, byte-identical file out. Do not
put a timestamp in it; `--check` depends on that.

The suite runs every case against a throwaway `$HOME`, so it cannot touch your
real `~/.claude`. It needs `jq` and nothing else.

### Adding a critter

Add a case to `src/critters.sh` with a face pair (`FACE`/`BLINK` must be the
same display width or the statusline jitters), spinner verbs, and a palette,
then `./build.sh`. The five status faces are derived from `FACE` by substituting
the eyes, so a face built from `•` gets weary, asleep, pleased and watching
variants for free.
