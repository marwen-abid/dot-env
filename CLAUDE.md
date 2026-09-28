## IMPORTANT DIRECTIONS FOR COMMUNICATION

- Remove all mannered prose.
- For technical document, use ASD-STE100 Simplified Technical English.

## CLOUD SESSIONS (`CLAUDE_CODE_REMOTE=true`)

- GitHub GraphQL is blocked (HTTP 403): `gh pr list|view|diff|create|review`, `gh api graphql`. Use the built-in `mcp__github__*` tools (`pull_request_read`, `pull_request_review_write`, `resolve_review_thread`, `update_pull_request`, `list_pull_requests`) or REST via `gh api repos/{owner}/{repo}/...`.
- Review threads over REST (CCR routes): `GET /repos/{o}/{r}/pulls/{n}/ccr/review_threads` returns `[{resolved, outdated, path, line, comment_ids}]`; comment bodies come from `GET /repos/{o}/{r}/pulls/{n}/comments`; `POST .../pulls/{n}/ccr/comments/{comment_id}/resolve` or `/unresolve`; `PUT|DELETE .../ccr/auto_merge`; `POST .../ccr/ready_for_review`, `.../ccr/convert_to_draft`.
- `gh auth status` fails by design; `gh api` works on repositories attached to the session.
- The session enforces a `Claude-Session:` commit trailer and an attribution footer on GitHub posts; do not fight it.
