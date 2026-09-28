#!/usr/bin/env python3
"""Dump a PR's review threads as JSON via `gh api graphql` (or REST in cloud sessions).

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
        {"author": "tamirms", "body": "...", "createdAt": "...", "url": "...", "id": 123}
      ]
    }

Cloud sessions block GraphQL (HTTP 403). The script then uses REST: the CCR
route `pulls/N/ccr/review_threads` plus `pulls/N/comments`. It selects REST when
CLAUDE_CODE_REMOTE=true, or when the GraphQL call fails with a GraphQL 403.
On REST, the thread "id" is the first comment id as a string (REST has no
PRRT_ node ids); `POST pulls/N/ccr/comments/{id}/resolve` accepts it.

Requires an authenticated `gh` (run `gh auth status`). Pagination is handled
for up to 100 threads x 100 comments each, which covers any realistic PR.
"""
import json
import os
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
            nodes { databaseId author { login } body createdAt url diffHunk }
          }
        }
      }
    }
  }
}
"""


class GraphQLBlocked(Exception):
    """The GraphQL API refused the call (cloud sessions answer HTTP 403)."""


def gql(owner, name, number, after):
    cmd = [
        "gh", "api", "graphql",
        "-F", f"owner={owner}", "-F", f"name={name}", "-F", f"number={number}",
        "-f", f"query={QUERY}",
    ]
    if after:
        cmd += ["-F", f"after={after}"]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        msg = r.stdout + r.stderr
        if "403" in msg and "graphql" in msg.lower():
            raise GraphQLBlocked(r.stderr.strip())
        raise subprocess.CalledProcessError(r.returncode, cmd, r.stdout, r.stderr)
    return json.loads(r.stdout)["data"]["repository"]["pullRequest"]


def rest(path, *extra):
    cmd = ["gh", "api", path, *extra]
    out = subprocess.run(cmd, check=True, capture_output=True, text=True).stdout
    # --paginate can emit one JSON document per page; join list pages into one list.
    docs, dec, i = [], json.JSONDecoder(), 0
    while i < len(out):
        if out[i].isspace():
            i += 1
            continue
        doc, i = dec.raw_decode(out, i)
        docs.append(doc)
    if len(docs) == 1:
        return docs[0]
    return [x for d in docs for x in d]


def fetch_graphql(owner, name, number):
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
                     "createdAt": c["createdAt"], "url": c["url"], "id": c["databaseId"]}
                    for c in comments
                ],
            })
        if not page["pageInfo"]["hasNextPage"]:
            break
        after = page["pageInfo"]["endCursor"]
    meta = {
        "title": pr["title"], "url": pr["url"], "head": pr["headRefOid"],
        "headRef": pr["headRefName"], "baseRef": pr["baseRefName"],
        "mergeable": pr["mergeable"], "author": (pr["author"] or {}).get("login", ""),
    }
    return meta, threads


MERGEABLE = {True: "MERGEABLE", False: "CONFLICTING", None: "UNKNOWN"}


def fetch_rest(owner, name, number):
    base = f"repos/{owner}/{name}/pulls/{number}"
    pr = rest(base)
    by_id = {c["id"]: c for c in rest(f"{base}/comments", "--paginate")}
    threads = []
    for t in rest(f"{base}/ccr/review_threads", "--paginate"):
        comments = sorted((by_id[i] for i in t["comment_ids"] if i in by_id), key=lambda c: c["created_at"])
        if not comments:
            continue
        first = comments[0]
        original = first.get("original_line")
        threads.append({
            "id": str(first["id"]),
            "isResolved": t["resolved"],
            "isOutdated": t["outdated"],
            "path": t.get("path") or first.get("path"),
            "line": t.get("line") or first.get("line") or original,
            "originalLine": original,
            "diffHunk": first.get("diff_hunk", ""),
            "url": first["html_url"],
            "comments": [
                {"author": (c.get("user") or {}).get("login", "ghost"), "body": c["body"],
                 "createdAt": c["created_at"], "url": c["html_url"], "id": c["id"]}
                for c in comments
            ],
        })
    threads.sort(key=lambda t: t["comments"][0]["createdAt"])
    meta = {
        "title": pr["title"], "url": pr["html_url"], "head": pr["head"]["sha"],
        "headRef": pr["head"]["ref"], "baseRef": pr["base"]["ref"],
        "mergeable": MERGEABLE.get(pr.get("mergeable"), "UNKNOWN"),
        "author": (pr.get("user") or {}).get("login", ""),
    }
    return meta, threads


def main():
    args = [a for a in sys.argv[1:] if not a.startswith("--")]
    keep_all = "--all" in sys.argv
    if len(args) != 2 or "/" not in args[0]:
        sys.exit(__doc__)
    owner, name = args[0].split("/", 1)
    number = int(args[1])

    if os.environ.get("CLAUDE_CODE_REMOTE") == "true":
        meta, threads = fetch_rest(owner, name, number)
    else:
        try:
            meta, threads = fetch_graphql(owner, name, number)
        except GraphQLBlocked:
            print("GraphQL is blocked (HTTP 403); falling back to the REST CCR routes", file=sys.stderr)
            meta, threads = fetch_rest(owner, name, number)

    if not keep_all:
        threads = [t for t in threads if not t["isResolved"]]

    result = {
        "pr": {"repo": f"{owner}/{name}", "number": number, **meta},
        "threads": threads,
    }
    json.dump(result, sys.stdout, indent=2)
    n_open = sum(1 for t in threads if not t["isResolved"])
    print(f"\n{len(threads)} threads emitted ({n_open} unresolved) for {owner}/{name}#{number} @ {meta['head'][:8]}",
          file=sys.stderr)


if __name__ == "__main__":
    main()
