# Subagent prompts

All subagents: `subagent_type: "engineer"` for tasks that need judgment (analysis, opinions), `subagent_type: "worker"` for pure extraction or reading (fall back to `model: "opus"` if the agent type is missing). Launch them in one turn. Each prompt is self-contained — the subagent has *no* conversation context. Fill every `<…>`.

The common preamble every prompt starts with:

```
You are working in the repo at <ABS_REPO_PATH>, already checked out on <BRANCH>.
Read-only: do NOT edit tracked files, do NOT commit, do NOT switch branches,
do NOT post anything to GitHub. Use <SCRATCH_DIR> for any scratch files.
Merge base: <BASE_SHA>. Saved diffs: <SCRATCH_DIR>/full.diff,
<SCRATCH_DIR>/prod.diff, <SCRATCH_DIR>/tests.diff. Read working-tree files
whenever the diff context is insufficient; report working-tree line numbers.

What the change claims to do (author's summary):
<3–8 lines distilled from the PR description — the mechanisms, not the prose>

When done, write your COMPLETE report to <SCRATCH_DIR>/<name>.md and reply
with the single word "written". Do not summarize in the reply — notifications
are truncated and the file is the deliverable.
```

Reports use terse structured markdown: `- file:line — finding — suggested fix`. No praise padding, no long code dumps (≤5-line snippets only where essential). Mark anything not verified as "unverified".

---

## verifier

Purpose: the facts the page's verdict rests on. Runs to completion even if other agents are cut short.

```
<preamble>

Build prerequisites: <e.g. "Go with cgo; Rust static libs must exist — try
`go build ./...` first; only run `make build-libs` (slow, timeout 600000) if
the linker complains about lib*.a">.

Packages/dirs touched by the change: <list>.

Tasks, in order — report each as PASS/FAIL with verbatim output on failure:
1. Build: `<build cmd>`.
2. Static checks: `<vet / typecheck cmd>`.
3. Tests on touched packages: `<test cmd>` (timeout 600000). Report every FAIL
   line and package summary lines verbatim. If a package approaches the
   default timeout, re-run it alone with a longer timeout and report both times.
4. Race/concurrency detector on the packages that add pools, locks, callbacks,
   or shared buffers: `<race cmd>`. Report any race verbatim.
5. Flakiness probe on the new tests: `<test cmd> -count=5 -run '<regex of new
   test names>'`. Also list which test names matched.
6. Lint: check the tool is installed and its version. Run full-tree on the
   touched dirs AND `--new-from-rev=<BASE_SHA>` (or the equivalent) so
   pre-existing issues are separated from new ones. Report new issues verbatim
   with file:line.
7. Changelog: `git diff <BASE_SHA>..HEAD --stat -- CHANGELOG.md` (empty = no
   entry; just report the fact).
8. Dead references: for each symbol the change deletes — <list, e.g.
   `GetLedgerRaw`, `viewLedgerSource`> — `grep -rn` the repo (prod and tests
   separately) and report hits.

Report format:
- Build / Static / Tests / Race / Flakiness / Lint / Changelog / Dead refs —
  one section each, PASS or FAIL, verbatim output for anything non-passing,
  tool versions where relevant. Facts only; no speculation about causes.
```

---

## test-auditor

Purpose: does each claimed behaviour have a test that would actually fail on regression?

```
<preamble>

Claimed behaviours (from the change description) — for EACH, name the test(s)
that pin it and say whether the test would fail if the behaviour regressed:
<numbered list of behaviours, each one sentence, e.g.
 1. GetPinned releases the pinned handle and the lock on a panicking callback.
 2. The hot store never pools a buffer larger than 64 MiB.
 3. compactView's output never aliases the lent buffer (nil vs empty preserved).
 4. A close time of 0 is treated as known, not as absent.>

Then answer:
A. Coverage gaps — behaviours with no test, or with a test that passes even
   when the behaviour is broken. For each: file:line, the concrete gap (state
   the specific production change that would NOT be caught), a one-line fix.
   Pay special attention to tests that assert an observable which the SAME
   change made insensitive (e.g. an allocation budget after the change added
   pooling; a byte comparison performed before the buffer could be reused).
