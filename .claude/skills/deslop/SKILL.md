---
name: deslop
description: "Diff-scoped AI-slop cleanup pass for Go code. Strips comment slop, defensive-check slop, type laundering, speculative scaffolding, test slop and style drift from the current branch diff before review, and reports what it left for the author. Use whenever the user says deslop, de-slop, remove the slop / AI slop, tighten or clean up a Go branch, PR or stacked PR before review or autoreview, or says the diff reads like a model wrote it, even when they do not say 'slop'."
---

# Deslop (Go)

Clean only the current branch diff before review. Preserve behavior absolutely.

Slop is code or prose that a careful Go maintainer would not write. It accumulates when a model writes code, and it grows each review round when the author answers feedback by adding a guard, a clause or a test. It hides the real design from the reviewer. Most of the work is deletion.

## Checklist

1. Scope the pass to the branch diff.
   - Find the real base. If a PR exists, use its base branch (`gh pr view --json baseRefName`). A stacked PR's base is its parent branch, not `origin/main`. Without a PR, use the merge base with `origin/main`. If that diff is far larger than the branch's own commits, the branch is stacked: find the nearest parent branch (`git branch -r --contains HEAD~N`, `git log --oneline --decorate`) and use it.
   - Diff with `git diff <merge-base>` (no `...HEAD`), so uncommitted edits are in scope too.
   - Never run a repo-wide cleanup. Code outside the diff is the style reference, not a target.
   - Read each touched file whole before you judge its hunks. "Abnormal for the surrounding module" needs the module.
   - In a stack, look at the child branches too. Code that the next PR uses is planned, not dead; still report it if this PR must stand alone, but say who uses it. Do not edit lines that the next PR rewrites: the edit buys a restack conflict and nothing else.
2. Inspect every changed hunk for the categories under "What to look for".
3. Make no functional edits. In Go, behavior includes returned errors and their text, log lines, emitted file or wire formats (CSV rows, JSON fields), flags, exported identifiers and lint status. If cleanup could change any of these, leave it alone and report it.
4. Fix a finding inline only when the cleanup is trivial and behavior-neutral. Otherwise note it for the author. After edits, run `gofmt`, `go build`, `go vet` and `go test` on the touched packages, and `golangci-lint run` on them when the repo configures it. A cleanup that breaks the build, a test or the linter is not neutral: revert it and report the finding. A comment you shorten or rewrite must still be true: check each claim against the code, because a rewrite can keep an old mistake.
5. Report the result in 1–3 sentences, including whether anything changed and any non-trivial item left for review. Keep file counts, line counts and verification details out of those sentences; they go below. Then list the items left for the author, one line each, with `file:line`, most important first. If you saw a real bug while reading, put it first and say it is a bug; a deslop pass does not fix bugs, but it must not hide one.

## What to look for

Each category names signals, not rules. Judge each case against the surrounding code.

### Comment slop

A Go comment earns its place when it gives a unit, an invariant, a concurrency rule, a non-obvious contract, or the reason for a surprising choice. Everything else is noise that goes stale.

- Doc comments on every unexported field or constant that restate the name: `// dispatched counts the measured requests that ran`. Go does not ask for these.
- Essays: byte-budget arithmetic, derivations, a full file-format contract inside a godoc. Keep the conclusion and one reason. A format contract belongs where its consumer reads it; report that move.
- The same sentence on each field (`Written by the dispatch goroutine only.` four times). Group the fields by owner and write the rule once. Put `mu` directly above the fields it guards.
- Floating comments attached to no declaration, and package prose outside `doc.go`.
- Cross-reference litter (`(see timed)`) for code that is adjacent, narration of the next line, and rhetoric that argues with the reviewer (`worth ending before it starts, not after hours`, `Keep the margin.`).
- Names of branches, PR numbers, review rounds or "the next PR in this stack". They are wrong on the day the stack merges.
- Justification of a micro-choice (`holds no pointer, so the slice needs no GC scan`). Keep it only if the choice is load-bearing and measured.

For a comment that stays but reads robotic, the voice rules in the `doc-comment-cleanup` skill apply.

### Defensive-check slop

Go validates at the boundary (flag parsing, an options `validate()`, a network decoder) and trusts internal callers. A guard for a state that no caller can produce is slop.

- Guard cascades: an overflow check that an earlier bound already dominates, NaN or Inf checks on a flag that is already validated, nil checks on values that cannot be nil.
- Inconsistent handling of bad input: one argument silently clamped (`warmup = max(warmup, 0)`) next to others that return an error.
- Cleanup for imagined crash states: sweeps of stale temp files, glob-safety asides, retries with no observed failure.
- `recover()` away from a goroutine or request boundary. `_ = f()` where the surrounding code returns that error. An error both logged and returned.
- A test for each guard that pins its error text. These tests keep the guard alive. Removing a guard is a fix only when it is unreachable, because an earlier check already rejects everything it would reject; its test then goes too. A redundant guard that runs first still decides which error the caller sees, so report it with the one-sentence proof.

