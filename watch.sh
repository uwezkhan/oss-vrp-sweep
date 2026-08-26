#!/usr/bin/env bash
# Daily OSS VRP watcher: detect NEWLY tier-listed repos and sweep only those.
#   bash watch.sh --seed   # run ONCE at setup: record current list without sweeping
#   bash watch.sh          # daily: sweep only repos added since last run, publish NEW-FLAGS.md
set -uo pipefail
export GIT_TERMINAL_PROMPT=0
ROOT="$(cd "$(dirname "$0")" && pwd)"
TIER_URL="https://raw.githubusercontent.com/google/bughunters/main/oss-repository-tier/external_repositories.txtpb"
SEEN="$ROOT/tier-seen.txt"; touch "$SEEN"
LOG="$ROOT/watch.log"; NEWFLAGS="$ROOT/NEW-FLAGS.md"
log(){ echo "$(date -u +%FT%TZ) $*" >> "$LOG"; }

# Fetch + parse current OSS VRP repos as owner/repo (tolerate UTF-16 by stripping NULs).
parse_current() {
  curl -fsSL "$TIER_URL" | tr -d '\000' | awk '
    /repository[[:space:]]*\{/ { url=""; scope="" }
    /url:/            { if (match($0,/github\.com\/[^"]+/)) url=substr($0,RSTART+11,RLENGTH-11) }
    /product_vuln_scope:/ { scope=$0 }
    /\}/ { if (url!="" && scope ~ /SCOPE_OSS_VRP/) print url; url=""; scope="" }
  ' | sed 's#/*$##' | sort -u
}

cur="$(parse_current)"
[ -z "$cur" ] && { log "FAIL: tier fetch/parse returned nothing"; exit 1; }

if [ "${1:-}" = "--seed" ]; then
  printf '%s\n' "$cur" | sort -u > "$SEEN"
  log "seeded $(wc -l < "$SEEN") repos (no sweep)"
  echo "Seeded $(wc -l < "$SEEN") repos into tier-seen.txt. Daily runs will sweep only additions."
  exit 0
fi

new="$(comm -23 <(printf '%s\n' "$cur") <(sort -u "$SEEN"))"
if [ -z "$new" ]; then log "no new repos"; exit 0; fi
n=$(printf '%s\n' "$new" | grep -c .)
log "detected $n new repo(s): $(echo $new)"

# Sweep only the new repos (fresh per-run state).
list="$ROOT/.new-repos.txt"; printf '%s OT? A\n' $new > "$list"
rm -rf "$ROOT/reports" "$ROOT/FLAGGED" "$ROOT/work"
bash "$ROOT/sweep.sh" "$list" >> "$LOG" 2>&1

# Summarize into NEW-FLAGS.md (committed; readable via raw GitHub for the daily routine).
{
  echo "# OSS VRP new-repo sweep — $(date -u +%F)"
  echo; echo "**$n new OSS VRP repo(s) detected & swept:**"; echo '```'; echo "$new"; echo '```'; echo
  if ls "$ROOT/FLAGGED/"*.gha.txt >/dev/null 2>&1; then
    echo "## ⚠️ FLAGGED — needs triage"
    for f in "$ROOT/FLAGGED/"*.gha.txt; do
      echo "### $(basename "$f" .gha.txt)"; echo '```'
      grep '\*\*\* HIGH' "$f" 2>/dev/null || echo "(secrets flag — see reports/)"; echo '```'
    done
    echo; echo "_Ask the assistant to triage these before reporting (dup-check first)._"
  else
    echo "## ✅ No HIGH flags in the new repos."
  fi
  echo; echo "Verdict table:"; echo '```'; cat "$ROOT/reports/_master.md" 2>/dev/null; echo '```'
} > "$NEWFLAGS"

# Mark seen + publish.
printf '%s\n' $new >> "$SEEN"; sort -u -o "$SEEN" "$SEEN"
cd "$ROOT"
git add NEW-FLAGS.md tier-seen.txt 2>/dev/null
git -c user.email="digiscrypt@gmail.com" -c user.name="uwezkhan" commit -q -m "watch: swept $n new repo(s) $(date -u +%F)" 2>/dev/null \
  && (git push -q origin master 2>/dev/null && log "published NEW-FLAGS.md" || log "push FAILED (run 'gh auth setup-git')")
log "done: $n new, $(ls "$ROOT/FLAGGED" 2>/dev/null | wc -l) flag file(s)"
