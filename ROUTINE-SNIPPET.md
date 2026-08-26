# Paste this block into the Daily Bounty Digest routine prompt
# (routine: https://claude.ai/code/routines/trig_01XFZRZn8edR6wFM9JeUHJw1 — log in as digiscrypt@gmail.com)

---

**OSS VRP new-repo sweep (auto).** A cron on my VM detects repos newly added to Google's OSS VRP
tier list, runs the CI/supply-chain sweep on them, and publishes the result to:

    https://raw.githubusercontent.com/uwezkhan/oss-vrp-sweep/master/NEW-FLAGS.md

Fetch that file. If its date is today (or since the last digest) AND it contains a "⚠️ FLAGGED"
section, surface it near the TOP of the digest as **"OSS VRP: N new repo(s), M flagged — triage"**,
listing the flagged repo names and their zizmor rule(s) (template-injection / dangerous-triggers /
workflow_run / secrets). If it says "✅ No HIGH flags", include a one-line "OSS VRP: N new repos, clean."
If the file's date is old (no new repos recently), say nothing about OSS VRP.

Do NOT try to triage flags yourself — just surface them so I can ask the assistant to verify
(real-vs-FP + dup-check) before reporting.
