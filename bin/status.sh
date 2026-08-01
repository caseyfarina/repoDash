#!/usr/bin/env bash
# Mission Control — status dashboard
# Auto-discovers git repos under your scan roots and shows any with a commit
# in the last N months, newest first. git facts are deterministic; STATE.md
# (optional, per repo) adds a human summary. No LLM required to run this.
# Portable: Git Bash / WSL / macOS / Linux.

set -uo pipefail

# --- config -----------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
ROOTS_FILE="${MC_ROOTS_FILE:-$SCRIPT_DIR/roots.txt}"   # dirs to scan for repos
PINS_FILE="${MC_REGISTRY:-$SCRIPT_DIR/projects.txt}"   # optional explicit repos
MC_MONTHS="${MC_MONTHS:-4}"          # activity window: show repos committed within N months
STALE_DAYS="${MC_STALE_DAYS:-14}"    # within shown repos, flag ones idle this long
NOW_LINES="${MC_NOW_LINES:-4}"       # max lines shown from each STATE.md "Now"
PRUNE="${MC_PRUNE:-node_modules Library .venv obj Temp Build build dist}"  # dirs to skip while scanning

NOW_EPOCH=$(date +%s)
CUTOFF=$(( NOW_EPOCH - MC_MONTHS * 2629800 ))   # 2629800s ≈ 1 month
RULE="═══════════════════════════════════════════════════════════════"

# --- output format: terminal (default) or --json ----------------------------
FORMAT="term"
for a in "$@"; do [ "$a" = "--json" ] && FORMAT="json"; done
[ "${MC_FORMAT:-}" = "json" ] && FORMAT="json"

# --- colors -----------------------------------------------------------------
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
  BOLD=$'\033[1m'; DIM=$'\033[2m'; RESET=$'\033[0m'
  RED=$'\033[31m'; GRN=$'\033[32m'; YEL=$'\033[33m'; CYN=$'\033[36m'; MAG=$'\033[35m'
else
  BOLD=""; DIM=""; RESET=""; RED=""; GRN=""; YEL=""; CYN=""; MAG=""
fi

# --- helpers ----------------------------------------------------------------
fm() {  # fm <file> <key> -> frontmatter value
  sed -n '/^---[[:space:]]*$/,/^---[[:space:]]*$/p' "$1" 2>/dev/null \
    | grep -m1 "^$2:" | sed "s/^$2:[[:space:]]*//" | tr -d '\r'
}
section() {  # section <file> <heading> -> non-empty lines under "## heading"
  awk -v h="## $2" '
    index($0, h)==1 { grab=1; next }
    /^##[[:space:]]/ && grab { grab=0 }
    grab && NF { sub(/\r$/,""); print }
  ' "$1" 2>/dev/null
}
jesc() {  # escape a string for JSON (single-line fields)
  local s="$1"
  s="${s//\\/\\\\}"; s="${s//\"/\\\"}"
  s="${s//$'\t'/\\t}"; s="${s//$'\r'/}"; s="${s//$'\n'/\\n}"
  printf '%s' "$s"
}
to_json_array() {  # stdin: bullet lines -> ["x","y"] (skips a lone "none")
  local first=1 out="[" l
  while IFS= read -r l; do
    [ -z "$l" ] && continue
    l="${l#- }"; l="${l#\* }"
    echo "$l" | grep -qi '^none$' && continue
    if [ "$first" = 1 ]; then first=0; else out+=","; fi
    out+="\"$(jesc "$l")\""
  done
  out+="]"; printf '%s' "$out"
}
read_list() {  # read_list <file> -> clean paths (strip comments/blanks, expand ~)
  [ -f "$1" ] || return 0
  while IFS= read -r line || [ -n "$line" ]; do
    line="${line%%#*}"
    line="$(echo "$line" | sed 's/[[:space:]]*$//;s/^[[:space:]]*//')"
    [ -z "$line" ] && continue
    echo "${line/#\~/$HOME}"
  done < "$1"
}
find_repos() {  # find_repos <root> -> repo dirs, pruning heavy folders
  local root="$1"; [ -d "$root" ] || return 0
  local expr=(); local d
  for d in $PRUNE; do expr+=( \( -type d -name "$d" -prune \) -o ); done
  find "$root" "${expr[@]}" \( -type d -name .git -prune -print \) 2>/dev/null \
    | while IFS= read -r g; do dirname "$g"; done
}

# --- gather candidates ------------------------------------------------------
# roots -> discovered repos ; pins -> always considered (marked *)
declare -A PINNED=()
candidates=""

