# rex-review

A code reviewer that optimizes for precision. Findings are hypotheses. A pipeline of cheap stages generates them, and expensive stages kill them. Only verified defects reach the human.

## Pipeline

| Stage | Script | Model | Output |
|---|---|---|---|
| 1. Brief | `bin/rex-brief.sh` | none | `brief.md`: diff, changed symbols, callers, intent, linter output, context cards |
| 2. Lenses | `bin/rex-lens.sh` | cheap (`sonnet`) | `findings.<lens>.json`, one file per lens, schema `schemas/finding.schema.json` |
| 3. Gate | `bin/rex-validate.sh` | none | `candidates.json`. Drops findings with no trigger path, low confidence, or a file outside the diff. Dedups. |
| 4. Adjudicator | `bin/rex-adjudicate.sh` | strong (`opus`) | `verdicts.json`. Default verdict is REJECTED. Optional test reproduction with `--repro`. |
| 5. Report | `bin/rex-report.sh` | none | `report.md`, `surfaced.json`, `rejected.jsonl`, `summary.json` |

`bin/rex-review.sh` runs all five. Each run writes to `runs/<repo>/<timestamp>-<sha>/`. The reviewed commit is checked out in a detached worktree so the models read the exact code under review.

## Quick start

```bash
(install.sh not vendored)                                   # registers the /rex-review skill
bin/rex-review.sh --repo ../stellar-rpc --pr 934
cat runs/stellar-rpc/*/report.md
```

Environment knobs: `REX_LENS_MODEL`, `REX_ADJ_MODEL`, `REX_LENSES`, `REX_MIN_CONF` (gate, default 0.3), `REX_MIN_SEVERITY` (report, default low), `REX_MAX_DIFF_LINES` (default 4000), `REX_LINT_GO` (default 1), `REX_LINT_RUST` (default 0).

## Evals

Build the ground truth from a repo's history, then run the pipeline over it:

```bash
bin/rex-eval-mine.sh --repo ../stellar-rpc --n 20     # evals/stellar-rpc/{clean.tsv,fixes/*.json}
bin/rex-eval.sh --repo ../stellar-rpc --set clean --limit 5 --tag baseline
bin/rex-eval.sh --repo ../stellar-rpc --set fixes --limit 5 --tag baseline
```

- **Clean set**: merged PRs. Every surfaced finding is a false positive. This gives the noise rate.
- **Fix set**: commits whose subject says "fix". The removed lines are blamed to find the introducing commit (SZZ-lite). The pipeline reviews the introducing commit; a hit is a surfaced finding in the same file within ±15 lines of a blamed line.

Results go to `evals/results/<repo>/<timestamp>-<tag>/report.md`. Rerun after any prompt or schema change. Keep the false-positive rate on the clean set under 10% of PRs before you add lenses.

## Context cards

Optional repo knowledge that the brief includes by path match. Put markdown files in `<repo>/.review/context/` or `context/<repo>/` here. `invariants.md`, `bug-patterns.md`, and `architecture.md` are always included. Other cards need a `globs:` list in YAML frontmatter:

```markdown
---
globs: [cmd/stellar-rpc/internal/events/**]
---
Events are keyed by (ledger, tx, op, event) ordinal ...
```

Add a card only when an eval miss shows that the card would have caught the defect.

## Layout

```
bin/          scripts, one per stage plus orchestrator and eval tools
prompts/      lens-<name>.md, adjudicator.md
schemas/      finding.schema.json, verdict.schema.json (passed to claude --json-schema)
evals/        <repo>/clean.tsv, <repo>/fixes/*.json, results/
context/      optional per-repo context cards
runs/         run artifacts (gitignored)
SKILL.md      the /rex-review Claude Code skill
```
