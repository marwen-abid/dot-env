---
name: explain-changeset
description: Build a shareable review dossier (an Artifact page) that explains a changeset — a PR, a branch vs its base, a commit range, or the uncommitted working tree — to a reviewer with no codebase context. Slices the final-state diff into logical groups that tell the story, shows each group's key hunks, adds the context the diff can't show, gives an opinion per group, and (optionally) a verdict with severity-labelled findings and build/test/lint verification. Use this whenever the user asks to explain, walk through, summarize, or "help me review" a diff or PR, asks whether a PR is worth merging, wants to onboard another reviewer onto a change, or wants a "what changed and why" page — even if they never say "artifact". Runs as a maestro: the main session directs and judges; `engineer` and `worker` subagents do the legwork.
---

# Explain Changeset

Produce one page a reviewer can read instead of the raw diff and still make a merge decision. The page tells the *story* of the change in its **final state** — never the intermediate commits — and pairs every group of hunks with the context a newcomer lacks and an honest opinion.

## You are the maestro

Your context is the expensive resource; subagent context is cheap. Rules:

- **You decide, subagents dig.** You read the production diff yourself (that is the judgment you cannot delegate), pick the groups, form the opinions, and write the page. Anything that is a sweep — running the build/tests/lint, auditing test files, tracing every caller of a new API, checking an external library's copy-vs-alias behaviour — goes to a subagent with a self-contained prompt.
- **Use the project agents.** Pass `subagent_type: "engineer"` for tasks that need judgment (analysis, opinions) and `subagent_type: "worker"` for pure extraction or reading (the definitions are in `.claude/agents/engineer.md` and `.claude/agents/worker.md`). If those agent types are missing, pass `model: "opus"` explicitly. State the planned dispatch count before launching (three is the normal ceiling for a mid-size PR) and launch them all in one turn so they run concurrently.
- **Subagents get zero shared context.** Write each prompt as if to a contractor who has never seen the repo: absolute paths, the merge-base SHA, where the saved diff files are, what the change claims to do (paste the PR description's core), the exact questions to answer, and the report format. Templates are in `references/subagent-prompts.md`.
- **Reports come back as files, not chat.** Subagent results get truncated in the notification. Ask every subagent to write its full report to `${CLAUDE_JOB_DIR:-$(mktemp -d)}/tmp/<name>.md` (if `CLAUDE_JOB_DIR` is not set, create one scratch dir with `mktemp -d` and use it for all subagents) (or a scratch dir you name) and reply with one line. Read the file with `grep`/`sed` for headings and bullets — never `cat` a 30 KB report into your context.
- **Never paste the full diff into your own context.** Save it to files first (`git diff > …`), read the production diff in per-group slices, and hand the test diff to a subagent.
- **Spot-check before you repeat.** A subagent claim that reaches the page must have been verified by you with one targeted `sed -n` or `grep` — subagents are confident when wrong, and the page carries your name.

## 1. Resolve the changeset

Accept any of these and normalize to `BASE..HEAD` plus a label:

| Input | Resolve |
|---|---|
| PR number / URL | `gh pr view N --json title,body,baseRefName,headRefName,commits,additions,deletions,changedFiles`; `git fetch origin <base>`; `BASE=$(git merge-base HEAD origin/<base>)`. If the PR isn't checked out, `gh pr checkout N` first (or diff `origin/<base>...origin/<head>` without switching). |
| Branch vs base (`main..feature`, or just a branch) | `BASE=$(git merge-base <base> <branch>)`. |
| Commit range / single SHA | Use as given; a single SHA is `SHA^..SHA`. |
| Working tree (no argument, dirty tree) | `git diff HEAD` (staged + unstaged); note there is no description or review history. |

Then save three files in the scratch dir: the full diff, the production-only diff (`':!*_test.*'` and the repo's test-directory conventions), and the test-only diff. Record `BASE`, the stat (`git diff --stat`), and file count — these go in the page header.

Flags: `--no-verdict` skips the verification and audit subagents and drops the verdict section (pure explainer). `--out <path>` overrides the HTML location (default: the scratch dir).

## 2. Understand the changeset before judging it

Read `references/understanding-the-changeset.md` — it is the context-gathering sequence that turns a diff into a story. In short:

1. **Intent first.** PR description, commit subjects, linked issues. Extract: the problem, the claimed fix in one sentence, the numbers if any (before/after), and the author's own stated risks or follow-ups. This becomes the page's opening section almost verbatim.
2. **Prior review.** `gh api repos/O/R/pulls/N/comments --paginate` (inline) and `.../pulls/N/reviews`, `.../issues/N/comments`. Every thread already raised — by a human or a bot — is *excluded* from your findings but *verified* as landed (grep for the fix). Say so on the page: "N prior threads, all addressed; nothing below repeats them."
3. **Tests first, then production.** Tests reveal intent; read their names and what they assert before the code they exercise. Hand the test diff to the test-auditor subagent; skim only the test names yourself.
4. **Production diff, by hand, in slices.** Read it file-group by file-group, not top to bottom. While reading, write down (a) each new concept a reader must hold, (b) each deleted concept, (c) each place where the diff's correctness depends on something *outside* the diff — a library's aliasing behaviour, a lock's scope, a type's field list, an invariant established elsewhere. Item (c) is the "context you can't see" for each group, and it is what a newcomer needs most.
5. **Group.** Slice the change into 4–8 groups that read as a narrative, ordered from the lowest layer up (storage → plumbing → consumer → contract change), or in dependency order. A group is a *mechanism*, not a file — one mechanism may span three files, one file may hold two mechanisms. Name each group with a verb phrase that says what the code now does ("The hot tier lends a decoded ledger"), not a noun ("hot_store.go changes").

## 3. Dispatch the subagent work

Launch in one turn, on `engineer` for tasks that need judgment (analysis, opinions) and on `worker` for pure extraction or reading. Default set when the verdict is on:

- **verifier** — build, vet, `go test`/equivalent on touched packages, race detector where relevant, a flakiness probe on the new tests (`-count=5`), lint full-tree *and* `--new-from-rev=BASE`, changelog check, grep for dangling references to deleted symbols. Output: pass/fail per step with verbatim failure output.
- **test-auditor** — for each claimed behaviour, name the test that pins it and whether it actually would fail on regression; find tests weakened to pass, sleeps, GC/pool-identity dependence, brittle thresholds, duplicated helpers, oversized files, deleted coverage without replacement.
- **risk-auditor** — the change-specific adversary. Write its questions from your step-4 notes: the (c) items are its hunt list. Require it to CONFIRM with `file:line` evidence or DISCARD, and to list discarded candidates so you know what was covered.

With `--no-verdict`, dispatch at most one **context-scout** (callers of new APIs, what a deleted symbol used to do, library behaviour you need to explain) — or none.

While they run, keep reading the production diff and drafting group notes. Don't poll; results arrive as notifications.

## 4. Write the page

Load the `artifact-design` skill, then start from `assets/template.html` and follow `references/artifact-spec.md` for the structure, the per-group rhythm (Why → Diff → Context you can't see → My take), the diff-rendering rules, and the severity vocabulary. Non-negotiables the spec explains:

- Written for a reader who has never opened the repo: one new term per sentence, defined where it first appears; concrete thing before its label; mechanism → flaw → cost. Codebase vocabulary (envelope, window, stamp, tier, sentinel…) is jargon to this reader — define it once in The story or use the plain phrase. The spec's "Write for the reader who has never opened the repo" section has the rules and the counter-example.
- Final state only. If a hunk changed twice across the PR's commits, show where it landed.
- Show the *key* hunks, trimmed with `… n lines unchanged …` markers, not every line. A reader who wants everything has the PR.
- "Context you can't see" states facts you verified (a library copies, a lock guards only lifecycle, an interface has exactly N implementors), with enough specificity that the reader could check them.
- "My take" is an opinion with a reason, and it says when the code is right. Praise that is specific is information; hedged praise is noise.
- Findings carry severity labels (Required / Optional / Nit / FYI, plus Critical when warranted) and each has a concrete fix.
- The verdict answers the reviewer's actual question — merge, merge-after-fixes, or not yet — and "Is it worth including?" in a paragraph.

Publish with the Artifact tool (`icon` on first publish; redeploy the same path for fixes). Then look at it as the reader would: open the diff blocks in your mind — the classic bug is double-spaced diff lines from preserved newlines between block spans (the template already sets `white-space: normal` on the container; keep it).

## 5. Report in chat

Lead with the link, then the verdict in one line, then the Required findings as a numbered list (one line each), then a one-line pointer that everything else is in the page. Never post to GitHub unless asked.

## Cost discipline

- Diff ≤ ~300 changed lines: skip the test-auditor, fold its questions into the risk-auditor.
- Diff > ~1,500 lines: the page's first finding is "split this"; still group and explain, but cap groups at 8 and say which files you did not read in detail.
- Re-use: if this session already reviewed the change, do not re-dispatch — write the page from what you already verified.
- The verifier is the only subagent that must run to completion; if an auditor stalls past ~15 minutes, ask it for a partial file and proceed.
