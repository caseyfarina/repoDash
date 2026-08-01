# Deploying the web dashboard (GitHub Pages)

The web dashboard lives in `docs/` — a static page (`docs/index.html`) that
renders from `docs/data.json`. GitHub Pages serves static files only; it never
runs your scripts and can't see your local machine. So the whole design question
is **how `data.json` gets produced**. Pick one of the two pipelines below.

## First: make this a repo and turn on Pages

```
cd mission-control
git init && git add . && git commit -m "mission control"
git remote add origin git@github.com:YOU/mission-control.git
git push -u origin main
```

Then on GitHub: **Settings → Pages → Source: Deploy from a branch →
Branch: `main` / folder: `/docs`**. Your dashboard will be at
`https://YOU.github.io/mission-control/`.

It renders immediately using the sample `data.json`. Now wire real data:

---

## Option A — Local generate + push  (captures uncommitted/local state)

Your machine produces `data.json` and pushes it. This is the only option that
can see uncommitted changes (✎) and local, unpushed STATE.md files, because that
state exists nowhere but your disk.

```
bash bin/publish.sh
```

`publish.sh` runs `status.sh --json > docs/data.json`, commits, and pushes.
Automate it so you don't have to think about it:

- **Windows (Task Scheduler):** schedule `bash -lc '~/dev/mission-control/bin/publish.sh'`
  hourly, or on login.
- **cron (mac/Linux/WSL):** `0 * * * * ~/dev/mission-control/bin/publish.sh`
- **git hook:** call it from a `post-commit` hook in the repos you care about.

Freshness = last push. Only your machine can update it.

---

## Option B — GitHub Action + GitHub API  (fully hosted, auto-updating)

A scheduled Action lists every repo you own, keeps those pushed to in the last
4 months, reads each one's committed STATE.md, and writes `docs/data.json` —
all on GitHub's servers, hourly, no local machine involved. The files are
already here: `.github/workflows/status.yml` and `bin/build-data.mjs`.

Trade-offs: the API can't see uncommitted changes (so ✎ dirty never fires under
B), and it only covers GitHub-hosted repos. STATE.md summaries appear only for
repos that have a `STATE.md` committed to their default branch.

**Setup:**

1. **Create a token.** The Action needs to read your *other* repos, which the
   built-in `GITHUB_TOKEN` can't do. Make a fine-grained PAT:
   GitHub → Settings → Developer settings → **Fine-grained tokens** → Generate.
   - Resource owner: your account
   - Repository access: **All repositories** (or select the ones you want shown)
   - Permissions → Repository → **Contents: Read-only** and **Metadata: Read-only**
   (A classic PAT with the `repo` scope also works but grants more than needed.)

2. **Add it as a secret.** In the `mission-control` repo:
   Settings → Secrets and variables → **Actions** → New repository secret →
   name it `MC_TOKEN`, paste the token.

3. **Turn on Pages** (same as above): Settings → Pages → Deploy from a branch →
   `main` / `/docs`.

4. **Run it once** to seed the data: Actions tab → `mission-control` → **Run
   workflow**. After it finishes, `docs/data.json` is committed and the page is
   live. It then refreshes itself hourly.

**Tuning** happens in the workflow's `env:` block — `MC_MONTHS`, `MC_STALE_DAYS`,
`MC_EXCLUDE_ARCHIVED`, `MC_EXCLUDE_FORKS`. To add STATE.md summaries to a repo,
commit one to it (`bin/new-state.sh <repo> <category>`, then commit + push from
that repo).

**Cost/limits:** authenticated API allows 5000 calls/hour — this uses roughly
one per in-window repo, far under it. Hourly runs on a private repo consume
Action minutes (2000/month free); public repos are unlimited. The bot's own
commits don't retrigger the workflow, so there's no loop.

---

## Privacy note

If any monitored repos are private, a **public** Pages site exposes their
names, commit activity, and STATE.md text. To keep it private, make the
`mission-control` repo private and use private Pages (requires a paid GitHub
plan). Otherwise assume the dashboard is world-readable.

## Tuning the front-end

All visual tokens (colors, fonts, type scale) are CSS variables at the top of
`docs/index.html`. The accent is `--orange: #ff4b12`. The page auto-refetches
`data.json` every 60s, so an auto-updating Option-B feed stays live without a
manual reload.