while IFS= read -r root; do
  while IFS= read -r repo; do candidates+="$repo"$'\n'; done < <(find_repos "$root")
done < <(read_list "$ROOTS_FILE")

while IFS= read -r pin; do
  candidates+="$pin"$'\n'; PINNED["$pin"]=1
done < <(read_list "$PINS_FILE")

# dedupe, then compute last-commit epoch and apply the activity window
records=""   # each line: <epoch>\t<path>\t<pinned 0/1>
while IFS= read -r p; do
  [ -z "$p" ] && continue
  p="${p%/}"
  if git -C "$p" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    ep="$(git -C "$p" log -1 --format=%ct 2>/dev/null || echo 0)"
  else
    ep=0
  fi
  pin="${PINNED[$p]:-0}"
  if [ "$pin" = 1 ] || { [ "$ep" -gt 0 ] && [ "$ep" -ge "$CUTOFF" ]; }; then
    records+="${ep}	${p}	${pin}"$'\n'
  fi
done < <(printf '%s' "$candidates" | awk 'NF && !seen[$0]++')

# sort by recency, newest first
records="$(printf '%s' "$records" | sort -t$'\t' -k1,1nr)"

# --- render -----------------------------------------------------------------
active=0; stale_ct=0; dirty_ct=0; blocked_ct=0; shown=0
BUFFER=""; JREC=""
emit() { BUFFER+="$1"$'\n'; }

while IFS=$'\t' read -r ep p pin; do
  [ -z "$p" ] && continue
  shown=$((shown+1))
  name="$(basename "$p")"

  # STATE.md (optional)
  state="$p/STATE.md"; s_status=""; s_cat=""; s_updated=""
  if [ -f "$state" ]; then
    s_status="$(fm "$state" status)"; s_cat="$(fm "$state" category)"; s_updated="$(fm "$state" updated)"
  fi
  [ "$s_status" = "active" ] && active=$((active+1))

  # git facts
  branch="$(git -C "$p" rev-parse --abbrev-ref HEAD 2>/dev/null)"
  last_rel="$(git -C "$p" log -1 --format=%cr 2>/dev/null || echo 'no commits')"
  if [ -n "$(git -C "$p" status --porcelain -- . ':(exclude)STATE.md' 2>/dev/null)" ]; then dirty=1; else dirty=0; fi
  lr="$(git -C "$p" rev-list --count --left-right '@{u}...HEAD' 2>/dev/null || true)"
  if [ -n "$lr" ]; then behind="$(echo "$lr" | cut -f1)"; ahead="$(echo "$lr" | cut -f2)"; else behind=0; ahead=0; fi
  days=$(( (NOW_EPOCH - ep) / 86400 )); is_stale=0
  [ "$ep" -gt 0 ] && [ "$days" -ge "$STALE_DAYS" ] && is_stale=1
  [ "$is_stale" = 1 ] && stale_ct=$((stale_ct+1))
  [ "$dirty" = 1 ] && dirty_ct=$((dirty_ct+1))
  last_iso="$(git -C "$p" log -1 --format=%cI 2>/dev/null || echo '')"

  # STATE.md sections (hoisted so both terminal + JSON use them)
  now_txt=""; blocked_txt=""; next_txt=""
  if [ -f "$state" ]; then
    now_txt="$(section "$state" Now)"; blocked_txt="$(section "$state" Blocked)"; next_txt="$(section "$state" Next)"
  fi
  is_blocked=0
  if [ -n "$blocked_txt" ] && ! echo "$blocked_txt" | grep -qi 'none\|^-\?[[:space:]]*$'; then
    is_blocked=1; blocked_ct=$((blocked_ct+1))
  fi

  # ---- JSON mode: accumulate a record, skip terminal formatting ----
  if [ "$FORMAT" = "json" ]; then
    now_json="$(printf '%s\n' "$now_txt" | to_json_array)"
    next_json="$(printf '%s\n' "$next_txt" | to_json_array)"
    blk_json='[]'; [ "$is_blocked" = 1 ] && blk_json="$(printf '%s\n' "$blocked_txt" | to_json_array)"
    [ -n "$JREC" ] && JREC+=","
    JREC+=$(printf '{"name":"%s","category":"%s","status":"%s","branch":"%s","last_commit_rel":"%s","last_commit_iso":"%s","stale":%s,"dirty":%s,"ahead":%s,"behind":%s,"pinned":%s,"now":%s,"next":%s,"blocked":%s}' \
      "$(jesc "$name")" "$(jesc "$s_cat")" "$(jesc "$s_status")" "$(jesc "$branch")" \
      "$(jesc "$last_rel")" "$(jesc "$last_iso")" \
      "$([ "$is_stale" = 1 ] && echo true || echo false)" \
      "$([ "$dirty" = 1 ] && echo true || echo false)" \
      "${ahead:-0}" "${behind:-0}" \
      "$([ "$pin" = 1 ] && echo true || echo false)" \
      "$now_json" "$next_json" "$blk_json")
    continue
  fi

  # header line
  case "$s_status" in
    active) badge="${GRN}active${RESET}" ;; paused) badge="${YEL}paused${RESET}" ;;
    done) badge="${DIM}done${RESET}" ;; "") badge="" ;; *) badge="${CYN}${s_status}${RESET}" ;;
  esac
  cat_txt=""; [ -n "$s_cat" ] && cat_txt=" ${DIM}[${s_cat}]${RESET}"
  pin_mark=""; [ "$pin" = 1 ] && pin_mark=" ${DIM}★${RESET}"
  emit "  ${BOLD}▸ ${name}${RESET}${cat_txt}${badge:+  }${badge}${pin_mark}"

  # git line
  gline="    ${DIM}git${RESET} ${CYN}${branch:-?}${RESET}  ·  "
  if [ "$is_stale" = 1 ]; then gline+="${YEL}⚠ ${last_rel}${RESET}"; else gline+="${last_rel}"; fi
  [ "$dirty" = 1 ] && gline+="  ·  ${YEL}✎ uncommitted${RESET}"
  [ "$ahead" -gt 0 ] 2>/dev/null && gline+="  ·  ${GRN}↑${ahead}${RESET}"
  [ "$behind" -gt 0 ] 2>/dev/null && gline+="  ·  ${RED}↓${behind}${RESET}"
  emit "$gline"

  # STATE.md summary (terminal)
  if [ -n "$now_txt" ]; then
    count=0
    while IFS= read -r l; do [ "$count" -ge "$NOW_LINES" ] && break; emit "    ${l}"; count=$((count+1)); done <<< "$now_txt"
  fi
  if [ "$is_blocked" = 1 ]; then
    while IFS= read -r l; do emit "    ${RED}▲ ${l#- }${RESET}"; done <<< "$blocked_txt"
  fi
  if [ -n "$next_txt" ]; then
    fn="$(echo "$next_txt" | head -n1)"; fn="${fn#- }"; fn="${fn#\* }"
    emit "    ${DIM}next: ${fn}${RESET}"
  fi
  emit ""
