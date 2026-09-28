---
name: rex-review
description: High-precision code review of a diff or PR. Runs the rex pipeline (deterministic brief → lens hypotheses → mechanical gate → adversarial adjudicator) and presents only verified findings. Use when the user asks for a rex review, a high-precision review, or verified-findings-only review of a PR, branch, or commit range. For a quick conversational PR review, use simple-review.
---

# rex-review

Rex reviews code the way a detective works a case: every finding is a hypothesis, and only the ones that survive verification reach the user.

## Run

The tool lives at `$REX_HOME/bin/`. `REX_HOME` defaults to the directory that contains this SKILL.md (`bin/_lib.sh` derives it from the script location). From inside the target repository:

```bash
REX_HOME="${REX_HOME:-<directory that contains this SKILL.md>}"
"$REX_HOME/bin/rex-review.sh" --repo "$(pwd)" [--pr N | --base REF] [--head REF] [--repro]
```

- No arguments: reviews `origin/HEAD..HEAD`.
- `--pr N`: reviews the PR against its base branch, and includes the PR description in the brief.
- `--base REF --head REF`: reviews an explicit range.
- `--repro`: lets the adjudicator write and run a failing test for critical/high findings. Needs a working build.
- `--lenses correctness`: comma-separated lens names (files in `prompts/lens-*.md`).

Note: the pipeline shells out to `claude -p` and needs `jq` and `rg`. It is not verified in cloud sessions.

The script prints the run directory on its last stdout line. Read these files from it:

- `report.md` — the deliverable. Surfaced findings with trigger path, evidence, and falsifying test.
- `rejected.jsonl` — what the adjudicator killed, and why. Do not show these unless asked.
- `summary.json` — counts and cost.

## Present

1. Read `report.md`.
2. Show each surfaced finding with its `file:line`, the claim, the evidence, and the suggested fix. Keep the adjudicator's verdict label (CONFIRMED or LIKELY) and the severity.
3. If there are no findings, say so in one line. Do not invent style comments to fill the space.
4. If the user asks to post the review, use `gh pr comment` or `gh pr review` with the report content.

## Rules

- Never soften a REJECTED finding into a "consider". It was rejected for a reason.
- Never add findings of your own to the report. If you see one, run the pipeline again with a note, or tell the user it is unverified.
- Runs live under `$REX_HOME/runs/<repo>/`. Leave them; they are eval data.
