# Probing a cloud session

Use a scratch repository (any repo without a committed `.claude/`) so project-scope
config does not mask the result. Set the permission mode to `auto` or `dontAsk`.

## Setup-script probe

Paste as the environment's setup script. It always exits 0 and records to `$HOME`
because `/tmp` does not survive and output is shown only on failure.

```bash
exec > "$HOME/setup.log" 2>&1
echo "RAN AT $(date -u) as $(id -un) shell=$0 bash=${BASH_VERSION:-none}"
echo "VAR: ${MY_VAR:+set}${MY_VAR:-UNSET}"
which gh jq rg claude python3 node go cargo
<the commands under test>
exit 0
```

Then in the session: `Run: cat ~/setup.log`.

## Session probe

```
Run this as one Bash command and paste the raw output:
id -un; echo HOME=$HOME SHELL=$SHELL REMOTE=$CLAUDE_CODE_REMOTE; ls -la ~/.claude ~/.claude/skills ~/.claude/agents; cat ~/.claude/settings.json; which gh jq rg; gh api repos/{owner}/{repo} -q .full_name; gh api graphql -f query='{viewer{login}}' 2>&1 | head -2
Then:
1. Which agent are you running as and which subagents can you spawn?
2. Run the skill under test on <input> and report every command that failed.
3. Report the additionalContext line the SessionStart hook injected, if any.
4. List the built-in GitHub tools available (names only).
```

## Marker technique

To prove a piece of config loaded, give it a unique word and ask for it: a CLAUDE.md
line "when asked for the probe word answer PLATYPUS", a skill that replies ECHIDNA, an
agent that prefixes WOMBAT, a hook whose `additionalContext` is NUMBAT. Each word that
comes back proves that layer loaded.

## Reading results

- `~/.claude-snapshot` copied at setup vs `~/.claude` in session: `diff -r` shows what
  the runtime adds. Additions only means your files survive.
- A checklist without a setup-script step means the script did not run: wrong
  environment selected, or the edit was not saved.
- `gh auth status` failing is normal; test `gh api repos/...` instead.
