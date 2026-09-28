#!/usr/bin/env python3
"""Render the review-reconciliation artifact from a manifest.

Usage:
    build_artifact.py manifest.json out.html

The manifest (see references/manifest.md for the full schema) names the PR, the
worktree where the fix commits live, and one entry per review thread:
status, the quoted comment, the "why", an optional draft reply, and for fixed
threads the commit sha whose diff answers the comment. Diffs are read from git
at render time, so the page always shows exactly what `git cherry-pick -n <sha>`
will stage.

When one commit carries several threads' fixes (their edits interleave in the
same lines), each thread lists `focus` substrings; changed lines matching them
are highlighted for that thread and the rest of the hunk is dimmed, so the
reader never has to guess which lines answer which comment.
"""
import html
import json
import re
import subprocess
import sys
from collections import OrderedDict

STATUS_LABEL = {
    "fixed": "Fixed",
    "reply": "Reply drafted",
    "resolve": "Resolve only",
    "done": "Already on branch",
}
STATUS_CHIP = {"fixed": "fixed", "reply": "reply", "resolve": "resolve", "done": "done"}


# ----------------------------------------------------------------- git access
def git(root, *args):
    return subprocess.run(["git", "-C", root, *args], check=True, capture_output=True, text=True).stdout


def commit_files(root, sha):
    return [f for f in git(root, "show", "--format=", "--name-only", sha).splitlines() if f]


def commit_subject(root, sha):
    return git(root, "show", "-s", "--format=%s", sha).strip()


def is_ancestor(root, sha, head):
    """True when sha is already contained in head (so cherry-picking it is wrong)."""
    if not head:
        return False
    r = subprocess.run(["git", "-C", root, "merge-base", "--is-ancestor", sha, head], capture_output=True)
    return r.returncode == 0


def parse_diff(text):
    """unified diff text -> OrderedDict{path: [ {header, lines[]} ]}"""
    files, cur = OrderedDict(), None
    for line in text.splitlines():
        if line.startswith("diff --git"):
            cur = line.split(" b/", 1)[-1]
            files[cur] = []
        elif cur is None:
            continue
        elif line.startswith("@@"):
            files[cur].append({"header": line, "lines": []})
        elif line.startswith(("--- ", "+++ ", "index ", "new file", "deleted file", "similarity", "rename ", "old mode", "new mode", "Binary files")):
            continue
        elif files[cur]:
            files[cur][-1]["lines"].append(line)
    return files


def hunk_start(header, sign):
    m = re.search(r"%s(\d+)" % re.escape(sign), header)
    return int(m.group(1)) if m else 0


# -------------------------------------------------------------- diff rendering
def render_hunk(hunk, focus):
    """focus None -> every changed line is the fix; else substrings marking the fix lines.
    Structural lines (bare '}', '//', blank) follow the changed line above them."""
    out, o, n, last = [], hunk_start(hunk["header"], "-"), hunk_start(hunk["header"], "+"), None
    for ln in hunk["lines"]:
        kind, body = ln[:1], ln[1:]
        esc = html.escape(body) or " "
        if kind == "+":
            cls, num = "add", f'<span class="ln"></span><span class="ln">{n}</span>'; n += 1
        elif kind == "-":
            cls, num = "del", f'<span class="ln">{o}</span><span class="ln"></span>'; o += 1
        elif kind == "\\":
            continue  # "\ No newline at end of file"
        else:
            cls, num = "ctx", f'<span class="ln">{o}</span><span class="ln">{n}</span>'; o += 1; n += 1
        if kind in "+-":
            if body.strip() in ("}", "//", "", "};", ")", "]") and last is not None:
                cls += " " + last
            elif focus is None or any(f in body for f in focus):
                cls += " hit"
            else:
                cls += " other"
            last = cls.split()[-1]
        mark = kind if kind in "+-" else " "
        out.append(f'<div class="dl {cls}">{num}<span class="mk">{mark}</span><span class="code">{esc}</span></div>')
    return f'<div class="hunk"><div class="hh">{html.escape(hunk["header"])}</div>{"".join(out)}</div>'


