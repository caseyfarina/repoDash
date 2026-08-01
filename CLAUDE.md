# Mission Control

This directory is a read-only status dashboard for all my active projects.
It is a **command center, not the ground crew** — it reports status and helps
me decide what to work on. It never modifies project code or deploys anything.

## Session Start Protocol

When a session starts here, do this immediately, without being asked:

1. Run `bash bin/status.sh` and show me its full output verbatim.
   (This is deterministic — it reads git facts + each project's STATE.md.
   Do not re-derive status by reading files yourself; the script is the
   source of truth. Just run it.)
2. In one short paragraph, point out anything that needs attention:
   projects flagged stale (⚠), anything Blocked (▲), or uncommitted work (✎).
3. Ask: "What do you want to work on today?"

Keep step 2 to a few sentences. Do not restate the whole dashboard in prose —
the table already shows it.

## Updating a project's status

When I finish working in a project (or ask you to `/update` it), update that
project's `STATE.md`:
- Move completed items out of `## Now`.
- Promote the top of `## Next` into `## Now` if I've started it.
- Refresh the `updated:` frontmatter date to today.
- Keep `## Now` to a few lines — it's a glance, not a log.

Never touch anything in a project other than its `STATE.md` from here.

## Adding a project

Nothing to do — the dashboard auto-discovers every git repo under the scan
roots in `roots.txt` and shows any committed to in the last 4 months. To make
a repo show up, just commit to it (or add its parent dir to `roots.txt`).

Two optional extras:
- For a written summary beyond git facts: `bash bin/new-state.sh <repo> <category>`
- To force-show a repo that's been quiet longer than the window: add its path
  to `projects.txt` (it'll be marked ★).

## Notes

- The dashboard runs fine standalone (`bash bin/status.sh`) with no LLM — wire
  it to a desktop shortcut for a zero-cost morning glance.
- Tunables via env vars: `MC_MONTHS` (activity window, default 4),
  `MC_STALE_DAYS` (default 14), `MC_NOW_LINES` (default 4),
  `MC_ROOTS_FILE` (default ./roots.txt), `MC_REGISTRY` (pins, default ./projects.txt).
- To let me run the dashboard without a permission prompt each time, allowlist
  `bin/status.sh` in your Claude Code settings.
