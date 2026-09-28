# Artifact manifest

Do not write `manifest.json` by hand. Run `scripts/make_manifest.py threads.json verdicts.json manifest.json`: thread facts (comments, author, url, path, line) come from `threads.json`, you write only `verdicts.json`. Then `scripts/build_artifact.py manifest.json out.html` renders the page, reading diffs from git at render time — keep the fix branch reachable until the page is published.

## Numbering

Card `n` is the thread's 1-based position in `threads.json`. Use the same numbers in commit subjects (`pr-938: #7 …`), in the report table, and when cross-linking cards (`[#7](#c7)`), so the three always agree and a later session can pick the numbering up unchanged.

## verdicts.json

```json
{
  "pr": {
    "fixBranch": "pr-938-fixes",
    "worktree": "/abs/path/.claude/worktrees/pr-938-fixes",
    "checkoutHead": "a003f3bb3df8c257378e337090532ff5814dfea9"
  },
  "repoRoot": "/abs/path/.claude/worktrees/pr-938-fixes",
  "footer": "Markdown shown under the last card: verification you ran, caveats, mergeability.",
  "threads": {
    "7": {
      "status": "fixed",
      "title": "Preflight the kept bench packages so a roster gap fails fast",
      "why": "Markdown. Verdict on the claim, what you checked, what changed, any deviation. Link cards as [#4](#c4).",
      "commit": "cfb8365a",
      "focus": ["preflightBench", "linkable"],
      "files": ["only/show/these.go"],
      "reply": "Optional draft reply in the author's voice (markdown).",
      "deviation": true
    },
    "1": { "status": "resolve", "title": "…", "why": "…", "note": "Author's own note; cjonas9 said LGTM." }
  }
}
```

`pr` keys are merged over the `pr` block `fetch_threads.py` produced (`repo`, `number`, `title`, `url`, `head`, `headRef`, `baseRef`, `mergeable`, `author`). `checkoutHead` is the user's actual `HEAD` (`git rev-parse HEAD` in their checkout, not the worktree); the page uses it to say whether the cherry-picks apply cleanly. Omit `fixBranch` when nothing was fixed.

## Per-thread fields

| Field | Meaning |
|---|---|
| `status` | `fixed` (a commit answers it), `reply` (no code change, draft reply), `done` (already satisfied on the branch — from an earlier session or another commit), `resolve` (author's own note or acknowledged thread; nothing to do). |
| `title` | Short imperative title for the card and the nav. |
| `why` | Your verdict and evidence. Must say what you checked, not just what you did. |
| `commit` | Sha whose diff answers the comment. Required for `fixed`; set it for `done` too so the diff still shows — the page detects that the sha is already in the PR head and suppresses the apply command. |
| `focus` | Substrings; a changed line is highlighted for this thread when it contains one. List (all files) or object keyed by path with `"*"` default. Omit when the whole commit is this thread's — everything is then highlighted. Bare `}`/`//`/blank lines follow the line above, no need to match them. |
| `files` | Show only these files of the commit (for a shared commit touching files this thread has nothing to do with). Apply/undo still cover the whole commit. |
| `reply` | Draft reply, markdown. Use for `reply`, for `done` ("done in <sha>"), and for one-line deviation notes on `fixed`. |
| `note` | Short markdown for `resolve` cards (shown instead of a diff). |
| `deviation` | `true` when you deliberately did something other than the literal suggestion. Adds a "deviation" tag to the chip; say why in `why` and `reply`. |
| `applyable` | Override the automatic apply-command decision (`fixed` and not already in `pr.head`). Rarely needed. |

`comment`/`comments`: filled by `make_manifest.py` from the thread — every comment in the thread, each attributed and linked, because the decision often lives in a later reply, not the first comment. If you build a manifest without the helper, either `comments: [{author, body, url}]` or a single `comment` string works.

Markdown accepted in `why`, `reply`, `note`, `footer` and comment bodies: paragraphs, `code`, **bold**, *italic*, `[text](url)`, `-` lists (nested by indent), ``` fences, `>` quotes.

## Commit grouping and shared commits

One commit per thread is the default. When two threads' fixes interleave in the same lines, make one commit whose subject lists every thread (`pr-938: #4 #5 #8 #9 serve-phase teardown`) and give each of those threads the same `commit` with its own `focus`. The page labels the commit with all of them and dims the other threads' lines.

## Commands the page emits

- Per applicable card: `git cherry-pick -n <sha>` (stages, no commit) and `git restore --source=HEAD --staged --worktree -- <that commit's files>` to undo.
- Nav: `git cherry-pick -n <pr.head>..<fixBranch>` for every fix in order, with a note comparing `checkoutHead` to `pr.head`.
