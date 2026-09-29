# Verified cloud-session facts

Established on the Anthropic-hosted image, Claude Code 2.1.284, 2026-09-28. Entries
marked (docs) come from code.claude.com/docs; entries marked (probe) from a live
session and override the docs where they differ.

## VM

- User `root`, `HOME=/root`, shell `/bin/bash`, Ubuntu noble. (probe)
- Pre-installed: `git`, `jq`, `rg`, `python3`, `node` 22 with `claude`, common
  toolchains (Go, Rust, Java 21, etc. per docs). Not installed: `gh`. (probe)
- `apt-get install -y gh` works from the image's cached lists. `apt-get update` fails:
  third-party PPAs in the image return 403 through the Trusted network. Install first,
  update only as a fallback with errors ignored. (probe)
- `CLAUDE_CODE_REMOTE=true`, `CLAUDE_CODE_REMOTE_SESSION_ID=cse_...` in sessions. (probe, docs)
- Session effort is set by the launcher (`xhigh` observed); `effortLevel` in any
  settings file is ignored. (probe)
- Permission mode comes from the session UI, not from settings. (docs)
- Slash commands that open pickers do not work; pass values as arguments. (docs)

## Setup script and snapshot

- Runs once per environment, before Claude Code, as bash; output is shown only when
  it exits non-zero. On success the filesystem is snapshotted and reused for ~7 days;
  it is rebuilt when the script or allowed hosts change. Resuming a session never
  re-runs it. (docs, probe)
- Environment variables are NOT available to the setup script; they are copied into
  the session at startup. Secrets therefore cannot be used before launch. (probe)
- `/tmp` written by the setup script is not present in the session; `$HOME` is. (probe)
- Budget ~5 minutes or the snapshot is not cached. (docs)

## What loads

| Item | Loads? | Note |
|---|---|---|
| Repo `CLAUDE.md`, `.claude/settings.json`, `.claude/{skills,agents,commands,rules}`, `.mcp.json` | Yes | Single-repo sessions only for settings and `.mcp.json` |
| VM `~/.claude/{CLAUDE.md,skills,agents,settings.json}` written by the setup script | Yes | Hooks run; `agent` key applies to the main session; `reloadSkills` works (probe) |
| Runtime additions to `~/.claude` | Added, nothing overwritten | `stop-hook-git-check.sh`, `stop-hook-reply-gate.py`, `user-prompt-submit-reply-reminder.py`, `launcher-settings.json`, `skills/synced/` (account skills), `skills/session-start-hook/` (probe) |
| Plugins, marketplaces (`enabledPlugins`, even in the repo) | No | Vendor the skill files instead |
| User-scoped MCP servers (`~/.claude.json`) | No | Use project `.mcp.json` or claude.ai connectors |
| Laptop `~/.claude` | No | Never synced |
| `env` transport keys (`NODE_EXTRA_CA_CERTS`, mTLS) | No | Ignored |
| API keys for services | Pro/Max: API credentials (proxy-attached). Team/Enterprise: plain env vars, readable by every user of the environment | |

## Network and GitHub

- Levels: None, Trusted (package registries, GitHub, cloud SDKs), Custom (allowlist), Open. Anthropic API, GitHub proxy, and MCP connector traffic bypass the level. (docs)
- All GitHub traffic goes through Anthropic's proxy, which injects credentials only for repositories attached to the session. `GH_TOKEN` reads as `proxy-injected`. (docs, probe)
- Cloning an unattached private repo fails (`Invalid username or token`) even with a token in the URL from the setup script, because no variable is available there. Public repos clone. (probe)
- GitHub GraphQL is blocked: HTTP 403 `GitHub GraphQL is not available from Claude Code sessions`. Broken: `gh pr list|view|diff|create|review|checks`, `gh api graphql`, `gh stack`. Working: `gh api repos/{owner}/{repo}/...` REST, git push/pull on attached repos. `gh auth status` fails by design. (probe)
- CCR REST routes (cloud only): `GET /repos/{o}/{r}/pulls/{n}/ccr/review_threads` → `[{resolved, outdated, path, line, comment_ids}]`; `POST .../ccr/comments/{comment_id}/resolve|unresolve`; `PUT|DELETE .../ccr/auto_merge`; `POST .../ccr/ready_for_review`, `.../ccr/convert_to_draft`. Comment bodies via standard `GET /repos/{o}/{r}/pulls/{n}/comments`. (probe)
- Built-in `mcp__github__*` tools (59) use GraphQL server-side where it is not blocked: `pull_request_read`, `pull_request_review_write`, `resolve_review_thread`, `add_reply_to_pull_request_comment`, `update_pull_request`, `list_pull_requests`, `create_pull_request`, `merge_pull_request`, actions, search. `Claude_Code_Remote` server: `add_repo`, `check_repo_access`, `list_repos`, `subscribe_pr_activity`. (probe)
- Commits get a `Claude-Session:` trailer and PR bodies a session link unless settings set `attribution.sessionUrl: false`. (docs)
- Push scope: the docs say `git push` works only on the session's working branch. A restack pushed several branches (`bench-query/02-*`, `03-*` on a fork) from one session on 2026-09-29. Trust the probe; re-check if a push to another branch fails. (docs, probe)
- Setup script: must finish in about 5 minutes or the environment is not cached (cache lasts about 7 days), and a non-zero exit stops the session from starting. Commands: 2-minute default timeout, 10-minute maximum (`BASH_DEFAULT_TIMEOUT_MS`, `BASH_MAX_TIMEOUT_MS`). VM: Ubuntu 24.04 x86_64, 4 vCPU, 16 GB RAM, 30 GB disk; `gh`, `jq`, `cmake`, `ninja`, GCC pre-installed. (docs)
- GitHub release-asset and archive downloads reach only repositories attached to the session (docs); `git clone` of a public repo and `raw.githubusercontent.com` files work. (docs, probe)
- claude.ai connectors (Slack, Atlassian, Gmail, ...) work as `mcp__claude_ai_<Name>__*` through Anthropic's servers; no allowlist entry needed; tokens stay server-side; the session can idle out while waiting for a connector approval. The Atlassian connector exposes read tools; ticket creation is not confirmed. (docs, probe)
- Interactive auth (SSO, device flow, `acli` login, Copilot OAuth) is impossible. (docs)

## Delivery

Repo route: commit `CLAUDE.md` and `.claude/` into the target repository. Hooks and
`.mcp.json` load only in single-repo sessions.

Dotfiles route (verified with github.com/marwen-abid/dot-env, modeled on
github.com/leighmcculloch/dotfiles):

```bash
# environment setup script
set -e
git clone -q https://github.com/<owner>/<dotfiles>.git "$HOME/<dotfiles>"
bash "$HOME/<dotfiles>/cloud/install.sh"
```

`install.sh` installs `gh`, sets `commit.gpgsign false`, runs `sync.sh`. `sync.sh`
copies `CLAUDE.md`, agents, skills (one directory at a time, so `skills/synced/` is
kept) and a settings file whose SessionStart hook has an absolute path substituted at
copy time. The hook runs `git pull --ff-only`, `sync.sh`, then prints
`{"hookSpecificOutput":{"hookEventName":"SessionStart","reloadSkills":true,"additionalContext":"..."}}`.
Skills reload this way; the `agent` key, agent files and CLAUDE.md must already be on
disk at launch, so they must come from the snapshot, not the hook.
