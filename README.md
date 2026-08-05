# cute-claude

[![ci](https://github.com/hbackman/cute-claude/actions/workflows/ci.yml/badge.svg)](https://github.com/hbackman/cute-claude/actions/workflows/ci.yml)

![demo](docs/demo.gif)

Sets up a warm, critter-flavored Claude Code persona: a tone guide in
`CLAUDE.md`, and optionally a theme, an animated statusline, critter-flavored
spinner verbs, and a handful of slash commands.

It installs **no hooks**. Without `--terminal` it writes `CLAUDE.md` and nothing
else, so `settings.json` is never opened.

Everything it writes lives under `~/.claude`, is backed up first, and is
recorded in a manifest, so `--revert` puts your environment back exactly as it
was — including un-merging only its own keys from a `settings.json` you already
had.

## Install

```sh
curl -fsSL https://maja.sh/cute.sh | bash
```

Pipe it flags the same way:

```sh
curl -fsSL https://maja.sh/cute.sh | bash -s -- --critter bnuuy --terminal
```

Or clone it and run `./build.sh` first — `dist/` is not committed.
Restart Claude Code afterwards.

Requires `bash` and coreutils. **`jq` is needed only when `settings.json` is
actually opened** — that is, with `--terminal`, or when upgrading an install old
enough to have left hooks behind. A plain install needs neither.

Where it is needed it is required rather than optional, because merging into a
`settings.json` this script did not write is not a job for regexes. It is checked
before anything is written, so a missing dependency costs you nothing but the
message telling you to install it — see the note above `preflight_deps` in
`src/installer.sh`.

## Verifying it before you run it

Piping a script from the internet into your shell is a reasonable thing to
refuse, so this is checkable rather than asking for trust.

`maja.sh/cute.sh` redirects to the latest [release](../../releases), which is
built from a tag by [the release workflow](.github/workflows/release.yml) —
never uploaded by hand. Each release carries the script and a `.sha256`.

The build is **deterministic**: identical sources always produce a
byte-identical artifact, and `--version` prints a content hash of `src/`. So the
published file can be reproduced from source rather than taken on faith:

```sh
curl -fsSL https://maja.sh/cute.sh | bash -s -- --version   # cute-claude build N

git clone https://github.com/hbackman/cute-claude && cd cute-claude
git checkout <the release tag>
./build.sh && ./dist/cute.sh --version                      # same N
```

Matching build ids mean the file you are about to pipe is exactly what this
source compiles to — verified against the repository rather than against the
host that served it. CI asserts the determinism the check depends on, on every
push.

Or skip the pipe: clone it, run `./build.sh`, and execute `dist/cute.sh`
yourself.

## What it writes

| Path | What | Needs |
|---|---|---|
| `~/.claude/CLAUDE.md` | tone guide — the persona itself | always |
| `~/.claude/settings.json` | statusline, spinner verbs, theme | `--terminal` (merged, never replaced) |
| `~/.claude/statusline.sh` | the animated statusline | `--terminal` |
| `~/.claude/themes/kitten.json` | the color theme | `--terminal` |
| `~/.claude/commands/{pet,treat,critter}.md` | `/pet`, `/treat`, `/critter` | `--commands` |

`CLAUDE.md` and the slash commands work everywhere — the terminal, the VS Code
panel, and Zed's ACP adapter, all of which read `CLAUDE.md` directly. The theme,
statusline and spinner verbs are **terminal-only**: they are Claude Code's own
CLI chrome, and other frontends draw their own UI, so there is no surface for
them to appear on.

Nothing here writes anything at runtime. A slash command's `` !`...` `` line is
permission-checked, and every absolute path it could use is refused — under
`~/.claude` as a sensitive file, anywhere else as outside the session's allowed
working directory — so `/pet` executes nothing at all. The statusline notices it
by reading the transcript instead, which needs no permission and works in every
frontend.

## Options

| Flag | Meaning |
|---|---|
| `--critter <name>` | `cat` (default), `bnuuy`, `fox`, `raven`, or any name at all |
| `--vibe <cute\|dry>` | how warm the tone is. `dry` keeps the humor, drops the hearts |
| `--vibe-extra "<words>"` | folds your own descriptor into the vibe line |
| `--profile <work\|personal>` | shorthand. `work` = `--vibe dry`; `personal` = cute + `--terminal --commands` |
| `--terminal` | theme, statusline, spinner verbs |
| `--commands` | `/pet`, `/treat`, `/critter` |
| `--append` | keep an existing `CLAUDE.md` and add the tone guide below it |
| `--upgrade` | reinstall with the options the last run recorded |
| `--doctor` | check the install is actually wired up, not merely present |
| `--list` | show the built-in critters |
| `--revert` | undo everything |
| `--version` | which build this is |

An unknown critter is fully supported, not a fallback: it gets a face chosen
deterministically from its name, and `CLAUDE.md` asks Claude to invent that
critter's noises and habits and keep them consistent. The flavor is generated at
read time by the thing reading it.

## Checking it works

```sh
dist/cute.sh --doctor
```

"Is it installed" is the easy question and not the useful one. Files can all be
present while nothing is wired: something rewrites `settings.json`, `statusLine`
and the theme go with it, and the statusline script sits there doing nothing
with no error anywhere to tell you. `--doctor` checks the wiring rather than the
inventory, reports anything half-applied, and exits non-zero if it found a
problem.

It also works on installs predating the manifest — those are the ones most
likely to have drifted, so it runs the wiring checks anyway and only skips the
per-file checksums it has nothing to compare against.

## Upgrading

```sh
dist/cute.sh --upgrade
```

Each install records its own options in the manifest, so `--upgrade` replays
them rather than making you remember whether it was `--critter raven --vibe dry
--terminal`. Any flag you pass explicitly still wins; `--profile` is refused
alongside it, because both want to be the base layer under your explicit flags
and guessing which one wins is worse than saying so.

## An existing `CLAUDE.md`

If `~/.claude/CLAUDE.md` is there and cute-claude did not write it, that is
someone's own global instructions — the one file here that people hand-write.
It is backed up and replaced, with a warning saying so and pointing at:

```sh
dist/cute.sh --append
```

which keeps your file and puts the tone guide underneath it instead. Either way
`--revert` restores exactly what you had. It warns rather than refusing, because
refusing by default would break the one-line install for precisely the people
most likely to have opinions about their `CLAUDE.md`.

## Reverting

```sh
dist/cute.sh --revert
```

Files it created are deleted; files it replaced are restored from their backups;
`settings.json` has only cute-claude's own keys removed, so anything
you changed since installing survives. If you edited a file it wrote, a reinstall
keeps your version alongside as `<name>.local.<timestamp>` rather than
discarding it.

## Licence

[0BSD](LICENSE) — do whatever you like with it, no attribution required. If you
want to use it as a base for your own Claude personalisation, that is what it is
for.

## The demo

`docs/demo.gif` is rendered from an [asciinema](https://asciinema.org) recording
with [agg](https://github.com/asciinema/agg):

```sh
agg demo.cast docs/demo.gif --fps-cap 10 \
  --font-family "Menlo,Ayuthaya,Courier New,STIX Two Math,Monaco,Hiragino Sans"
```

The font list is not decoration. The critter face is assembled from Thai (`ฅ`),
Arabic (`ﻌ`) and assorted modifier letters, none of which live in a coding font —
a terminal resolves them through its own fallback chain, and a renderer has to be
told the same chain or it draws tofu. Those families are what macOS selects; on
Linux, substitute equivalents with the same coverage.

## Development

```
build.sh                    src/ -> dist/cute.sh
src/installer.sh            args, preflight, manifest, claim/revert, install flow
src/critters.sh             the critter table — faces, spinner verbs, palettes
src/assets/statusline.sh    the statusline program
dist/cute.sh                the built artifact — gitignored, attached to releases
tests/run.sh                the suite
```

**Edit `src/`, never `dist/cute.sh`.** The artifact is generated, gitignored,
and published by the release workflow — anything you type into it is silently
undone by the next build. `./build.sh --check` tells you whether your local
`dist/` is stale.

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
```

The build is deterministic — same sources in, byte-identical file out. Do not
put a timestamp in it; `--check` depends on that.

The suite runs every case against a throwaway `$HOME`, so it cannot touch your
real `~/.claude`. It needs `jq` and nothing else.

### Adding a critter

Add a case to `src/critters.sh` with a face pair (`FACE`/`BLINK` must be the
same display width or the statusline jitters), spinner verbs, and a palette,
then `./build.sh`. The five status faces are derived from `FACE` by substituting
the eyes, so a face built from `•` gets weary, asleep and pleased variants for
free.
