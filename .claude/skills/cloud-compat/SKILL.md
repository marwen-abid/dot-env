---
name: cloud-compat
description: >
  Make a Claude Code skill, agent, hook, or settings file work in Claude Code cloud
  sessions (claude.ai/code, Claude Code on the web, "CCC", cloud environments, remote
  sessions). Use it whenever the user wants to port, migrate, assess, triage, or fix
  configuration for cloud use, asks why a skill or command fails in a cloud session,
  wants a setup script or SessionStart hook for a cloud environment, or asks what from
  ~/.claude carries over to the cloud. Also use it when reviewing a skill that shells out
  to local tools (gh, acli, pi, opencode, railway, psql) and the user mentions cloud.
---

Cloud sessions run on a fresh Linux VM with only the repository clone, an Anthropic
proxy for GitHub and MCP connectors, and whatever a setup script installs. Most
portability failures come from five assumptions that hold on a laptop and not there:
a local binary exists, a path under `~/.claude` or `/Users/...` exists, a plugin or
user-scoped MCP tool exists, a write persists, or GitHub GraphQL is reachable.

`references/cloud-facts.md` holds the verified facts about the VM, the network, and
what loads. Read it before assessing anything; do not rely on memory of how cloud
sessions work, several of the facts contradict the docs and were established by
probing a live session.

## 1. Assess

Read the skill's `SKILL.md` and every file it references (scripts, references,
templates). For agents read the frontmatter and body. For settings read every key.
Grep the whole directory for each of these and record every hit as `file:line`:

- Local binaries: `pi`, `opencode`, `acli`, `railway`, `devbox`, `nsc`, `psql`,
  `openapi`, `gh extension`, `brew`, `soffice`, anything not in the pre-installed list.
- Paths: `~/.claude`, `/Users/`, `$HOME/.claude`, `~/.agents`, `localhost`, `127.0.0.1`.
- Tool names: `mcp__plugin_*` (plugins do not install in cloud), user-scoped MCP
  servers, agent names that exist only in the user's `~/.claude/agents`.
- GitHub: `gh pr`, `gh api graphql`, `gh auth status`, `gh extension`, GraphQL queries.
- Persistence: writes to the skill directory, `memory` fields, "save to project memory".
- Secrets and internal identifiers: tokens, emails, Slack or Jira IDs, hostnames.
- Interactive auth: SSO, OAuth device flows, `brew install`, `sudo` prompts.

Give one verdict per item:

| Verdict | Meaning |
|---|---|
| PORTABLE | Works as is. |
| NEEDS-EDITS | Works after the fixes you list. |
| LOCAL-ONLY | Depends on a local tool or credential that cannot exist in cloud. Keep it out of the cloud config. |
| DROP | Vendored copy of something the platform already provides, eval workspace, sync cache, or unattended installer. |

Report in this shape before editing, so the user can veto:

```
### <name>
purpose: <one line>
deps: <hits with file:line>
secrets: <hits or none>
verdict: PORTABLE | NEEDS-EDITS (<what>) | LOCAL-ONLY (<why>) | DROP (<why>)
```

## 2. Edit

Apply the smallest edit that makes the cloud path work and leaves the local path
unchanged. `references/fix-patterns.md` has a before/after for each pattern. The
recurring ones:

- Gate cloud behavior on `CLAUDE_CODE_REMOTE=true`; never on hostname or user.
- Replace `gh pr ...` and `gh api graphql` with `gh api repos/{owner}/{repo}/...` REST
  or the built-in `mcp__github__*` tools. Review threads use the CCR routes.
- Replace plugin tool names `mcp__plugin_<x>__<tool>` with the claude.ai connector
  names `mcp__claude_ai_<Name>__<tool>`, and say what to do when the connector lacks
  the tool.
- Replace `~/.claude/skills/<name>/...` with "next to this SKILL.md", `$CLAUDE_PROJECT_DIR`,
  or a path derived from the script's own location.
- Make optional CLIs optional: `command -v x || { note skipped steps; fallback }`.
- Replace references to user-only agents with the project agents that exist in the
  repo, and keep a `model:` fallback.
- Give scratch paths a fallback: `${CLAUDE_JOB_DIR:-$(mktemp -d)}`.
- State that writes to the skill directory and to memory do not persist; skip them
  when `CLAUDE_CODE_REMOTE` is `true`.

Strip `.DS_Store`, `evals/`, `*-workspace/`, `runs/`, `synced/`, logs, drafts. Copy the
target of a symlink, never the symlink. Keep frontmatter valid: `---` on line 1, `name`
and `description` present.

## 3. Verify

Locally: `claude plugin validate <skills dir>`; `find <dir> -type l` is empty;
`grep -rn '~/.claude\|/Users/\|mcp__plugin\|gh pr\|graphql' <dir>` shows only hits with
a cloud alternative beside them; scripts pass `bash -n` or `python3 -m py_compile`.

In cloud: run the probe in `references/probe.md`. One session answers what loads, what
the runtime adds to `~/.claude`, and whether the skill's commands work. A skill is
verified only after this, not after the local checks.

## Delivering config to cloud

Two routes, both in `references/cloud-facts.md` under "Delivery":

- Commit `.claude/` and `CLAUDE.md` in the target repository (single-repo sessions only).
- A public dotfiles repo cloned by the environment's setup script into the VM's
  `~/.claude`, refreshed by a SessionStart hook that pulls and returns
  `reloadSkills: true`. Applies to every repository. Must be public: environment
  variables are not available to setup scripts, so no token can be used there.

Say plainly what you could not verify. Cloud behavior changes; when a fact in the
references disagrees with a live session, trust the session and update the reference.
