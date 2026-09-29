## IMPORTANT DIRECTIONS FOR COMMUNICATION

- Remove all mannered prose.
- For technical document, use ASD-STE100 Simplified Technical English.

## CLOUD SESSIONS (`CLAUDE_CODE_REMOTE=true`)

- GitHub GraphQL is blocked (HTTP 403): `gh pr list|view|diff|create|review`, `gh api graphql`. Use the built-in `mcp__github__*` tools (`pull_request_read`, `pull_request_review_write`, `resolve_review_thread`, `update_pull_request`, `list_pull_requests`) or REST via `gh api repos/{owner}/{repo}/...`.
- Review threads over REST (CCR routes): `GET /repos/{o}/{r}/pulls/{n}/ccr/review_threads` returns `[{resolved, outdated, path, line, comment_ids}]`; comment bodies come from `GET /repos/{o}/{r}/pulls/{n}/comments`; `POST .../pulls/{n}/ccr/comments/{comment_id}/resolve` or `/unresolve`; `PUT|DELETE .../ccr/auto_merge`; `POST .../ccr/ready_for_review`, `.../ccr/convert_to_draft`.
- `gh auth status` fails by design; `gh api` works on repositories attached to the session.
- Settings set `attribution.sessionUrl: false`, so commits get no `Claude-Session:` trailer and PR bodies get no session link. Do not add them by hand.
- Paths: repositories are at `/home/user/<repo>`, the user is root, and there is no `~/.zshenv`. Do not use `/Users/marwen/...` paths or local shell files. The environment variables come from the cloud environment settings; `~/.config/dot-env/*.env` has the same values.
- Only the default branch is cloned. Get other branches with `git fetch origin <branch>`.
- stellar-rpc: the `stellar-rpc` profile installs Go, golangci-lint, libzstd, librocksdb and sets the cgo variables. Setup logs are in `~/.config/dot-env/logs`. `make build-libs` output is in `<checkout>/target`; in a new git worktree, run `ln -s /home/user/stellar-rpc/target <worktree>/target`. Tests that need a non-root user skip themselves.
