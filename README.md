# OSS VRP CI/supply-chain sweep

Clone one repo → audit → **FLAG** (keep for review) or **clean** (delete) → next.
Scope: what OSS VRP actually pays a solo researcher for — leaked secrets + insecure CI/CD.
NOT memory-safety in fuzzed C/C++ libs (OSS-Fuzz owns that).

## Run (on the VM)
```bash
bash setup.sh            # one-time toolchain install; then: source ~/.bashrc
bash sweep.sh            # full list (repos.txt), priority A first is up to you to reorder
ONE=google/osv-scanner bash sweep.sh    # single repo
KEEP=1 bash sweep.sh     # never delete clones (debugging the loop)
```
Outputs:
- `reports/_master.md`  — one verdict row per repo (secrets / gha / deps / verdict)
- `reports/<name>.*`    — raw tool output (trufflehog/gitleaks/gha/osv json+txt)
- `FLAGGED/`            — copies of flagged repos' reports + `*.location.txt` (clone kept on disk)

## What raises a FLAG (loop keeps the clone, stops deleting)
- **VERIFIED secret** (trufflehog --only-verified) → highest signal, almost always real.
- **GHA HIGH**: `pull_request_target`/`workflow_run` that checks out untrusted PR/head code,
  OR untrusted `${{ github.event.* }}` / `github.head_ref` interpolated into a `run:` step.
- gitleaks history hits are recorded but NOT auto-flagged (noisy) — triage in the report.

## Before reporting ANY flag (hard rules)
1. **DUP-SWEEP FIRST** (your standing rule). Check the repo's GitHub Security advisories,
   closed issues/PRs, and Google OSS VRP disclosures. gemini-cli chained_e2e was a confirmed dup —
   don't re-file a known class.
2. **Verify manually.** A HIGH from the analyzer is a *candidate*, not a bug. Confirm the untrusted
   input truly reaches a dangerous sink AND that the trigger is reachable on the public repo.
   For secrets: confirm the credential is live and in-scope (not a test/expired/example value).
3. **Impact.** OSS VRP wants real compromise (secret exfil, code exec in CI with repo write / publish
   rights). A cosmetic unpinned-action note alone is not payable.
4. Submit at https://bughunters.google.com/ under Google OSS VRP. One issue per report; clear PoC.

## Caveats (honest)
- Priority-B libraries: this sweep only covers their secrets+CI. It will legitimately find nothing
  in their C++ — that's expected, not a miss. Don't read "clean" as "no vulns", read it as
  "no CI/secret issues".
- The analyzer is regex-based: false negatives exist (obfuscated expr, composite actions,
  reusable workflows via `workflow_call`). Treat a clean GHA result as "no obvious pattern", and
  hand-review the priority-A repos' workflows even when clean.
