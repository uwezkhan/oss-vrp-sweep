#!/usr/bin/env bash
# GitHub Actions supply-chain risk analyzer. Usage: gha-audit.sh <repo_dir>
# Emits findings to stdout; exit 10 if any HIGH-signal pattern hit, else 0.
set -uo pipefail
DIR="${1:?repo dir}"; WF="$DIR/.github/workflows"
HIGH=0
say(){ echo "$1"; }
[ -d "$WF" ] || { echo "no .github/workflows"; exit 0; }

FILES=$(find "$WF" -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
[ -z "$FILES" ] && { echo "no workflow files"; exit 0; }

# --- HIGH: dangerous triggers ---
PWN=$(grep -lEn 'pull_request_target|workflow_run' $FILES 2>/dev/null || true)
if [ -n "$PWN" ]; then
  say "== triggers: pull_request_target / workflow_run =="
  for f in $PWN; do
    say "  [trigger] $f"
    # PR-head checkout inside a privileged trigger = classic pwn-request RCE/secret-exfil
    if grep -qEn 'actions/checkout' "$f" && grep -qEn 'ref:\s*.*(head\.sha|head\.ref|pull_request\.head|github\.event\.workflow_run\.head)' "$f"; then
      say "  *** HIGH: privileged trigger CHECKS OUT untrusted PR/head code -> $f"; HIGH=1
    fi
  done
fi

# --- HIGH: script injection (untrusted expr interpolated into run:) ---
INJ=$(grep -rEn '\$\{\{\s*github\.(event\.(issue|pull_request|comment|review|discussion|commits)|head_ref)[^}]*\}\}' $FILES 2>/dev/null || true)
if [ -n "$INJ" ]; then
  say "== untrusted \${{ github.* }} expressions (review each: is it inside a run: shell step?) =="
  echo "$INJ" | sed 's/^/  /'
  # crude: flag HIGH if such an expr appears and the file has run: steps
  for f in $(echo "$INJ" | cut -d: -f1 | sort -u); do
    grep -qEn '^\s*run:' "$f" && { say "  *** HIGH: untrusted expr + run: step in $f (script-injection candidate)"; HIGH=1; }
  done
fi

# --- MED: self-hosted runners on (likely public) repo ---
SH=$(grep -rEn 'runs-on:.*self-hosted' $FILES 2>/dev/null || true)
[ -n "$SH" ] && { say "== MED: self-hosted runners =="; echo "$SH" | sed 's/^/  /'; }

# --- MED: GITHUB_TOKEN write perms ---
WR=$(grep -rEn 'permissions:\s*write-all|contents:\s*write|packages:\s*write|id-token:\s*write' $FILES 2>/dev/null || true)
[ -n "$WR" ] && { say "== MED: elevated GITHUB_TOKEN / OIDC perms (check fork-triggered exposure) =="; echo "$WR" | sed 's/^/  /'; }

# --- INFO: unpinned third-party actions (not SHA-pinned) ---
UP=$(grep -rEn 'uses:\s*[^ ]+@(v?[0-9][^ ]*|main|master)\s*$' $FILES 2>/dev/null | grep -vE 'uses:\s*(actions|github)/' || true)
[ -n "$UP" ] && { say "== INFO: unpinned 3rd-party actions (tag not 40-hex SHA) =="; echo "$UP" | head -20 | sed 's/^/  /'; }

exit $([ "$HIGH" = 1 ] && echo 10 || echo 0)