done <<< "$records"

# --- JSON output ------------------------------------------------------------
if [ "$FORMAT" = "json" ]; then
  printf '{"generated":"%s","window_months":%s,"stale_days":%s,"summary":{"repos":%s,"active":%s,"stale":%s,"dirty":%s,"blocked":%s},"repos":[%s]}\n' \
    "$(date -u +%Y-%m-%dT%H:%M:%SZ)" "$MC_MONTHS" "$STALE_DAYS" \
    "$shown" "$active" "$stale_ct" "$dirty_ct" "$blocked_ct" "$JREC"
  exit 0
fi

# --- terminal print ---------------------------------------------------------
printf '%s\n' "${BOLD}${MAG}${RULE}${RESET}"
printf '%s\n' "${BOLD}  MISSION CONTROL${RESET}   ${DIM}$(date '+%Y-%m-%d %H:%M')${RESET}"
printf '%s\n' "${BOLD}${MAG}${RULE}${RESET}"
if [ "$shown" -eq 0 ]; then
  printf '%s\n' "  ${DIM}No repos committed to in the last ${MC_MONTHS} months.${RESET}"
  printf '%s\n' "  ${DIM}Add a scan directory to roots.txt (e.g. ~/dev).${RESET}"
  printf '%s\n\n' "${BOLD}${MAG}${RULE}${RESET}"
  exit 0
fi
sm="  ${BOLD}${shown}${RESET} repos ${DIM}(active in ${MC_MONTHS}mo)${RESET}"
sm+="   ${GRN}●${RESET} ${active}"
sm+="   ${YEL}⚠${RESET} stale ${stale_ct}"
sm+="   ${YEL}✎${RESET} dirty ${dirty_ct}"
sm+="   ${RED}▲${RESET} blocked ${blocked_ct}"
printf '%s\n' "$sm"
printf '%s\n' "${DIM}  newest first · stale flag: ${STALE_DAYS}d · ★ = pinned${RESET}"
printf '%s\n\n' "${BOLD}${MAG}${RULE}${RESET}"
printf '%s' "$BUFFER"