def render_commit_diff(root, sha, focus, only_files=None):
    files = parse_diff(git(root, "show", "--format=", "--no-color", "-U3", sha))
    parts = []
    for path, hunks in files.items():
        if only_files and path not in only_files:
            continue
        f_focus = focus.get(path, focus.get("*")) if isinstance(focus, dict) else focus
        body = "".join(render_hunk(h, f_focus) for h in hunks)
        parts.append(f'<figure class="file"><figcaption><span class="fp">{html.escape(path)}</span></figcaption>'
                     f'<div class="scroll">{body}</div></figure>')
    return "".join(parts)


# ------------------------------------------------------------ light markdown
def md(text):
    if not text:
        return ""
    out, para, in_code, code = [], [], False, []

    def inline(s):
        s = html.escape(s)
        s = re.sub(r"`([^`]+)`", r"<code>\1</code>", s)
        s = re.sub(r"\[([^\]]+)\]\(([^)\s]+)\)", r'<a href="\2">\1</a>', s)
        s = re.sub(r"\*\*([^*]+)\*\*", r"<strong>\1</strong>", s)
        s = re.sub(r"(?<![\w`*])[*_]([^*_]+)[*_](?![\w`*])", r"<em>\1</em>", s)
        return s

    def flush():
        nonlocal para
        if para:
            out.append("<p>" + inline(" ".join(para)) + "</p>")
            para = []

    lines, i = text.split("\n"), 0
    while i < len(lines):
        l = lines[i]
        if l.startswith("```"):
            if in_code:
                out.append('<pre class="snippet">' + html.escape("\n".join(code)) + "</pre>")
                code, in_code = [], False
            else:
                flush(); in_code = True
            i += 1; continue
        if in_code:
            code.append(l); i += 1; continue
        if re.match(r"^\s*[-*] ", l):
            flush()
            items = []
            while i < len(lines) and re.match(r"^\s*[-*] ", lines[i]):
                depth = len(lines[i]) - len(lines[i].lstrip())
                items.append((depth, re.sub(r"^\s*[-*] ", "", lines[i])))
                i += 1
            frag, stack = [], []
            for depth, it in items:
                while stack and stack[-1] > depth:
                    frag.append("</ul>"); stack.pop()
                if not stack or depth > stack[-1]:
                    frag.append("<ul>"); stack.append(depth)
                frag.append(f"<li>{inline(it)}</li>")
            frag += ["</ul>"] * len(stack)
            out.append("".join(frag)); continue
        if l.startswith(">"):
            flush()
            q = []
            while i < len(lines) and lines[i].startswith(">"):
                q.append(lines[i].lstrip("> ")); i += 1
            out.append("<blockquote>" + md("\n".join(q)) + "</blockquote>"); continue
        if not l.strip():
            flush()
        else:
            para.append(l.strip())
        i += 1
    flush()
    return "".join(out)


# --------------------------------------------------------------------- page
def cmd_block(label, cmd):
    return (f'<div class="cmd"><div class="cmd-head"><span class="eyebrow">{label}</span>'
            f'<button type="button" class="copy" data-copy="{html.escape(cmd, quote=True)}">Copy</button></div>'
            f'<pre>{html.escape(cmd)}</pre></div>')


