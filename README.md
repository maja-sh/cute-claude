# cute-claude

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
curl -fsSL <url>/dist/cute.sh | bash
```

Pipe it flags the same way:

```sh
curl -fsSL <url>/dist/cute.sh | bash -s -- --critter bnuuy --terminal
```

Or clone and run `dist/cute.sh` directly. Restart Claude Code afterwards.

Requires `bash` and coreutils. **`jq` is needed only when `settings.json` is
actually opened** — that is, with `--terminal`, or when upgrading an install old
enough to have left hooks behind. A plain install needs neither.

Where it is needed it is required rather than optional, because merging into a
`settings.json` this script did not write is not a job for regexes. It is checked
before anything is written, so a missing dependency costs you nothing but the
message telling you to install it — see the note above `preflight_deps` in
`src/installer.sh`.

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

`/pet` leaves a marker in `/tmp` rather than `~/.claude`. A slash command's
`` !`...` `` line is permission-checked and Claude Code refuses writes anywhere
under `~/.claude` as sensitive, so a marker there fails outright.

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

## Development

```
build.sh                    src/ -> dist/cute.sh
src/installer.sh            args, preflight, manifest, claim/revert, install flow
src/critters.sh             the critter table — faces, spinner verbs, palettes
src/assets/statusline.sh    the statusline program
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
