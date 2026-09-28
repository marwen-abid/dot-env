#!/usr/bin/env python3
"""Merge threads.json (from fetch_threads.py) with your verdicts into manifest.json.

Usage:
    make_manifest.py threads.json verdicts.json manifest.json

Thread facts (comments, author, url, path, line) come from threads.json so they
are never retyped; you write only the judgement. Card numbers are positional:
thread `n` is the n-th entry of threads.json (1-based), which keeps numbering
stable across sessions and lets commit subjects say `#n`.

verdicts.json:
    {
      "pr": {                       # merged over the pr block from threads.json
        "fixBranch": "pr-938-fixes",
        "worktree": "/abs/path/.claude/worktrees/pr-938-fixes",
        "checkoutHead": "a003f3bb..."   # the user's actual HEAD (git rev-parse HEAD in their checkout)
      },
      "repoRoot": "/abs/path/.claude/worktrees/pr-938-fixes",
      "footer": "markdown",
      "threads": {
        "1": {"status": "fixed", "title": "...", "why": "...", "commit": "sha",
              "focus": ["..."], "files": ["..."], "reply": "...", "note": "...",
              "deviation": true, "applyable": false},
        "2": {...}
      }
    }

Every unresolved thread must have a verdict; the script fails loudly otherwise
so a thread cannot fall off the page by accident.
"""
import json
import sys


def main():
    if len(sys.argv) != 4:
        sys.exit(__doc__)
    threads = json.load(open(sys.argv[1]))
    verdicts = json.load(open(sys.argv[2]))

    pr = dict(threads["pr"])
    pr.update(verdicts.get("pr", {}))
    out = {"pr": pr, "repoRoot": verdicts["repoRoot"], "footer": verdicts.get("footer", ""), "threads": []}

    missing = []
    for i, t in enumerate(threads["threads"], start=1):
        v = verdicts["threads"].get(str(i))
        if v is None:
            missing.append(f"#{i} {t['path']}:{t['line']} ({t['comments'][0]['author']})")
            continue
        entry = {
            "n": i,
            "path": t["path"],
            "line": t["line"],
            "author": t["comments"][0]["author"],
            "url": t["url"],
            "comments": [{"author": c["author"], "body": c["body"], "url": c["url"]} for c in t["comments"]],
        }
        entry.update(v)
        out["threads"].append(entry)

    if missing:
        sys.exit("no verdict for:\n  " + "\n  ".join(missing))
    extra = set(verdicts["threads"]) - {str(i) for i in range(1, len(threads["threads"]) + 1)}
    if extra:
        sys.exit(f"verdicts for threads that do not exist: {sorted(extra)}")

    json.dump(out, open(sys.argv[3], "w"), indent=2)
    print(f"wrote {sys.argv[3]}: {len(out['threads'])} threads", file=sys.stderr)


if __name__ == "__main__":
    main()
