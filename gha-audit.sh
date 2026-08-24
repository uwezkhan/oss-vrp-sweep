#!/usr/bin/env bash
# GitHub Actions security audit.
# Primary: zizmor (precise; distinguishes injectable run: text from safe env: vars).
# Fallback: conservative regex (only if zizmor is unavailable).
# Emits "*** HIGH ..." lines for High-severity findings (sweep.sh flags on these).
set -uo pipefail
DIR="${1:?repo dir}"; WF="$DIR/.github/workflows"
[ -d "$WF" ] || { echo "no .github/workflows"; exit 0; }

if command -v zizmor >/dev/null 2>&1; then
  S=$(zizmor --offline --format sarif "$WF" 2>/dev/null || true)
  if [ -n "$S" ] && echo "$S" | jq -e '.runs[0].results' >/dev/null 2>&1; then
    echo "$S" | jq -r '
      .runs[0].results[]?
      | (.locations[0].physicalLocation // {}) as $l
      | [ .level,
          (.ruleId // "?"),
          (($l.artifactLocation.uri // "?") + ":" + (($l.region.startLine // 0)|tostring)),
          ((.message.text // "") | gsub("\\s+";" ")) ]
      | @tsv' \
    | while IFS=$'\t' read -r level rule loc msg; do
        case "$level" in
          error)   echo "*** HIGH [$rule] $loc — $msg" ;;
          warning) echo "== MED [$rule] $loc — $msg" ;;
          *)       echo "== INFO [$rule] $loc" ;;
        esac
      done
    echo "---- zizmor detail ----"
    zizmor --offline --format plain "$WF" 2>/dev/null || true
    exit 0
  fi
  echo "(zizmor gave no parseable output — using regex fallback)"
fi

# ---- conservative regex fallback (zizmor absent) ----
FILES=$(find "$WF" -type f \( -name '*.yml' -o -name '*.yaml' \) 2>/dev/null)
[ -z "$FILES" ] && { echo "no workflow files"; exit 0; }
# Only ATTACKER FREE-TEXT (.title/.body/head_ref), and only when NOT an env:/concurrency: assignment.
HIT=$(grep -rEn '\$\{\{[^}]*github\.(event\.(issue|pull_request|comment|review|discussion)\.(title|body)|head_ref)[^}]*\}\}' $FILES 2>/dev/null \
      | grep -vE '^[^:]+:[0-9]+:\s*(#|.*(env:|group:|name:))' || true)
if [ -n "$HIT" ]; then
  echo "== fallback: attacker free-text expressions (review whether inside a run: shell step) =="
  echo "$HIT" | sed 's/^/  /'
fi
# pwn-request: privileged trigger + checkout of PR head
for f in $(grep -lE 'pull_request_target|workflow_run' $FILES 2>/dev/null || true); do
  if grep -qE 'actions/checkout' "$f" && grep -qE 'ref:\s*.*(head\.sha|head\.ref|pull_request\.head)' "$f"; then
    echo "*** HIGH [fallback-pwn-request] $f — privileged trigger checks out untrusted PR head"
  fi
done
exit 0
