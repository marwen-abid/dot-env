# dot-env

Portable Claude Code configuration. Cloud sessions load only what is committed in a repository, so this repo holds the parts of `~/.claude` that must travel.

## Layout

- `CLAUDE.md`: communication rules.
- `.claude/settings.json`: main agent, model, effort, permissions, env.
- `.claude/agents/`: `maestro` (main session), `engineer`, `worker`.
- `.claude/skills/`: the skills listed in the glossary below.
- `cloud/`: setup for Claude Code cloud environments.

Skills that carry internal identifiers (sprint and standup posting, Jira ticket creation) are kept out of this public repo.

## Agents

| Agent | Model | Effort | Role |
|---|---|---|---|
| `maestro` | Opus 5.5 | high | Main session. Architects, decides, reviews, delegates. |
| `engineer` | Opus 5.5 | medium | Senior developer. Implements from a specification. |
| `worker` | Sonnet 5.5 | high | Well-specified work: search, read, sweep, run, verify. |

## Skills

| Skill | Description |
|---|---|
| address-pr-comments | Verify, fix, or reply to each unresolved PR review comment; publish reconciliation artifact. |
| changelog | Add an entry to CHANGELOG.md for the current change. |
| code-review-and-quality | Multi-axis code review of any change before merge. |
| code-simplification | Simplify code for clarity without changing behavior. |
| doc-comment-cleanup | Rewrite doc comments for first-time readers; strip defensive and historical framing. |
| explain-changeset | Build a shareable Artifact dossier that explains a PR or diff to reviewers. |
| gh-stack | Manage stacked branches and dependent PRs with the gh-stack GitHub CLI extension. |
| grill-with-docs | Challenge a plan against the domain model; update CONTEXT.md and ADRs inline. |
| interview-me | One-question-at-a-time interview to find the user's real intent. |
| openapi-writer | Write, edit, review and validate OpenAPI specifications. |
| readme | Generate or update a comprehensive README.md for a project. |
| rex-review | High-precision code review of a diff or PR; presents only verified findings. |
| security-and-hardening | Harden code that handles untrusted input, auth, secrets, or personal data. |
| simple-review | Concise review of a GitHub PR or local diff. |
| spec-drift-analysis | Verify an OpenAPI spec against reference documents (such as SEPs) to detect drift. |

Cloud caveats: GitHub GraphQL is blocked in cloud sessions, so `gh pr ...` subcommands, `address-pr-comments` (GraphQL thread fetch), and `gh-stack` do not work there; `gh api` REST calls and the built-in GitHub tools do. `gh-stack` installs its extension at first use (unverified through the GitHub proxy). `openapi-writer` and `spec-drift-analysis` skip CLI validation when the `openapi` CLI is absent. `rex-review` shells out to `claude -p` and needs `jq` and `rg` (unverified in cloud).

## Use in a repository

Copy or symlink `CLAUDE.md` and `.claude/` into the target repository and commit them. Cloud sessions read them from the clone.

## Use in Claude Code cloud sessions (any repository)

The cloud environment's setup script clones this repo and copies the config into the VM's `~/.claude`. The repo is public because environment variables are not available to setup scripts, so no token can be used there. The config then applies to every repository the session works on. Verified on the Anthropic-hosted image: user-level `CLAUDE.md`, skills, agents, hooks and the `agent` key all load; `effortLevel` is set by the launcher and ignored; `gh` is not pre-installed (the install script adds it); GitHub GraphQL is blocked, REST works.

In the claude.ai environment dialog, set the setup script to:

```bash
set -e
git clone -q https://github.com/marwen-abid/dot-env.git "$HOME/dot-env"
bash "$HOME/dot-env/cloud/install.sh"
```

Files:

- `cloud/install.sh`: installs `gh`, disables commit signing, runs `sync.sh`.
- `cloud/sync.sh`: copies `CLAUDE.md`, `.claude/agents`, `.claude/skills` and `cloud/settings.json` into `~/.claude`. Skills are copied one by one so synced claude.ai skills stay.
- `cloud/settings.json`: `.claude/settings.json` plus a SessionStart hook.
- `cloud/hook-session-start.sh`: `git pull`, re-sync, `reloadSkills`. Keeps sessions on the latest commit even when the environment snapshot is a week old.

`cloud/settings.json` is generated from `.claude/settings.json`; regenerate it after editing the source:

```bash
jq --arg cmd '__SDF_DIR__/cloud/hook-session-start.sh' '. + {hooks: {SessionStart: [{matcher: "startup|resume", hooks: [{type: "command", command: $cmd, timeout: 120}]}]}}' .claude/settings.json > cloud/settings.json
```

## Credits

The cloud install approach (setup script clones the dotfiles repo and copies the config into the VM's `~/.claude`, with a SessionStart hook that re-syncs and reloads skills) follows [Leigh McCulloch's dotfiles](https://github.com/leighmcculloch/dotfiles), in particular `claude-cloud/install.sh` and `claude-cloud/sync.sh`.

## Not portable

Plugins, marketplaces, user-scoped MCP servers, and local tools (`pi`, OpenCode, `railway`, `devbox`) stay in `~/.claude` on the machine.
