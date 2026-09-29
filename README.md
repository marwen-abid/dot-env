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
| cloud-compat | Make a skill, agent, hook, or settings file work in Claude Code cloud sessions. |
| code-review-and-quality | Multi-axis code review of any change before merge. |
| code-simplification | Simplify code for clarity without changing behavior. |
| deslop | Diff-scoped AI-slop cleanup pass for Go code before review. |
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

The cloud environment's setup script clones this repo and copies the config into the VM's `~/.claude`. The repo is public because environment variables are not available to setup scripts, so no token can be used there. The config then applies to every repository the session works on. Verified on the Anthropic-hosted image: user-level `CLAUDE.md`, skills, agents, hooks and the `agent` key all load; `effortLevel` is set by the launcher and ignored; `gh` and `jq` are pre-installed (the install script adds them only if missing); GitHub GraphQL is blocked, REST works.

In the claude.ai environment dialog, set the setup script to:

```bash
set -e
git clone -q https://github.com/marwen-abid/dot-env.git "$HOME/dot-env"
bash "$HOME/dot-env/cloud/install.sh"
```

For a repository with a toolchain profile, add the profile name. For stellar-rpc:

```bash
set -e
git clone -q https://github.com/marwen-abid/dot-env.git "$HOME/dot-env"
bash "$HOME/dot-env/cloud/install.sh" stellar-rpc
```

Also set these in the environment's **Environment variables** field. The environment copies them into every command of the session:

```text
CGO_CFLAGS=-I/root/.zstd/include -I/root/.rocksdb/include
CGO_LDFLAGS=-L/root/.zstd/lib -L/root/.rocksdb/lib
LD_LIBRARY_PATH=/root/.zstd/lib:/root/.rocksdb/lib
GOFLAGS=-tags=grocksdb_clean_link
BASH_DEFAULT_TIMEOUT_MS=600000
```

`BASH_DEFAULT_TIMEOUT_MS` raises the Bash command timeout from 2 to 10 minutes (the maximum), so a cold `go test` or `cargo` build does not go to the background.

A setup script must finish in about 5 minutes, or the environment is not cached. A RocksDB build takes about 20 minutes, so the `stellar-rpc-native` workflow builds libzstd, librocksdb and golangci-lint once and force-pushes the tarball to the orphan `artifacts` branch. Setup downloads it from `raw.githubusercontent.com`. The workflow runs daily and builds only when the stellar-rpc install scripts or the golangci-lint pin change. If no artifact matches, setup builds from source and the environment is not cached; run `gh workflow run stellar-rpc-native.yml` to publish one.

Files:

- `cloud/install.sh`: installs `gh` and `jq` if missing, disables commit signing, sets the commit identity, runs each profile given as an argument, runs `sync.sh`. Always exits 0: a failed setup script stops the session from starting.
- `cloud/profiles/stellar-rpc.sh`: the toolchain that stellar-rpc CI uses. Replaces the image's Go with the `go.mod` version (from `proxy.golang.org`), installs the native artifact (libzstd in `~/.zstd`, librocksdb in `~/.rocksdb`, golangci-lint at the CI pin), and runs `make build-libs` when the checkout exists. Writes the cgo variables to `~/.config/dot-env/stellar-rpc.env`. Logs are in `~/.config/dot-env/logs`.
- `cloud/profiles/stellar-rpc-native.sh`: computes the artifact key and builds the artifact. Used by the workflow, and by setup when no artifact matches.
- `.github/workflows/stellar-rpc-native.yml`: builds and publishes the artifact.
- `cloud/sync.sh`: copies `CLAUDE.md`, `.claude/agents`, `.claude/skills` and `cloud/settings.json` into `~/.claude`. Skills are copied one by one so synced claude.ai skills stay.
- `cloud/settings.json`: `.claude/settings.json` plus a SessionStart hook.
- `cloud/hook-session-start.sh`: `git pull`, re-sync, sets the git commit identity, loads `~/.config/dot-env/*.env` through `CLAUDE_ENV_FILE`, `reloadSkills`. Keeps sessions on the latest commit even when the environment snapshot is a week old.

`cloud/settings.json` is generated from `.claude/settings.json`; regenerate it after editing the source:

```bash
jq --arg cmd '__SDF_DIR__/cloud/hook-session-start.sh' '. + {hooks: {SessionStart: [{matcher: "startup|resume", hooks: [{type: "command", command: $cmd, timeout: 120}]}]}}' .claude/settings.json > cloud/settings.json
```

## Credits

The cloud install approach (setup script clones the dotfiles repo and copies the config into the VM's `~/.claude`, with a SessionStart hook that re-syncs and reloads skills) follows [Leigh McCulloch's dotfiles](https://github.com/leighmcculloch/dotfiles), in particular `claude-cloud/install.sh` and `claude-cloud/sync.sh`.

## Not portable

Plugins, marketplaces, user-scoped MCP servers, and local tools (`pi`, OpenCode, `railway`, `devbox`) stay in `~/.claude` on the machine.
