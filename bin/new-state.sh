#!/usr/bin/env bash
# new-state.sh <project-path> [category]
# Drops a STATE.md into a project (from STATE.template.md), prefilled with
# the project name, today's date, and optional category. Won't overwrite.

set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TEMPLATE="$SCRIPT_DIR/STATE.template.md"

target="${1:-}"
category="${2:-uncategorized}"
if [ -z "$target" ]; then
  echo "usage: new-state.sh <project-path> [category]" >&2
  exit 1
fi
target="${target/#\~/$HOME}"

[ -d "$target" ] || { echo "not a directory: $target" >&2; exit 1; }
dest="$target/STATE.md"
[ -e "$dest" ] && { echo "STATE.md already exists at $dest — leaving it alone" >&2; exit 0; }

name="$(basename "$target")"
today="$(date +%Y-%m-%d)"

sed -e "s/PROJECT_NAME/$name/" \
    -e "s/^category: uncategorized/category: $category/" \
    -e "s/DATE/$today/" \
    "$TEMPLATE" > "$dest"

echo "created $dest"