B. Test quality — flag: reliance on pool identity or GC timing; sleeps;
   thresholds brittle across toolchain versions; duplicated helpers across
   packages; test names that don't match what is asserted; doc comments that
   overclaim; tests of implementation details rather than behaviour; every
   touched test file's line count (flag > 1000).
C. Deleted or rewritten tests — what coverage was removed, and whether an
   equivalent exists. Report `git grep` at <BASE_SHA> for any symbol the brief
   says was removed so stale claims are caught.
D. What the tests reveal about production — tests weakened to pass, new
   t.Skip / nolint / commented-out assertions, a branch that exists in
   production but is exercised by nothing.

End with a 3-line verdict on test adequacy. Structure: sections A–D, bullets
`- file:line — finding — fix`.
```

---

## risk-auditor

Purpose: the change-specific adversary. Its question list is *your* list (c) from reading the production diff — the places where correctness depends on something outside the diff. Do not send a generic checklist; send the specific hazards.

```
<preamble>

You are an adversarial correctness reviewer focused on <THE RISK CLASS:
e.g. "memory lifetime, aliasing, and concurrency" / "error-path handling and
silent fallbacks" / "schema and data-migration safety" / "auth boundaries">.

The change introduces these mechanisms (file:function for each):
<numbered list — the new APIs, their contracts, who calls them>

Hunt for real bugs. For each candidate, trace the actual code path and either
CONFIRM with file:line evidence or DISCARD. Questions to answer:

(a) <specific question, e.g. "Escape analysis of every WithLedger / GetPinned /
    ReadItem callback in production: list every value that leaves each closure.
    For xdr decodes inside a loan, determine copy vs alias by reading the
    decoder in $(go env GOMODCACHE)/<module>@<ver>/…">
(b) <specific question, e.g. "Pool correctness: is the buffer returned on
    panic? on decode failure? is the size cap applied to the grown capacity?
    what does Decode(dst, src) do with dst's capacity — confirm in the library">
(c) <specific question, e.g. "Lock scope: what does mu actually guard; does any
    production callback re-enter the store; how long is the lock held and does
    that block writers or only Close">
(d) <specific question about routing / snapshot / race windows>
(e) <specific question about error mapping vs the `-` lines of the diff>
(f) <specific question: grep the tree for the removed sentinel / old API and
    report any survivor>

Report: numbered findings, each with severity (Critical / Required / Optional
/ Nit / FYI), file:line, 2–4 sentences of traced evidence, a concrete fix.
Then a "Discarded candidates" list of one-liners for everything you checked
that was fine — the reviewer needs to know what was covered. Then an
"Unverified" list for anything you could not confirm. Never present
speculation as fact.
```

---

## context-scout (optional; the only agent in `--no-verdict` mode)

Purpose: fetch the facts you need to *explain* the change, when they require a sweep.

```
<preamble>

Answer these questions with file:line evidence; do not review or judge:
1. Every caller of <new API> in production code, and what each callback/closure
   does with the value it receives.
2. What <deleted symbol> did before the change (read it at <BASE_SHA> via
   `git show <BASE_SHA>:<path>`), and where its behaviour now lives.
3. For <external type/function>, in $(go env GOMODCACHE)/<module>@<ver>/…:
   <the specific fact — field list, copy-vs-alias, growth strategy, panic
   precondition>.
4. <any other sweep>

Report as a numbered list mirroring the questions, terse, with paths and
line numbers a reader can open.
```

---

## Reading the reports

- `grep -n '^##\|^###' <file>` first, then `sed -n 'A,Bp' <file> | grep -v '^$' | cut -c1-900` per section. Never `cat` the whole file.
- Before any finding goes on the page, open the cited lines yourself (`sed -n`). Confirmed → page. Not confirmed → drop it or mark "unverified" in your own words.
- Duplicates across auditors are common (the test-auditor and risk-auditor will both notice a missing test). Merge them; credit is irrelevant, the finding is what matters.
- A subagent that says "the brief is wrong about X" is usually right — check, and fix the page's premise rather than the subagent's conclusion.