### Type laundering

Go has no `as any`, but the same move exists: a value passes through a type that hides what it is.

- `any`, `interface{}`, `map[string]any` or `reflect` where the concrete type is known.
- A type that carries a different quantity so it fits an existing column: counts, bytes or rates stored in `time.Duration`. The conversion hides the unit from the compiler and from the reader.
- Narrowing or sign-changing conversions silenced with `//nolint:gosec` and a comment that asserts safety, instead of a type or check that proves it.
- Type assertions without `ok` on a non-fatal path, or `v, _ := x.(T)` that turns a type error into a zero value.
- Stringly-typed classification: a kind encoded in a label and parsed back later with `strings.HasSuffix` or slicing (`suffix[1:]`). The kind is known where the value is recorded; carry it as a typed value.

These are usually design findings. Report them; fix only the trivial ones.

### Redundant indirection

- Redundant intermediate variables or one-use helpers that add no domain meaning, remove no duplication and simplify no control flow.
- One function under several names: `queryStageRow(stage, rps)` and `queryDriverRow(qtype, rps)` whose bodies are both `rateRow(label, rps)`.
- A return value used as both a flag and data (a suffix string tested for `""` and then sliced).
- Capacity arithmetic for small bounded slices (`make(s, 0, len(a)*len(b)*(len(c)+1)+3)`). The formula drifts wrong. If a linter wants a capacity, a plain `len(x)` or a round bound is enough. A micro-optimization needs a benchmark.
- Magic constants with a claimed property (`odd and mutually prime`) where the library already takes the inputs directly.

### Speculative scaffolding and shims

- Compatibility shims, aliases, retries and fallback branches without a named shipped contract and a removal plan.
- Code shipped before its first use, kept alive by `//nolint:unused` or `//nolint:unparam` "consumed by the next PR". The linter is correct: the code belongs in the PR that uses it. Report it. Moving code between stacked PRs is not a trivial edit. If the stack keeps it on purpose, the reason must not name a branch.
- Extension points with no user in the diff: an interface with one implementation, a `map[string]string` bag that no production code writes, a one-member const block "one per bench", a new parameter that every caller passes the same value.

### Test slop

- Test comments that restate the test name (`// TestFooBar: foo bars.`).
- Assertions that recompute the code under test (`assert.Equal(t, max(res.a, res.b), res.elapsed)`). They pass when the formula is wrong.
- Tables that list every entry of a lookup table or schema. These detect change; they do not test behavior. Test the behavior that the table drives.
- Assertions on log-line text when the log line is not a contract.
- The same invariant block pasted into each test instead of one helper with `t.Helper()`.
- Long comments that defend a timing margin. A fake clock removes the margin; failing that, state it in one line.

A deleted test is lost coverage. Delete only a tautological test; report the others.

### Style drift

Naming, control flow, imports, formatting and other style that conflicts with the surrounding file. For Go, compare against the file and its package: error-string form (lowercase, no final punctuation, context prefix, `%w` wrapping), import grouping, literals versus named constants, `errors.New` versus `fmt.Errorf`, receiver names, and ASCII versus Unicode symbols (`×`, `→`) in comments.

### Review-round accretion

When the branch went through review rounds (`git log`, the previous pushed version, uncommitted edits on top of a pushed commit), compare the latest round against the one before it. Look for comments that grew a clause per round, a guard added to answer a hypothetical, and a test added to prove that guard. Fold the growth back into one statement of the invariant, or report it.

Also compare the commit message or PR description with the diff. After several rounds they often describe a constant, a limit or a flow that the code no longer has. Report each claim that the code does not back.

## What is not slop

Do not remove these:

- A comment that gives a unit, an invariant, a lock rule, or why the obvious alternative fails.
- Validation of user input at the boundary: CLI flags, config, network input.
- `//nolint` with a real reason about this code, such as `gosec` on a bound that `validate()` proved.
- An atomic temp-file-and-rename write for a file that a reader depends on after a crash.
- Code that looks odd but matches the surrounding package. The package sets the style.
- A pattern that a linter the repo enables asks for, such as a slice capacity for `prealloc`. Read `.golangci.yml` before you call it slop. If the value is wrong, report that.

## Examples

`references/examples.md` has before/after cases from a real Go branch. Read it when a case is borderline or you need to calibrate how hard to cut.
