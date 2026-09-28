---
name: address-pr-comments
description: Work through every unresolved review comment on a pull request - verify each reviewer claim against the code, fix the ones that hold (one commit per comment on a fix branch in a worktree, nothing pushed), draft replies in the author's own voice for the ones that don't, and publish a reconciliation artifact that shows, per comment, the quote, the why, the exact diff lines and a copy-pasteable `git cherry-pick -n` command that stages that fix into the user's branch without committing. Use this whenever the user asks to address, go through, triage, reconcile or respond to PR review comments or feedback, "handle the comments on PR N", "see what the reviewers want", or wants a before/after view of review fixes - even if they only mention a PR number or link and the word "comments"/"review".
---

# Address PR comments

The job: turn a PR's open review threads into (a) small, individually applicable fixes and (b) draft replies, then hand the user one page where each comment sits next to the lines that answer it. The user stays in control of what lands: fixes are commits on a side branch, the page gives a stage-only command per comment, and nothing is pushed or posted.

Two failure modes this skill exists to avoid; keep them in mind throughout:

- **Taking a reviewer's claim at face value.** Reviewers are often right, sometimes half-right, occasionally wrong about a detail (a line number, a lint rule, what a tool does). Verify every claim in the code before acting; when the claim is about tool behaviour and a reproduction is cheap (a toy module, a one-line command), reproduce it rather than reason about it. The "why" on the page must state what you checked.
- **Making the user guess which lines fix which comment.** A single commit or a wall of diff is useless to someone re-reading the threads. Attribution has to be explicit: one commit per thread, and per-line highlighting when fixes interleave.

Scripts live next to this file; `<skill>` below is this directory.

## 1. Sync with the PR, not the local checkout

Resolve the PR (number or URL; default to `gh pr view --json number` for the current branch) and fetch its state:

```bash
python3 <skill>/scripts/fetch_threads.py OWNER/REPO N > threads.json        # unresolved threads; a one-line summary goes to stderr
python3 <skill>/scripts/fetch_threads.py OWNER/REPO N --all > threads_all.json   # resolved too, for tone sampling in step 5
```

`pr.head` in that JSON is the truth. Anything the harness or `git status` shows about `origin/*` or the user's `HEAD` can be stale in either direction (another session may have rebased or pushed), so establish three facts yourself:

```bash
git cat-file -t <pr.head>                       # object present locally? if not:
git fetch https://github.com/OWNER/REPO.git <headRef>   # HTTPS: background sessions often cannot use the SSH remote
git rev-parse HEAD                              # the user's actual checkout head -> checkoutHead in the manifest
```

Also note `pr.mergeable`; if the base moved and the PR conflicts, say so in the report — do not rebase unless asked.

Then isolate. Cut the fix branch from exactly what the reviewers saw:

```bash
git worktree add -b pr-<N>-fixes .claude/worktrees/pr-<N>-fixes <pr.head>
```

Prefer this over `EnterWorktree`: that tool cuts its branch from the default branch or the local HEAD, not from `<pr.head>`, and names it itself. If the repo needs prebuilt artifacts to compile (cgo libs, generated code), symlink them from the main checkout rather than rebuilding — the project's CLAUDE.md says what those are. Do not commit the symlink.

Shell hygiene inside a worktree-isolated session: the guard rejects compound commands (`&&` chains with `cd`, heredocs, `cmd | tail; echo $?`). Run one plain command per call, use `go -C <dir>` / `git -C <worktree>` instead of `cd`, and write scratch files with the Write tool.

## 2. Read the PR before the comments

Read the PR description and the full diff (`gh pr diff N`), then each thread's file at `pr.head`. A comment only makes sense against the surrounding code and the PR's intent; reading comments first anchors you to the reviewer's framing. Check memory for earlier sessions on the same PR — decisions recorded there (a thread deliberately left as a reply, a deviation the author accepted) should not be re-litigated; if memory is silent, treat an unaddressed thread as open.

Card numbers are positional: thread `n` is the n-th entry in `threads.json`. Use those numbers everywhere (commit subjects, report, cross-links) so they stay stable across sessions.

Threads that are the PR author's own reviewer notes (first comment by `pr.author`, last comment theirs or a plain acknowledgment) become `resolve` cards. Every other unresolved thread gets a verdict.

## 3. Verify, then decide, one thread at a time

For each thread, reproduce the reviewer's reasoning against the code and record the result in one of these buckets:

| Bucket | When | Output |
|---|---|---|
| `fixed` | The claim holds and the fix is in the PR's scope | one commit |
| `reply` | The claim is wrong, half-right, or the fix belongs elsewhere (scope, follow-up, design debate) | draft reply |
| `done` | Already satisfied on the branch (previous session, another commit) | the satisfying commit + a "done in <sha>" reply |
| `resolve` | Author's own note, or an acknowledged thread with nothing left to do | one-line note |

