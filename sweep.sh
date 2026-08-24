#!/usr/bin/env bash
# OSS VRP CI/supply-chain sweep loop.
# For each repo: clone -> secret scan (history) -> GH Actions audit -> dep scan ->
# FLAG (keep for review) or CLEAN (delete). Resumable; logs every verdict.
#
#   bash sweep.sh [repos.txt]
#   ONE=google/osv-scanner bash sweep.sh     # single repo
#   KEEP=1 bash sweep.sh                      # never delete (debug)
set -uo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
WORK="${WORK:-$ROOT/work}"; OUT="$ROOT/reports"; FLAGS="$ROOT/FLAGGED"
mkdir -p "$WORK" "$OUT" "$FLAGS"
MASTER="$OUT/_master.md"; DONE="$OUT/_done.txt"; touch "$DONE"
LIST="${1:-$ROOT/repos.txt}"
[ -f "$MASTER" ] || echo -e "# OSS VRP sweep — verdict log\n\n| repo | tier | secrets | gha | deps | verdict |\n|---|---|---|---|---|---|" > "$MASTER"

audit() {
  local slug="$1" tier="$2" name="${1##*/}" dir sec_v gha_v dep_v flagged=0
  dir="$WORK/$name"
  grep -qx "$slug" "$DONE" && { echo "[skip] $slug (done)"; return; }
  echo "=================== $slug ($tier) ==================="
  rm -rf "$dir"
  if ! git clone --quiet --depth "${DEPTH:-1}" "https://github.com/$slug" "$dir" 2>"$OUT/$name.clone.err"; then
    echo "  clone FAILED"; echo "$slug | $tier | - | - | - | CLONE-FAIL" >> "$MASTER"; echo "$slug" >> "$DONE"; return
  fi

  # 1) secrets — verified (trufflehog) is high-signal; gitleaks history is broad
  sec_v="none"
  if command -v trufflehog >/dev/null; then
    trufflehog --no-update git "file://$dir" --only-verified --json > "$OUT/$name.trufflehog.json" 2>/dev/null || true
    [ -s "$OUT/$name.trufflehog.json" ] && { sec_v="VERIFIED-SECRET"; flagged=1; }
  fi
  if command -v gitleaks >/dev/null; then
    gitleaks detect --source "$dir" --report-format json --report-path "$OUT/$name.gitleaks.json" --redact -l error >/dev/null 2>&1 || true
    local gc; gc=$(jq 'length' "$OUT/$name.gitleaks.json" 2>/dev/null || echo 0)
    [ "${gc:-0}" -gt 0 ] && { [ "$sec_v" = none ] && sec_v="gitleaks:$gc"; }
  fi

  # 2) GitHub Actions supply-chain
  bash "$ROOT/gha-audit.sh" "$dir" > "$OUT/$name.gha.txt" 2>/dev/null
  local gr=$?; gha_v="ok"; grep -q '\*\*\* HIGH' "$OUT/$name.gha.txt" && { gha_v="HIGH"; flagged=1; }
  [ "$gha_v" = ok ] && grep -qE '== MED|== INFO' "$OUT/$name.gha.txt" && gha_v="notes"

  # 3) dependency known-vulns (low VRP value but cheap context)
  dep_v="-"
  if command -v osv-scanner >/dev/null; then
    osv-scanner scan --format json --output "$OUT/$name.osv.json" "$dir" >/dev/null 2>&1 || true
    local dc; dc=$(jq '[.results[].packages[].vulnerabilities[]?]|length' "$OUT/$name.osv.json" 2>/dev/null || echo 0)
    dep_v="${dc:-0}"
  fi

  # verdict
  if [ "$flagged" = 1 ]; then
    echo "  >>> FLAGGED (secrets=$sec_v gha=$gha_v) — kept for review"
    cp -r "$OUT/$name."* "$FLAGS/" 2>/dev/null || true
    echo "$slug | $tier | $sec_v | $gha_v | $dep_v | *** FLAGGED ***" >> "$MASTER"
    echo "$dir" > "$FLAGS/$name.location.txt"     # keep the clone; do NOT delete
  else
    echo "  clean (gha=$gha_v deps=$dep_v) — deleting clone"
    echo "$slug | $tier | $sec_v | $gha_v | $dep_v | clean" >> "$MASTER"
    [ "${KEEP:-0}" = 1 ] || rm -rf "$dir"
  fi
  echo "$slug" >> "$DONE"
}

if [ -n "${ONE:-}" ]; then
  t=$(grep -E "^${ONE//\//\/} " "$LIST" | awk '{print $2}'); audit "$ONE" "${t:-?}"
else
  grep -vE '^\s*#|^\s*$' "$LIST" | while read -r slug tier prio _; do audit "$slug" "$tier"; done
fi
echo; echo "Done. Verdicts: $MASTER   Flags: $FLAGS/"
grep -c 'FLAGGED' "$MASTER" 2>/dev/null | xargs -I{} echo "{} repo(s) flagged for review."
