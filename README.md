# cute-claude

[![ci](https://github.com/maja-sh/cute-claude/actions/workflows/ci.yml/badge.svg)](https://github.com/maja-sh/cute-claude/actions/workflows/ci.yml)

![demo](docs/demo.gif)

A warm, critter-flavored Claude Code persona — a tone guide in `CLAUDE.md`,
plus optionally a theme, an animated statusline, critter-flavored spinner
verbs, and a handful of slash commands.

No hooks. Without `--terminal` it writes `CLAUDE.md` and nothing else, so
`settings.json` never gets touched.

Everything it writes lives under `~/.claude`, gets backed up first, and is
tracked in a manifest, so `--revert` puts your environment back exactly how it
was — including un-merging just its own keys from a `settings.json` you already
had.

## Install

```sh
curl -fsSL https://github.com/maja-sh/cute-claude/releases/latest/download/cute.sh | bash
```

Pass it flags the same way — everything after `--` goes to the installer:

```sh
curl -fsSL https://github.com/maja-sh/cute-claude/releases/latest/download/cute.sh | bash -s -- \
  --profile personal \
  --critter bnuuy \
  --vibe dry \
  --terminal \
  --commands
```

`--profile personal` is the base layer; `--vibe dry` overrides the `cute` it
would otherwise set. The profile already implies `--terminal --commands`, so
those are only listed to show what it expands to.

Restart Claude Code afterwards.

Needs `bash` and coreutils. **`jq` only comes in when `settings.json` is
actually opened** — so with `--terminal`, or when upgrading an install old
enough to still have hooks. A plain install needs neither.

When it is needed it's required, not optional — merging into a `settings.json`
this script didn't write isn't a job for regexes. It's checked before anything
gets written, so a missing dependency just costs you the message telling you to
install it (see the note above `preflight_deps` in `src/installer.sh`).

## Verifying it before you run it

Piping a script from the internet into your shell is a fair thing to refuse,
so this is checkable rather than asking for trust.

Every release is built from a tag by
[the release workflow](.github/workflows/release.yml), never uploaded by hand,
and ships alongside a `.sha256`.

The build is **deterministic**: identical sources always produce a
byte-identical artifact, and `--version` prints a content hash of `src/`. So
you can reproduce the published file from source rather than take it on faith:

```sh
curl -fsSL https://github.com/maja-sh/cute-claude/releases/latest/download/cute.sh | bash -s -- --version      # cute-claude build N

git clone https://github.com/maja-sh/cute-claude && cd cute-claude
git checkout <the release tag>
./build.sh && ./dist/cute.sh --version       # same N
```

Matching build ids mean the file you're about to pipe is exactly what this
source compiles to — verified against the repository, not whatever host served
it. CI asserts that determinism on every push.

Or skip the pipe entirely: clone it, run `./build.sh`, and execute
`dist/cute.sh` yourself.

## What it writes

| Path | What | Needs |
|---|---|---|
| `~/.claude/CLAUDE.md` | tone guide — the persona itself | always |
| `~/.claude/settings.json` | statusline, spinner verbs, theme | `--terminal` (merged, never replaced) |
| `~/.claude/statusline.sh` | the animated statusline | `--terminal` |
| `~/.claude/themes/kitten.json` | the color theme | `--terminal` |
| `~/.claude/commands/{pet,treat,critter,affirm}.md` | `/pet`, `/treat`, `/critter`, `/affirm` | `--commands` |

`CLAUDE.md` and the slash commands work everywhere — the terminal, the VS Code
panel, and Zed's ACP adapter all read `CLAUDE.md` directly. The theme,
statusline and spinner verbs are **terminal-only** — they're Claude Code's own
CLI chrome, and other frontends draw their own UI, so there's no surface for
them to appear on.

Nothing here writes anything at runtime. A slash command's `` !`...` `` line is
permission-checked, and every absolute path it could use gets refused — under
`~/.claude` as a sensitive file, anywhere else as outside the session's allowed
working directory — so `/pet` doesn't actually execute anything. The statusline
notices it by reading the transcript instead, which needs no permission and
works in every frontend.

## Mood postcards

Every conversational response ends with a small mood line:

```
mood: cozy · *stretching in the last of the afternoon light*
```

The word — free vocabulary, whatever Claude thinks fits — appears in the
response itself in every frontend. With `--terminal`, the statusline also
lifts it out and shows it next to the context readout, so the critter's
mood is visible at a glance.

Slash commands (`/pet`, `/treat`, `/affirm`, `/critter`) are exempt from the
rule; they have their own brief formats. The statusline picks the word up
the same way it detects `/pet` — a small tail-read of the transcript, no
hooks, no state file, no new mechanism.

## Options

| Flag | Meaning |
|---|---|
| `--critter <name>` | `cat` (default), `bnuuy`, `fox`, `raven`, or any name at all |
| `--vibe <cute\|dry>` | how warm the tone is. `dry` keeps the humor, drops the hearts |
| `--vibe-extra "<words>"` | folds your own descriptor into the vibe line |
| `--profile <work\|personal>` | shorthand. `work` = `--vibe dry`; `personal` = cute + `--terminal --commands` |
| `--terminal` | theme, statusline, spinner verbs |
| `--commands` | `/pet`, `/treat`, `/critter`, `/affirm` |
| `--append` | keep an existing `CLAUDE.md` and add the tone guide below it |
| `--upgrade` | reinstall with the options the last run recorded |
| `--doctor` | check the install is actually wired up, not merely present |
| `--list` | show the built-in critters |
| `--revert` | undo everything |
| `--version` | which build this is |

An unknown critter is fully supported, not a fallback — it gets a face chosen
deterministically from its name, and `CLAUDE.md` asks Claude to invent that
critter's noises and habits and keep them consistent. The flavor is generated
at read time by the thing reading it.

## Checking it works

```sh
dist/cute.sh --doctor
```

"Is it installed" is the easy question, not the useful one. Files can all be
there while nothing is actually wired — something rewrites `settings.json`,
`statusLine` and the theme go with it, and the statusline script sits there
doing nothing with no error to tell you. `--doctor` checks the wiring rather
than the inventory, reports anything half-applied, and exits non-zero if it
found a problem.

It also works on installs predating the manifest — those are the ones most
likely to have drifted, so it runs the wiring checks anyway and skips only the
per-file checksums it has nothing to compare against.

## Upgrading

```sh
dist/cute.sh --upgrade
```

Each install records its own options in the manifest, so `--upgrade` replays
them rather than making you remember whether it was `--critter raven --vibe dry
--terminal`. Any flag you pass explicitly still wins. `--profile` is refused
alongside it, though — both want to be the base layer under your explicit
flags, and guessing which one wins is worse than saying so.

## An existing `CLAUDE.md`

If `~/.claude/CLAUDE.md` is already there and cute-claude didn't write it,
that's someone's own global instructions — the one file here that people
hand-write. It gets backed up and replaced, with a warning saying so and
pointing at:

```sh
dist/cute.sh --append
```

which keeps your file and puts the tone guide underneath it instead. Either way
`--revert` restores exactly what you had. It warns rather than refuses, because
refusing by default would break the one-line install for exactly the people
most likely to have opinions about their `CLAUDE.md`.

## Reverting

```sh
dist/cute.sh --revert
```

Files it created get deleted; files it replaced get restored from their
backups; `settings.json` only has cute-claude's own keys removed, so anything
you changed since installing survives. If you edited a file it wrote, a
reinstall keeps your version alongside as `<name>.local.<timestamp>` rather
than discarding it.

## Licence

[0BSD](LICENSE) — do whatever you like with it, no attribution required. If
you want to use it as a base for your own Claude personalisation, that's what
it's for.

## Development

```
build.sh                    src/ -> dist/cute.sh
src/installer.sh            args, preflight, manifest, claim/revert, install flow
src/critters.sh             the critter table — faces, spinner verbs, palettes
src/assets/statusline.sh    the statusline program
dist/cute.sh                the built artifact — gitignored, attached to releases
tests/run.sh                the suite
tests/try.sh                sandbox install into a throwaway HOME, then launch claude
```

**Edit `src/`, never `dist/cute.sh`.** The artifact is generated and published
by the release workflow — anything you type into it gets silently undone by the
next build. `./build.sh --check` tells you whether your local `dist/` is stale.

```sh
./build.sh           # write dist/cute.sh
./build.sh --check   # is dist/ current?
bash tests/run.sh    # builds first, then tests the artifact
bash tests/try.sh --commands   # sandbox install, opens claude in a temp HOME
```

The build is a single rule: a line reading `# @inline <path>` gets replaced by
that file's contents. Assets land inside quoted heredocs, so nothing expands
and nothing needs escaping. Each asset also carries a `# @build:strip-begin` /
`# @build:strip-end` block holding development defaults, dropped at build
time — which is what lets you run them directly while iterating:

```sh
printf '{"workspace":{"current_dir":"/tmp"}}' | bash src/assets/statusline.sh
```

The build is deterministic — that's what `./build.sh --check` relies on, so
don't put a timestamp in it.

The suite runs every case against a throwaway `$HOME`, so it can't touch your
real `~/.claude`. It needs `jq` and nothing else.

### Adding a critter

Add a case to `src/critters.sh` with a face pair (`FACE`/`BLINK` need to be
the same display width or the statusline jitters), spinner verbs, and a
palette, then `./build.sh`. The five status faces are derived from `FACE` by
swapping the eyes, so a face built from `•` gets weary, asleep and pleased
variants for free.
