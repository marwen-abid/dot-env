---
name: simple-review
description: Review a GitHub pull request or local diff in the current repository. Use when the user asks for /simple-review, a PR review, or concise code-review feedback focused on code quality, bugs, security, and performance. For verified-findings-only review, use rex-review; for a reviewer-facing explainer page, use explain-changeset.
---

# Simple Review

Review the requested pull request or diff with a focus on:

- Code quality and best practices
- Potential bugs or issues
- Security implications
- Performance considerations

Provide detailed feedback using inline-style comments for specific issues, posted in the chat only. Do **not** post comments, reviews, labels, or status updates remotely to GitHub unless the user explicitly asks you to do so.

## Workflow

1. Determine the review target from the user's request.
   - Accept forms like `PR851`, `PR #851`, `#851`, a GitHub PR URL, `current branch`, `staged changes`, or `current repo`.
   - For `PR851` / `#851`, treat the number as a GitHub PR number in the current repository.
2. Inspect repository state first:
   - Run `git status --short`.
   - Run `git remote -v` when reviewing a PR number or URL and a repo must be resolved.
   - Preserve unrelated local changes; do not checkout branches or modify files unless the user explicitly asks.
3. Read the diff.
   - For GitHub PRs, prefer `gh pr diff <number-or-url>` and `gh pr view <number-or-url> --json title,headRefName,baseRefName,author,url`.
   - If useful, save the diff to `/tmp` for repeated reads.
   - Use `gh pr diff --name-only` or `git diff --name-only` to identify changed files.
   - Cloud sessions (`CLAUDE_CODE_REMOTE=true`): `gh pr ...` fails (GraphQL is blocked). Use the built-in GitHub tools, or REST. Get `{owner}/{repo}` from `git remote get-url origin`.
     - Metadata (title, body, base/head refs): `gh api repos/{owner}/{repo}/pulls/{n}`.
     - Diff: `gh api repos/{owner}/{repo}/pulls/{n} -H "Accept: application/vnd.github.v3.diff"`.
     - Changed files: `gh api repos/{owner}/{repo}/pulls/{n}/files --paginate --jq '.[].filename'`.
4. Inspect relevant changed files and surrounding context with `read`; use `rg`/`git grep` to understand related code paths.
5. Run focused validation when reasonable and not too expensive.
   - Prefer package-level tests/lints or targeted commands over full-suite runs.
   - Mention commands run and their results.
6. Produce the review in chat.

## Review style

- Prioritize actionable issues. Avoid nitpicks unless they materially improve maintainability or correctness.
- Prefer concrete comments with file paths and line numbers when possible.
- For each finding, include:
  - Severity or priority when helpful (`High`, `Medium`, `Low`, or `Nit`).
  - File path and approximate line(s).
  - What is wrong or risky.
  - Why it matters.
  - A suggested fix or direction.
- If there are no blocking issues, say so explicitly.
- Include a short "Positive notes" section when appropriate.
- Keep the tone direct, constructive, and concise.

## Suggested output format

```markdown
I reviewed <target> locally only; I did not post anything to GitHub.

Commands run:
- `<command>` — <result>

## Findings

### 1. <short issue title>

**Severity:** <High|Medium|Low|Nit>  
**File:** `<path>`  
**Lines:** <line range>

<inline-style review comment explaining the issue and suggested fix.>

## Positive notes

- <optional positive observation>
```

If the user specifically asks for “inline comments”, provide them as inline-style comments in the chat with file/line anchors; do not use `gh pr review` or GitHub APIs to submit comments.
