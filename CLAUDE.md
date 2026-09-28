## IMPORTANT DIRECTIONS FOR COMMUNICATION

- Remove all mannered prose.
- For technical document, use ASD-STE100 Simplified Technical English.

## CLOUD SESSIONS (`CLAUDE_CODE_REMOTE=true`)

- GitHub GraphQL is blocked. `gh pr list|view|create|review` and `gh api graphql` fail with HTTP 403. Use `gh api repos/{owner}/{repo}/...` (REST) or the built-in GitHub tools. Review-thread, resolve, auto-merge, and draft/ready operations have REST routes under `/repos/{owner}/{repo}/pulls/{n}/ccr/...`; the 403 message lists them.
- `gh auth status` fails by design; `gh api` on repositories attached to the session works.
