#!/usr/bin/env python3
"""Dump a PR's review threads as JSON via `gh api graphql`.

Usage:
    fetch_threads.py OWNER/REPO NUMBER [--all] > threads.json

By default only unresolved threads are emitted. `--all` keeps resolved ones too,
which is useful for sampling the PR author's own comments (reply tone) and for
re-verifying threads a reviewer resolved early.

Output shape (one object per thread):
    {
      "id": "...", "isResolved": false, "isOutdated": false,
      "path": "cmd/.../serve.go", "line": 37, "originalLine": 37,
      "diffHunk": "@@ ... (the hunk GitHub attached to the first comment)",
      "url": "https://github.com/.../pull/N#discussion_r...",
      "comments": [
        {"author": "tamirms", "body": "...", "createdAt": "...", "url": "..."}
      ]
    }

Requires an authenticated `gh` (run `gh auth status`). Pagination is handled
for up to 100 threads x 100 comments each, which covers any realistic PR.
"""
import json
import subprocess
import sys

QUERY = """
query($owner: String!, $name: String!, $number: Int!, $after: String) {
  repository(owner: $owner, name: $name) {
    pullRequest(number: $number) {
      title url headRefOid headRefName baseRefName mergeable
      author { login }
      reviewThreads(first: 100, after: $after) {
        pageInfo { hasNextPage endCursor }
        nodes {
          id isResolved isOutdated path line originalLine
          comments(first: 100) {
            nodes { author { login } body createdAt url diffHunk }
          }
        }
      }
    }
  }
}
"""


def gql(owner, name, number, after):
    cmd = [
        "gh", "api", "graphql",
        "-F", f"owner={owner}", "-F", f"name={name}", "-F", f"number={number}",
        "-f", f"query={QUERY}",
    ]
    if after:
        cmd += ["-F", f"after={after}"]
    out = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout
    return json.loads(out)["data"]["repository"]["pullRequest"]


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    keep_all = "--all" in sys.argv
    if len(args) != 2 or "/" not in args[0]:
        sys.exit(__doc__)
    owner, name = args[0].split("/", 1)
    number = int(args[1])

    threads, after, pr = [], None, None
    while True:
        pr = gql(owner, name, number, after)
        page = pr["reviewThreads"]
        for t in page["nodes"]:
            comments = t["comments"]["nodes"]
            if not comments:
                continue
            threads.append({
                "id": t["id"],
                "isResolved": t["isResolved"],
                "isOutdated": t["isOutdated"],
                "path": t["path"],
                "line": t["line"] or t["originalLine"],
                "originalLine": t["originalLine"],
                "diffHunk": comments[0].get("diffHunk", ""),
                "url": comments[0]["url"],
                "comments": [
                    {"author": (c["author"] or {}).get("login", "ghost"), "body": c["body"],
                     "createdAt": c["createdAt"], "url": c["url"]}
                    for c in comments
                ],
            })
        if not page["pageInfo"]["hasNextPage"]:
            break
        after = page["pageInfo"]["endCursor"]

    if not keep_all:
        threads = [t for t in threads if not t["isResolved"]]

    result = {
        "pr": {
            "repo": f"{owner}/{name}", "number": number, "title": pr["title"], "url": pr["url"],
            "head": pr["headRefOid"], "headRef": pr["headRefName"], "baseRef": pr["baseRefName"],
            "mergeable": pr["mergeable"], "author": (pr["author"] or {}).get("login", ""),
        },
        "threads": threads,
    }
    json.dump(result, sys.stdout, indent=2)
    n_open = sum(1 for t in threads if not t["isResolved"])
    print(f"\n{len(threads)} threads emitted ({n_open} unresolved) for {owner}/{name}#{number} @ {pr['headRefOid'][:8]}",
          file=sys.stderr)


if __name__ == "__main__":
    main()