Things that routinely change the verdict, so check them explicitly:

- **Lint and build constraints.** A suggestion like "drop the json tags" or "add a `go build` preflight" may collide with the linter config (`musttag` + `tagliatelle` force a different shape) or not do what the reviewer thinks (`go build` compiles but never links a non-main package, so a missing native library passes). Run the project's lint on the changed package before calling a fix done — the linter, not the reviewer, has the last word on shape.
- **Line numbers and paths** in the comment may be stale after a rebase; find the code by content.
- **Scope.** A fix PR should not grow a feature. When a reviewer proposes a redesign, evaluate it honestly, say whether it is right, and route it to a follow-up (offer to draft the issue) rather than absorbing it.
- **Deviating from the suggestion** is fine when you can show why (a stronger fix, a lint trap, a semantic the suggestion would lose). Mark it `deviation: true`, explain in the "why", and add a one-line reply so the reviewer sees it was deliberate.

## 4. Fix: one commit per thread on the fix branch

Work in the worktree on `pr-<N>-fixes`. For each `fixed` thread:

1. Make the change. Keep it to what the comment asks plus whatever the linter forces (e.g. extracting a helper when `funlen` trips).
2. Verify with the project's own commands (Makefile, CLAUDE.md): format, build, lint the changed packages, run their tests. Do not commit red.
3. Commit with a subject that names the thread — `pr-<N>: #<k> <short title>` — and a body that says what changed and why, ending with `Addresses: <thread url>`.

When two threads' fixes interleave in the same lines (both edit one function signature or one const block), fix them together in **one commit whose subject lists every thread it carries** (`pr-938: #4 #5 #8 #9 serve-phase teardown`). Splitting those produces cherry-picks that conflict with each other, which defeats the per-comment apply command; the page's `focus` highlighting restores per-comment attribution inside the shared diff.

Do not push the fix branch and do not touch the user's checkout. The branch stays reachable after the worktree is removed, so the apply commands keep working.

## 5. Replies in the author's voice

Draft replies for `reply` threads, "done in <sha>" notes for `done` threads, and one-liners for deviations — in the PR author's tone, not yours. Sample it from their own comments in `threads_all.json`: sentence length, how they open ("Yeah…", "I looked into this…"), how much evidence they cite (CI links, line numbers), how they close ("I'm open to…", "happy to do that in a follow-up"). A structure that reads well: cause → evidence → what you did or won't do → an open door. Never post — the page is where the user reviews and copies them.

## 6. Build and publish the page

Write `verdicts.json` (schema and field notes in `references/manifest.md`), then:

```bash
python3 <skill>/scripts/make_manifest.py threads.json verdicts.json manifest.json   # fails if a thread has no verdict
python3 <skill>/scripts/build_artifact.py manifest.json pr-<N>-review.html
```

Load the `artifact-design` skill (the Artifact tool requires it) but keep the generator's design; only the content varies. Publish with the Artifact tool: title `#<N> <PR title>`, icon `thread`, a one-sentence description.

What each card carries so the reader never has to guess:

- every comment in the thread, attributed and linked (the helper fills this in);
- **Why**: your verdict on the claim, what you checked, what changed, any deviation, and `[#k](#ck)` links to other cards when a commit is shared;
- the commit's diff with old/new line numbers; set `focus` whenever the commit is shared. Set `commit` on `done` cards too — the page shows the diff and, seeing the sha is already in `pr.head`, drops the apply command;
- for applicable fixes, `git cherry-pick -n <sha>` (stages, does not commit) and its undo — both emitted by the generator;
- the draft reply.

The nav carries the apply-all command (`git cherry-pick -n <pr.head>..<fixBranch>`), a note comparing `checkoutHead` to `pr.head`, and the worktree/branch location. Put the verification you ran in `footer`.

## 7. Report and remember

End with a compact table — thread, verdict, resolution, commit — the artifact URL, the worktree path and fix branch, and the apply-all command. Say plainly what was not fixed and why, and whether the user's checkout is at `pr.head`.

Then save a short project memory for this PR: per-thread verdicts, deviations, and anything deliberately left as a reply. The next session on this PR (a re-review, a rebase) starts from that instead of re-deriving it. In cloud sessions memory does not persist; skip this step when `CLAUDE_CODE_REMOTE` is `true`.

## Bundled scripts

- `scripts/fetch_threads.py OWNER/REPO N [--all]` — review threads as JSON (unresolved by default) plus PR head/base/mergeability/author.
- `scripts/make_manifest.py threads.json verdicts.json manifest.json` — merges thread facts with your verdicts; positional numbering; refuses to drop a thread.
- `scripts/build_artifact.py manifest.json out.html` — the reconciliation page; reads diffs from git so the page always matches what cherry-pick stages.
- `references/manifest.md` — verdict fields, statuses, `focus`/`files` attribution, shared commits.