def card(t, m, root, shared):
    n = t["n"]
    status = t["status"]
    label = STATUS_LABEL[status]
    if status in ("fixed", "done") and t.get("commit"):
        label += f' · {t["commit"][:8]}'
    if t.get("deviation"):
        label += " · deviation"
    author = html.escape(t.get("author", ""))
    loc = f'<code>{html.escape(t.get("path", ""))}:{t.get("line", "")}</code>' if t.get("path") else "conversation"
    head = f'''<header class="ch"><div class="ch-top"><span class="num">#{n}</span>
<span class="chip {STATUS_CHIP[status]}">{label}</span>
<a class="loc" href="{html.escape(t["url"])}" target="_blank" rel="noopener">{loc} · {author} ↗</a></div>
<h2 id="t{n}">{html.escape(t["title"])}</h2></header>'''
    parts = [head]
    if t.get("comments"):
        quoted = "".join(
            f'<div class="cq"><div class="eyebrow"><a href="{html.escape(c.get("url", t["url"]))}" target="_blank" rel="noopener">{html.escape(c["author"])} wrote</a></div>{md(c["body"])}</div>'
            for c in t["comments"])
        parts.append(f'<blockquote class="cmt">{quoted}</blockquote>')
    else:
        parts.append(f'<blockquote class="cmt"><div class="eyebrow">{author} wrote</div>{md(t.get("comment", ""))}</blockquote>')
    parts.append(f'<div class="why"><div class="eyebrow">Why</div>{md(t["why"])}</div>')

    if t.get("commit"):
        sha = t["commit"]
        others = [f'<a href="#c{o}">#{o}</a>' for o in shared.get(sha, []) if o != n]
        note = (f'<p class="note">This commit also carries {", ".join(others)}; their lines are dimmed here.</p>'
                if others else "")
        diff = render_commit_diff(root, sha, t.get("focus"), t.get("files"))
        parts.append(f'<div class="diffs"><div class="eyebrow">The fix — <code>{html.escape(commit_subject(root, sha))}</code></div>{note}{diff}</div>')
        applyable = t.get("applyable")
        if applyable is None:
            applyable = status == "fixed" and not is_ancestor(root, sha, m["pr"].get("head"))
        if applyable:
            files = commit_files(root, sha)
            apply_cmd = f"git cherry-pick -n {sha}"
            undo_cmd = "git restore --source=HEAD --staged --worktree -- " + " ".join(files)
            parts.append('<div class="cmds">' + cmd_block("Apply to your branch (stages, no commit)", apply_cmd)
                         + cmd_block("Undo (resets these files to HEAD)", undo_cmd) + "</div>")
        else:
            parts.append(f'<p class="note">Already on the PR branch: <code>{sha[:8]}</code> is contained in the PR head, so there is nothing to apply.</p>')
    if t.get("reply"):
        parts.append(f'<div class="reply"><div class="eyebrow">Draft reply</div>{md(t["reply"])}</div>')
    if t.get("note") and not t.get("commit"):
        parts.append(f'<p class="note">{md(t["note"])}</p>')
    return f'<article class="card" id="c{n}">{"".join(parts)}</article>'


def build(manifest):
    pr, root = manifest["pr"], manifest["repoRoot"]
    threads = manifest["threads"]
    shared = {}
    for t in threads:
        if t.get("commit"):
            shared.setdefault(t["commit"], []).append(t["n"])

    fix_branch, head = pr.get("fixBranch"), pr.get("head")
    commits = []
    if fix_branch and head:
        commits = [c for c in git(root, "rev-list", "--reverse", f"{head}..{fix_branch}").splitlines() if c]
    apply_all = f"git cherry-pick -n {head}..{fix_branch}" if commits else ""

    counts = {k: sum(1 for t in threads if t["status"] == k) for k in STATUS_LABEL}
    tally = "".join(f'<span class="chip {STATUS_CHIP[k]}">{v} {STATUS_LABEL[k].lower()}</span>' for k, v in counts.items() if v)
    nav = "".join(
        f'<a href="#c{t["n"]}" class="ni"><span class="ni-n">#{t["n"]}</span><span class="ni-t">{html.escape(t["title"])}</span>'
        f'<span class="dot {STATUS_CHIP[t["status"]]}"></span></a>' for t in threads)

    title = f'#{pr["number"]} {pr["title"]}'
    cards = "".join(card(t, manifest, root, shared) for t in threads)
    apply_all_html = ""
    if apply_all:
        co = pr.get("checkoutHead")
        if co and co.startswith(head[:8]) or (co and head.startswith(co[:8])):
            where = f'Your checkout of <code>{html.escape(pr.get("headRef", "the PR branch"))}</code> is at <code>{head[:8]}</code>, the PR head, so these apply cleanly.'
        elif co:
            where = (f'Your checkout is at <code>{co[:8]}</code> but the fixes were cut from the PR head <code>{head[:8]}</code>; '
                     f'check out <code>{head[:8]}</code> first or expect conflicts.')
        else:
            where = f'Run from your checkout of <code>{html.escape(pr.get("headRef", "the PR branch"))}</code> at <code>{head[:8]}</code>.'
        apply_all_html = ('<div class="legend-cmd">' + cmd_block(f"Apply all {len(commits)} fix{'es' if len(commits) != 1 else ''} at once", apply_all)
                          + f'<p class="note">{where} The commits live on <code>{html.escape(fix_branch)}</code> in <code>{html.escape(pr.get("worktree", ""))}</code>; '
                          f'the branch keeps them reachable even after the worktree is removed.</p></div>')

    footer = md(manifest.get("footer", ""))
    return PAGE.format(
        title=html.escape(title), pr_url=html.escape(pr["url"]), repo=html.escape(pr["repo"]), number=pr["number"],
        tally=tally, nav=nav, cards=cards, apply_all=apply_all_html, footer=footer,
        legend_fix=f'{head[:8]} → {fix_branch}' if commits else "no fix commits",
    )


