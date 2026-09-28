# Fix patterns

Each pattern keeps the local behavior and adds the cloud path.

## Gate on the session type

```markdown
Cloud sessions (`CLAUDE_CODE_REMOTE=true`): <alternative>. Locally: unchanged.
```

In scripts: `if [ "${CLAUDE_CODE_REMOTE:-}" = "true" ]; then ...; fi`. In Python:
`os.environ.get("CLAUDE_CODE_REMOTE") == "true"`, plus a fallback when the local path
fails with a 403 that mentions GraphQL.

## gh: PR metadata, diff, files, lookup

| Local | Cloud (REST) |
|---|---|
| `gh pr view N --json title,body,baseRefName,headRefName` | `gh api repos/{o}/{r}/pulls/N` |
| `gh pr diff N` | `gh api repos/{o}/{r}/pulls/N -H "Accept: application/vnd.github.v3.diff"` |
| `gh pr diff N --name-only` | `gh api repos/{o}/{r}/pulls/N/files --paginate --jq '.[].filename'` |
| `gh pr view --json number` (current branch) | `gh api "repos/{o}/{r}/pulls?head={o}:$(git branch --show-current)&state=all" --jq '.[0].number'` |
| `gh pr list --limit 1` | `gh api 'repos/{o}/{r}/pulls?state=all&per_page=1'` |
| `gh api graphql` review threads | `gh api repos/{o}/{r}/pulls/N/ccr/review_threads` + `gh api repos/{o}/{r}/pulls/N/comments --paginate` |
| resolve thread | `gh api -X POST repos/{o}/{r}/pulls/N/ccr/comments/{comment_id}/resolve` |
| `gh pr create` | built-in `create_pull_request` tool, or the session's Create PR button |
| `gh pr review`, comments | built-in `pull_request_review_write`, `add_issue_comment`, `add_reply_to_pull_request_comment` |
| `gh repo view --json defaultBranchRef` | works as is (REST) |

Derive `{o}/{r}` from `git remote get-url origin`. Never use `gh auth status` as a check.

Python REST thread dump, shape-compatible with the GraphQL one: match `comment_ids`
from `ccr/review_threads` against `id` in `pulls/N/comments`, sort by `created_at`,
use the first comment's id as the thread id (GraphQL node ids are unavailable), map
`resolved`→`isResolved`, `outdated`→`isOutdated`, `user.login`→`author`,
`html_url`→`url`. `--paginate` may emit several JSON documents; join them.

## Plugin tool names → connector names

```
mcp__plugin_atlassian_atlassian__searchJiraIssuesUsingJql
→ mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql
```

Add: "If the session has no `<tool>` tool, stop and tell the user; the connector does
not expose it."

## Local CLIs

`acli` (Jira) → Atlassian connector JQL:
```
mcp__claude_ai_Atlassian__searchJiraIssuesUsingJql cloudId=<id> jql="project = X AND sprint = 'Y' AND statusCategory = Done"
```
follow `nextPageToken`. Keep `acli` as a one-sentence local fallback.

Optional CLI (`openapi`, linters):
```markdown
Check `command -v openapi`. If missing, skip the CLI validation steps, validate by
reading the YAML directly, and tell the user which steps were skipped.
```

Extension (`gh stack`): bootstrap `gh extension list | grep -q gh-stack || gh extension install github/gh-stack`, and note that the extension itself needs GraphQL, so it stays LOCAL-ONLY.

Unavailable by nature (`pi`, `opencode`, Copilot OAuth, `railway` login, `devbox`, local Postgres, SSO): LOCAL-ONLY. Do not add install steps for tools that need interactive auth.

## Paths

| Before | After |
|---|---|
| `~/.claude/skills/x/config.json` | "`config.json` next to this SKILL.md" |
| `~/.claude/skills/x/bin/tool.sh` | `X_HOME="${X_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)}"; "$X_HOME/bin/tool.sh"` |
| `~/.claude/agents/grunt.md` | `.claude/agents/<project agent>.md` |
| `$CLAUDE_JOB_DIR/report.md` | `${CLAUDE_JOB_DIR:-$(mktemp -d)}/report.md` |
| `scripts/x.sh` from cwd | `$CLAUDE_PROJECT_DIR/scripts/x.sh` (hooks) |

## Agents named in skills

Replace user-only agent names with the repo's agents, split by what the task needs
(judgment vs extraction), and keep `model: "<alias>"` as the fallback when the agent
type is missing. Remove claims about which model "every subagent" runs on; the agent
files decide that.

## Persistence

Writes to the skill directory, `memory:` scopes, "save to project memory": add "does
not persist in cloud sessions; skip when `CLAUDE_CODE_REMOTE` is `true`", or move the
value into a committed file.

## Hooks

- Repo `.claude/settings.json` hooks load in single-repo sessions only.
- Hooks run in both places; gate cloud-only steps on `CLAUDE_CODE_REMOTE`.
- SessionStart `command` hooks are cancelled after 600 s unless `timeout` is set.
- Hook command paths must be absolute or `$CLAUDE_PROJECT_DIR`-relative; a dotfiles
  sync substitutes a placeholder at copy time.
- A SessionStart hook may return `reloadSkills: true` and `additionalContext`.

## Settings keys

Portable: `agent`, `model`, `outputStyle`, `alwaysThinkingEnabled`, `autoCompactEnabled`,
`attribution`, `permissions`, `hooks`, `env` (non-transport keys).
Ignored or harmful in cloud: `effortLevel` (launcher wins), `enabledPlugins`,
`extraKnownMarketplaces`, `statusLine` with a local path, `env.PHOENIX_*`/localhost
endpoints, `NODE_EXTRA_CA_CERTS`, mTLS keys, `skillOverrides` for skills not present.

## Secrets and internal identifiers

Tokens: never commit. Emails, Slack user IDs, canvas IDs, Jira cloudIds, team UUIDs:
acceptable in a private repo, not in a public one. If the delivery route requires a
public repo, move those skills to a private repo or strip the identifiers into a file
the user provides at runtime.
