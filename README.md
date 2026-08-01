# Mission Control

A single-glance status dashboard for all your Claude Code projects. Point it at
the folder(s) where your repos live; it **auto-discovers every git repo** and
shows any with a commit in the last 4 months, newest first. Two layers per repo:

- **git facts** (automatic, zero upkeep): branch, last-commit age, uncommitted
  changes, ahead/behind remote, staleness flag.
- **STATE.md** (optional, per repo): what you're working on `Now`, what's `Next`,
  what's `Blocked`. Repos without one just show git facts — that's fine.

It's a plain **terminal** dashboard (not a web page): a bash script that runs in
any shell with no LLM and no token cost. Claude Code sits on top of it (via
`CLAUDE.md`) to add "what should I work on today" judgment, not to compute status.

```
mission-control/
├── CLAUDE.md            # session-start protocol for Claude Code
├── roots.txt            # dirs to scan for repos  ← the main thing you edit
├── projects.txt         # optional pinned repos (★), shown regardless of age
├── STATE.template.md    # optional per-repo status file template
├── README.md
└── bin/
    ├── status.sh        # the dashboard (run this)
    └── new-state.sh     # scaffold a STATE.md into a repo
```

## Setup (about 2 minutes)

1. Put this folder somewhere, e.g. `~/dev/mission-control`.
2. `chmod +x bin/status.sh bin/new-state.sh`
3. Edit `roots.txt` — add the directory where your repos live (e.g. `~/dev`).
4. Run it: `bash bin/status.sh`

That's it. Every repo you've committed to in the last 4 months shows up. No
per-project setup required.

## Optional: richer summaries

For repos where you want a written status beyond git facts, drop in a STATE.md:

```
bash bin/new-state.sh ~/dev/midiFighterForUnity unity
```

Then edit its `## Now` / `## Next` / `## Blocked` sections. The dashboard picks
it up automatically.

## Daily use

- **Standalone glance:** `bash bin/status.sh`, or alias it:
  `alias mc='bash ~/dev/mission-control/bin/status.sh'`
- **With Claude Code:** launch Claude Code in this directory; `CLAUDE.md` tells
  it to run the dashboard, flag what needs attention, and ask what you want to
  work on. Ask it to `/update` a repo's STATE.md when you finish there.

## Web dashboard (GitHub Pages)

There's also a browser version in `docs/` — a static page styled after a
brutalist terminal aesthetic (black, blast-orange, pixel type) that renders your
repos as an asterisk-bulleted project index. It reads `docs/data.json`, which
`status.sh --json` produces:

```
bash bin/status.sh --json > docs/data.json   # generate the feed
open docs/index.html                          # preview locally
```

To host it on GitHub Pages and keep it auto-updating, see `DEPLOY.md` (two
pipelines: local-generate-and-push, or a GitHub Action). All visual tokens are
CSS variables at the top of `docs/index.html`.

## Tunables (environment variables)

| var             | default                     | meaning                                        |
|-----------------|-----------------------------|------------------------------------------------|
| `MC_MONTHS`     | `4`                         | activity window — show repos committed within N months |
| `MC_STALE_DAYS` | `14`                        | flag shown repos idle this long (⚠)            |
| `MC_NOW_LINES`  | `4`                         | max lines shown from each `## Now`             |
| `MC_ROOTS_FILE` | `./roots.txt`               | scan-roots file                                |
| `MC_REGISTRY`   | `./projects.txt`            | pinned-repos file                              |
| `MC_PRUNE`      | `node_modules Library …`    | folder names skipped while scanning            |

Examples: `MC_MONTHS=6 bash bin/status.sh` · `MC_MONTHS=1 mc`

## Windows

Run under **Git Bash** or **WSL** (git, awk, sed, date, find all present). Use
forward-slash paths in `roots.txt`, e.g. `/c/Users/casey/dev`. Unity `Library/`
folders are pruned during the scan, so big projects don't slow it down.

## What it does NOT do

Read-only. It never commits, pushes, edits project code, or deploys. The only
file it writes is a repo's `STATE.md`, and only when you ask.
