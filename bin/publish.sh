#!/usr/bin/env bash
# publish.sh — regenerate docs/data.json from your repos and push (Option A).
# Run this from the mission-control repo (the monitor repo). Requires that this
# repo has a remote and that GitHub Pages is set to serve from /docs.
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$SCRIPT_DIR"
bash bin/status.sh --json > docs/data.json
git add docs/data.json
if git diff --cached --quiet; then echo "no status change — nothing to publish"; exit 0; fi
git commit -qm "status: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
git push
echo "published to Pages."