PAGE = """<title>{title}</title>
<link rel="preconnect" href="https://fonts.googleapis.com">
<link rel="stylesheet" href="https://fonts.googleapis.com/css2?family=Fraunces:opsz,wght@9..144,500;9..144,600&family=Source+Sans+3:ital,wght@0,400;0,600;1,400&family=JetBrains+Mono:wght@400;500&display=swap">
<style>
:root {{
  --bg:#f5f7fa; --surface:#fff; --surface-2:#eef1f6; --line:#d6dce6; --line-soft:#e6eaf1;
  --ink:#17202b; --ink-2:#4a5566; --ink-3:#7a8494;
  --accent:#2f4f9a; --accent-soft:#e4eaf7;
  --add-bg:#e4f4e7; --add-ink:#1c5c30; --add-bar:#2e8b4a; --del-bg:#fbe5e3; --del-ink:#8b2a22;
  --hit-rail:#2f4f9a; --quote-bg:#f8f5ee; --quote-bar:#b89b5a; --reply-bg:#eef5f0; --cmd-bg:#1b2230; --cmd-ink:#e6eaf0;
  --chip-fixed-bg:#dff1e4; --chip-fixed-ink:#1c5c30; --chip-reply-bg:#fdf0d5; --chip-reply-ink:#7a5310;
  --chip-res-bg:#e8eaee; --chip-res-ink:#4a5566; --chip-done-bg:#e4eaf7; --chip-done-ink:#2f4f9a;
  --shadow:0 1px 2px rgba(23,32,43,.06),0 6px 18px rgba(23,32,43,.05);
}}
@media (prefers-color-scheme: dark) {{ :root:not([data-theme="light"]) {{
  --bg:#101419; --surface:#171c23; --surface-2:#1e252e; --line:#2b3441; --line-soft:#232b36;
  --ink:#e6eaf0; --ink-2:#aab3c0; --ink-3:#7d8794; --accent:#8fa8e6; --accent-soft:#1e2a44;
  --add-bg:#14301d; --add-ink:#9fd8ae; --add-bar:#3f9b5b; --del-bg:#3a1a18; --del-ink:#f0a49c;
  --hit-rail:#8fa8e6; --quote-bg:#1c1a15; --quote-bar:#9c854d; --reply-bg:#14201a; --cmd-bg:#0b0e13; --cmd-ink:#e6eaf0;
  --chip-fixed-bg:#17331f; --chip-fixed-ink:#9fd8ae; --chip-reply-bg:#3a2c10; --chip-reply-ink:#f0cf84;
  --chip-res-bg:#232b36; --chip-res-ink:#aab3c0; --chip-done-bg:#1e2a44; --chip-done-ink:#b5c6f2;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 6px 18px rgba(0,0,0,.35);
}} }}
:root[data-theme="dark"] {{
  --bg:#101419; --surface:#171c23; --surface-2:#1e252e; --line:#2b3441; --line-soft:#232b36;
  --ink:#e6eaf0; --ink-2:#aab3c0; --ink-3:#7d8794; --accent:#8fa8e6; --accent-soft:#1e2a44;
  --add-bg:#14301d; --add-ink:#9fd8ae; --add-bar:#3f9b5b; --del-bg:#3a1a18; --del-ink:#f0a49c;
  --hit-rail:#8fa8e6; --quote-bg:#1c1a15; --quote-bar:#9c854d; --reply-bg:#14201a; --cmd-bg:#0b0e13; --cmd-ink:#e6eaf0;
  --chip-fixed-bg:#17331f; --chip-fixed-ink:#9fd8ae; --chip-reply-bg:#3a2c10; --chip-reply-ink:#f0cf84;
  --chip-res-bg:#232b36; --chip-res-ink:#aab3c0; --chip-done-bg:#1e2a44; --chip-done-ink:#b5c6f2;
  --shadow:0 1px 2px rgba(0,0,0,.4),0 6px 18px rgba(0,0,0,.35);
}}
*{{box-sizing:border-box}} html{{scroll-behavior:smooth}}
@media (prefers-reduced-motion: reduce){{ html{{scroll-behavior:auto}} }}
body{{margin:0;background:var(--bg);color:var(--ink);font:16px/1.55 "Source Sans 3","Helvetica Neue",Arial,sans-serif}}
a{{color:var(--accent)}} a:focus-visible,button:focus-visible,.ni:focus-visible{{outline:2px solid var(--accent);outline-offset:2px}}
code,pre,.hunk{{font-family:"JetBrains Mono",ui-monospace,SFMono-Regular,Menlo,monospace}}
code{{font-size:.88em;background:var(--surface-2);padding:.05em .35em;border-radius:3px}}
h1,h2{{font-family:"Fraunces",Georgia,serif;font-weight:600;text-wrap:balance;letter-spacing:-.01em}}
.eyebrow{{font-size:.72rem;text-transform:uppercase;letter-spacing:.09em;color:var(--ink-3);font-weight:600;margin-bottom:.45rem}}
.wrap{{max-width:1280px;margin:0 auto;padding:2rem 1.5rem 5rem;display:grid;grid-template-columns:270px minmax(0,1fr);gap:2.5rem;align-items:start}}
@media (max-width:900px){{ .wrap{{grid-template-columns:1fr}} nav.idx{{position:static}} }}
nav.idx{{position:sticky;top:1.5rem;display:flex;flex-direction:column;gap:1rem;max-height:calc(100vh - 3rem);overflow-y:auto}}
nav.idx h1{{font-size:1.5rem;line-height:1.15;margin:0}} nav.idx .sub{{color:var(--ink-2);font-size:.92rem;margin:0}} nav.idx .sub a{{text-decoration:none}}
.tally{{display:flex;gap:.5rem;flex-wrap:wrap}}
.chip{{display:inline-block;font-size:.72rem;font-weight:600;letter-spacing:.04em;text-transform:uppercase;padding:.18rem .55rem;border-radius:999px;white-space:nowrap}}
.chip.fixed{{background:var(--chip-fixed-bg);color:var(--chip-fixed-ink)}} .chip.reply{{background:var(--chip-reply-bg);color:var(--chip-reply-ink)}}
.chip.resolve{{background:var(--chip-res-bg);color:var(--chip-res-ink)}} .chip.done{{background:var(--chip-done-bg);color:var(--chip-done-ink)}}
.nl{{display:flex;flex-direction:column;border-top:1px solid var(--line)}}
.ni{{display:grid;grid-template-columns:2.2rem 1fr auto;gap:.5rem;align-items:baseline;padding:.45rem .25rem;border-bottom:1px solid var(--line-soft);text-decoration:none;color:var(--ink);font-size:.9rem}}
.ni:hover{{background:var(--surface-2)}} .ni-n{{color:var(--ink-3);font-variant-numeric:tabular-nums;font-size:.82rem}} .ni-t{{line-height:1.3}}
.dot{{width:.55rem;height:.55rem;border-radius:50%;align-self:center}}
.dot.fixed{{background:var(--add-bar)}} .dot.reply{{background:#d9a441}} .dot.resolve{{background:var(--ink-3)}} .dot.done{{background:var(--accent)}}
.legend{{font-size:.82rem;color:var(--ink-2);border-top:1px solid var(--line);padding-top:.8rem;display:grid;gap:.35rem}}
.legend .sw{{display:inline-block;width:1.1rem;height:.8rem;vertical-align:-2px;margin-right:.4rem;border-radius:2px}}
.legend-cmd{{border-top:1px solid var(--line);padding-top:.8rem}}
main{{display:flex;flex-direction:column;gap:2rem;min-width:0}}
.card{{background:var(--surface);border:1px solid var(--line);border-radius:8px;box-shadow:var(--shadow);padding:1.4rem 1.6rem 1.6rem;display:flex;flex-direction:column;gap:1.1rem;min-width:0}}
.ch-top{{display:flex;align-items:center;gap:.7rem;flex-wrap:wrap;margin-bottom:.35rem}}
.num{{font-family:"Fraunces",Georgia,serif;font-size:1.05rem;color:var(--ink-3);font-variant-numeric:tabular-nums}}
.loc{{margin-left:auto;font-size:.85rem;text-decoration:none;color:var(--ink-2)}} .loc code{{background:transparent;padding:0;color:var(--ink-2)}} .loc:hover{{color:var(--accent)}}
.ch h2{{margin:0;font-size:1.45rem;line-height:1.2}}
.cmt{{margin:0;padding:1rem 1.2rem;background:var(--quote-bg);border-left:3px solid var(--quote-bar);border-radius:0 6px 6px 0;max-width:72ch}}
.cq+.cq{{margin-top:.9rem;padding-top:.9rem;border-top:1px dashed var(--line)}} .cq .eyebrow a{{color:inherit;text-decoration:none}} .cq .eyebrow a:hover{{color:var(--accent)}}
.cmt p,.why p,.reply p{{margin:0 0 .7rem}} .cmt p:last-child,.why p:last-child,.reply p:last-child{{margin-bottom:0}}
.cmt ul,.reply ul,.why ul{{margin:.2rem 0 .6rem 1.1rem;padding:0}} .cmt ul ul{{margin:.15rem 0 .2rem 1rem}}
.cmt blockquote{{margin:.4rem 0;padding-left:.8rem;border-left:2px solid var(--line);color:var(--ink-2)}}
.snippet{{margin:.5rem 0 .8rem;padding:.7rem .9rem;font-size:.8rem;line-height:1.5;background:var(--surface-2);border-radius:4px;overflow-x:auto}}
.why{{padding-left:1.2rem;border-left:3px solid var(--accent);max-width:72ch}}
.reply{{background:var(--reply-bg);border-radius:6px;padding:1rem 1.2rem;max-width:72ch}}
.note{{margin:0;font-size:.9rem;color:var(--ink-2);max-width:72ch}}
.diffs{{display:flex;flex-direction:column;gap:.8rem}}
.file{{margin:0;border:1px solid var(--line);border-radius:6px;overflow:hidden}}
.file figcaption{{background:var(--surface-2);padding:.45rem .8rem;font-size:.82rem;border-bottom:1px solid var(--line)}}
.fp{{font-family:"JetBrains Mono",monospace;color:var(--ink-2)}} .scroll{{overflow-x:auto}}
.hunk{{font-size:.78rem;line-height:1.45;min-width:max-content}} .hunk+.hunk{{border-top:1px solid var(--line)}}
.hh{{color:var(--ink-3);background:var(--surface-2);padding:.15rem .8rem .15rem 7.4rem;border-bottom:1px solid var(--line-soft)}}
.dl{{display:grid;grid-template-columns:2.8rem 2.8rem 1.2rem 1fr}}
.dl .ln{{text-align:right;padding-right:.5rem;color:var(--ink-3);user-select:none;font-variant-numeric:tabular-nums;border-right:1px solid var(--line-soft)}}
.dl .mk{{text-align:center;user-select:none;color:var(--ink-3)}} .dl .code{{white-space:pre;padding-right:1rem;tab-size:4}}
.dl.add{{background:var(--add-bg);color:var(--add-ink)}} .dl.add .mk{{color:var(--add-ink)}}
.dl.del{{background:var(--del-bg);color:var(--del-ink)}} .dl.del .mk{{color:var(--del-ink)}}
.dl.hit{{box-shadow:inset 3px 0 0 var(--hit-rail)}} .dl.other{{opacity:.38}} .dl.other:hover{{opacity:.85}}
.cmds{{display:grid;gap:.6rem;grid-template-columns:repeat(auto-fit,minmax(320px,1fr))}}
.cmd{{background:var(--cmd-bg);color:var(--cmd-ink);border-radius:6px;padding:.6rem .8rem;min-width:0}}
.cmd .eyebrow{{color:#9aa6b8;margin:0}} .cmd-head{{display:flex;justify-content:space-between;align-items:center;gap:.5rem;margin-bottom:.35rem}}
.cmd pre{{margin:0;font-size:.8rem;line-height:1.45;white-space:pre-wrap;word-break:break-all}}
.copy{{font:inherit;font-size:.75rem;padding:.15rem .55rem;border-radius:4px;border:1px solid #3a4658;background:transparent;color:var(--cmd-ink);cursor:pointer}}
.copy:hover{{background:#2a3446}}
.footer{{color:var(--ink-3);font-size:.85rem;max-width:72ch}}
</style>
<div class="wrap">
<nav class="idx">
  <h1>{title}</h1>
  <p class="sub">Review reconciliation — <a href="{pr_url}" target="_blank" rel="noopener">{repo}#{number}</a>. Every open thread, the exact lines that answer it, and why.</p>
  <div class="tally">{tally}</div>
  <div class="nl">{nav}</div>
  {apply_all}
  <div class="legend">
    <div><span class="sw" style="background:var(--add-bg);box-shadow:inset 3px 0 0 var(--hit-rail)"></span>Changed line that answers <em>this</em> comment</div>
    <div><span class="sw" style="background:var(--add-bg);opacity:.38"></span>Same commit, belongs to another comment (linked)</div>
    <div>Fix commits: <code>{legend_fix}</code></div>
  </div>
</nav>
<main>
{cards}
<p class="footer">{footer}</p>
</main>
</div>
<script>
document.addEventListener('click', function (e) {{
  var b = e.target.closest('.copy'); if (!b) return;
  var text = b.getAttribute('data-copy');
  var done = function () {{ var old = b.textContent; b.textContent = 'Copied'; setTimeout(function () {{ b.textContent = old; }}, 1200); }};
  try {{ navigator.clipboard.writeText(text).then(done, function () {{ fallback(); }}); }} catch (err) {{ fallback(); }}
  function fallback() {{
    var ta = document.createElement('textarea'); ta.value = text; document.body.appendChild(ta); ta.select();
    try {{ document.execCommand('copy'); done(); }} catch (e2) {{}} document.body.removeChild(ta);
  }}
}});
</script>
"""


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    manifest = json.load(open(sys.argv[1]))
    out = build(manifest)
    with open(sys.argv[2], "w") as f:
        f.write(out)
    print(f"wrote {sys.argv[2]} ({len(out)} bytes, {len(manifest['threads'])} threads)", file=sys.stderr)


if __name__ == "__main__":
    main()
