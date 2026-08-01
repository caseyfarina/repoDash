#!/usr/bin/env node
// build-data.mjs — Option B feed builder (runs in GitHub Actions).
// Lists all repos owned by the token's account, keeps those pushed to within
// MC_MONTHS months, reads each one's committed STATE.md, and writes
// docs/data.json in the same schema as `status.sh --json`.
//
// Cannot see uncommitted work (dirty) — that's local-only, so dirty is always
// false here. STATE.md summaries require STATE.md to be committed to the repo.

import { writeFileSync } from "node:fs";

const TOKEN = process.env.MC_TOKEN;
if (!TOKEN) { console.error("MC_TOKEN is not set (add it as an Actions secret)."); process.exit(1); }
const MONTHS = Number(process.env.MC_MONTHS || 4);
const STALE_DAYS = Number(process.env.MC_STALE_DAYS || 14);
const EXCLUDE_ARCHIVED = (process.env.MC_EXCLUDE_ARCHIVED ?? "true") !== "false";
const EXCLUDE_FORKS = (process.env.MC_EXCLUDE_FORKS ?? "false") === "true";

const API = "https://api.github.com";
const headers = {
  Authorization: `Bearer ${TOKEN}`,
  Accept: "application/vnd.github+json",
  "X-GitHub-Api-Version": "2022-11-28",
  "User-Agent": "mission-control",
};

async function gh(path) {
  const res = await fetch(API + path, { headers });
  if (!res.ok) throw new Error(`${res.status} ${res.statusText} — ${path}`);
  return res;
}

async function listOwnedRepos() {
  const repos = [];
  for (let page = 1; page <= 20; page++) {
    const res = await gh(`/user/repos?per_page=100&affiliation=owner&sort=pushed&page=${page}`);
    const batch = await res.json();
    repos.push(...batch);
    if (batch.length < 100) break;
  }
  return repos;
}

// --- STATE.md parsing (mirrors status.sh: fm() and section()) ---------------
function frontmatter(md, key) {
  const m = md.match(/^---\s*\r?\n([\s\S]*?)\r?\n---\s*/);
  if (!m) return "";
  const line = m[1].split(/\r?\n/).find((l) => l.startsWith(key + ":"));
  return line ? line.slice(key.length + 1).trim() : "";
}
function section(md, heading) {
  const out = [];
  let grab = false;
  for (const raw of md.split(/\r?\n/)) {
    const line = raw.replace(/\r$/, "");
    if (line.startsWith(`## ${heading}`)) { grab = true; continue; }
    if (/^##\s/.test(line) && grab) grab = false;
    if (grab && line.trim()) out.push(line.replace(/^[-*]\s+/, "").trim());
  }
  return out;
}
async function getState(owner, repo, branch) {
  try {
    const res = await fetch(`${API}/repos/${owner}/${repo}/contents/STATE.md?ref=${branch}`, { headers });
    if (!res.ok) return null;
    const j = await res.json();
    const md = Buffer.from(j.content, "base64").toString("utf8");
    return {
      status: frontmatter(md, "status"),
      category: frontmatter(md, "category"),
      now: section(md, "Now"),
      next: section(md, "Next"),
      blocked: section(md, "Blocked").filter((x) => x.toLowerCase() !== "none"),
    };
  } catch { return null; }
}

// --- build ------------------------------------------------------------------
const now = Date.now();
const cutoff = now - MONTHS * 2629800 * 1000;
const staleMs = STALE_DAYS * 86400 * 1000;

const all = await listOwnedRepos();
const chosen = all
  .filter((r) => {
    if (EXCLUDE_ARCHIVED && r.archived) return false;
    if (EXCLUDE_FORKS && r.fork) return false;
    return new Date(r.pushed_at).getTime() >= cutoff;
  })
  .sort((a, b) => new Date(b.pushed_at) - new Date(a.pushed_at));

const repos = [];
let active = 0, stale = 0, blocked = 0;
for (const r of chosen) {
  const st = await getState(r.owner.login, r.name, r.default_branch);
  const isStale = now - new Date(r.pushed_at).getTime() >= staleMs;
  const isBlocked = !!(st && st.blocked.length);
  if (st?.status === "active") active++;
  if (isStale) stale++;
  if (isBlocked) blocked++;
  repos.push({
    name: r.name,
    category: st?.category || "",
    status: st?.status || "",
    branch: r.default_branch,
    last_commit_iso: r.pushed_at,
    last_commit_rel: "",
    stale: isStale,
    dirty: false,
    ahead: 0, behind: 0,
    pinned: false,
    now: st?.now || [],
    next: st?.next || [],
    blocked: st?.blocked || [],
  });
}

const data = {
  generated: new Date().toISOString(),
  window_months: MONTHS,
  stale_days: STALE_DAYS,
  summary: { repos: repos.length, active, stale, dirty: 0, blocked },
  repos,
};

writeFileSync("docs/data.json", JSON.stringify(data, null, 2) + "\n");
console.log(`wrote docs/data.json — ${repos.length} repos in the last ${MONTHS} months`);
