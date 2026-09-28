---
name: changelog
description: >
  Add a CHANGELOG entry to the @CHANGELOG.md file.
  Use this skill whenever the user asks to update the changelog, add a changelog entry,
  record a change, or says "changelog". Also use it when the user has finished implementing
  a feature or fix and wants to document it in the changelog before committing.
---

# Changelog Entry Skill

Add well-formatted changelog entries that match the project's existing conventions. The changelog follows [Keep a Changelog](https://keepachangelog.com/) format.

## Workflow

### Step 1: Determine what changed

Run `git diff --staged` to see changes staged for commit. If nothing is staged, fall back to `git diff <base>...HEAD` to see all changes on the current branch compared to the base branch. Detect the base branch with `gh repo view --json defaultBranchRef -q .defaultBranchRef.name`; if that fails, use `develop` if it exists, else `main`.

Read the diff carefully to understand the nature of the changes — is it a new feature, a bug fix, a dependency bump, a refactoring, a security fix, etc.

### Step 2: Determine the PR number

Use the GitHub CLI to find the next PR number:

```bash
gh pr list --state all --limit 1 --json number --jq '.[0].number'
```

Add 1 to the result to get the upcoming PR number. If a PR already exists for the current branch, use that PR's number instead:

```bash
gh pr view --json number --jq '.number'
```

The repo URL is derived from the git remote — typically `https://github.com/<owner>/<repo>/pull/<number>`.

**Cloud sessions (`CLAUDE_CODE_REMOTE=true`):** `gh pr ...` fails (GraphQL is blocked). `gh repo view --json defaultBranchRef` in Step 1 works. Get `{owner}/{repo}` from `git remote get-url origin` and use REST:

```bash
# Latest PR number (add 1 for the upcoming PR)
gh api 'repos/{owner}/{repo}/pulls?state=all&per_page=1' --jq '.[0].number'
# PR for the current branch: number and URL
gh api "repos/{owner}/{repo}/pulls?head={owner}:$(git branch --show-current)&state=all" --jq '.[0] | .number, .html_url'
# Number and URL of a known PR
gh api repos/{owner}/{repo}/pulls/{n} --jq '.number, .html_url'
```

### Step 3: Pick the right section

Match the changes to the appropriate section. Keep a Changelog defines six standard types — the SDP repo convention also uses a custom "Security and Dependencies" variant for dependency bumps. If the CHANGELOG already uses this section, keep it; otherwise use the standard Keep-a-Changelog sections:

| Section | When to use |
|---------|-------------|
| **Added** | New features, new endpoints, new capabilities |
| **Changed** | Modifications to existing behavior, refactors that change interfaces |
| **Deprecated** | Features that will be removed in a future release (still functional, but discouraged) |
| **Fixed** | Bug fixes |
| **Removed** | Features that have been deleted |
| **Security** | Vulnerability patches and security hardening |
| **Security and Dependencies** | Dependency bumps combined with security-related updates (SDP repo convention: only if the CHANGELOG already uses this section — use this instead of plain "Security" when the change is primarily a dependency update) |

If the change spans multiple categories (e.g., a fix that also adds a feature), add entries to each relevant section.

For breaking changes, also add a `### Breaking Changes` or `### Potential Breaking Changes` subsection — look at how the existing changelog handles these for the exact heading style.

### Step 4: Write the entry

Format each entry as:

```
- Description of the change. [#PR_NUMBER](https://github.com/OWNER/REPO/pull/PR_NUMBER)
```

**Writing good descriptions:**
- Start with an action verb (Add, Fix, Update, Remove, Bump, Refactor)
- Be specific about what changed and where — mention endpoint names, component names, or config options
- Keep it to one or two sentences
- Match the tone of existing entries in the file — concise and factual

**Example entries (SDP repo convention):**
```
- Add endpoint for fetch captcha config. [#1052](https://github.com/stellar/stellar-disbursement-platform-backend/pull/1052)
- Fix short linking is not enabled by default. [#1051](https://github.com/stellar/stellar-disbursement-platform-backend/pull/1051)
- Mirror CI checks in Makefile for local development parity. [#1070](https://github.com/stellar/stellar-disbursement-platform-backend/pull/1070)
```

### Step 5: Insert into the changelog

Read the CHANGELOG.md file. Look for the `## [Unreleased]` section near the top.

- **If `[Unreleased]` exists**: Add the entry under the appropriate subsection (Added, Changed, Fixed, etc.). If the subsection doesn't exist yet within Unreleased, create it.
- **If `[Unreleased]` does not exist**: Create a `## [Unreleased]` section after the top-level heading and any preamble, then add the entry.

Use the Edit tool (not Write) to insert the entry — this preserves the rest of the file and makes the change easy to review in the diff.
