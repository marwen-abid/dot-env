---
name: doc-comment-cleanup
description: >
  Rewrite doc comments so they read for a first-time reader of the current code: strip
  defensive/comparative framing ("does X rather than Y", "instead of", "unchanged", "no longer"),
  drop history and counterfactual asides, lead with purpose instead of narrating the call graph,
  and balance comment lengths across a struct's fields or a type's methods. Defaults to the
  currently staged diff; also runs over specific files or directories the user names. Use this
  skill whenever the user asks to clean up / tidy / de-robotify doc comments or godocs, fix
  "defensive" or "AI-sounding" comments, rebalance uneven docstrings, or says things like "the
  docs read robotic", "these comments keep defending choices", "make the godoc sound like a human
  wrote it", "clean up the comments in the staged diff", or "do that doc cleanup again". Also
  worth reaching for right after writing a batch of new code with doc comments, to normalize their
  voice before committing.
---

# Doc-comment cleanup

Rewrite doc comments (Go doc comments, docstrings, `///` blocks) so they read cleanly for someone
seeing the code for the first time. This does **not** touch behavior — it is a comment-only pass.
It exists because freshly-written docs, especially ones written while a change is in flight, tend
to pick up a defensive, historical, call-path-narrating voice that reads robotic. This skill resets
that voice.

The heart of the skill is the **voice** in the next section. Internalize it before you edit.

## The voice: write for a first-time reader of the current code

Hold one reader in mind for every sentence: someone who has never seen this code and does not know
its history. They are **not** a reviewer comparing your change to yesterday's version. They want to
know what the code *is* and what it *does*, right now. Everything below falls out of that one idea.

### 1. Describe the present, not the history

Cut anything that only makes sense to someone who saw the previous version — `unchanged`,
`no longer`, `used to`, `now does`, `still`, `as before`. The first-time reader has no "before" to
anchor those to, so they read as noise at best and confusing at worst.

```
// before
the sink receiving both the per-stage MetricSink signals (via WriteColdChunk, unchanged) and
the scheduler's observability signals

// after
the sink collects its per-stage MetricSink timings and the scheduler's observability metrics
```

### 2. State what it does, not what it does *instead of*

Kill the `X rather than Y` / `instead of Z` / `not a … but a …` shape in doc comments. It defends
the code against an alternative the reader never proposed — it reads as arguing with a ghost. Flip
each one into a positive statement of what actually happens.

```
// before
a genuinely missing pack surfaces as RawLedgers' clear open error instead of a coverage timeout.

// after
a missing pack then surfaces through RawLedgers as a clear open error.
```

(See the exception at the end for inline *correctness* comments — those are allowed to say "rather
than".)

### 3. If you give a *why*, make it a why about the design that exists

Ground the reason in the real behavior of the surrounding code, and let the consequence follow.
Never ask the reader to reason about a design you didn't build — a counterfactual ("a durable
catalog *would otherwise* skip finished work") drags them into a hypothetical world to justify the
real one.

```
// before
Fresh-per-run is what makes every run a clean backfill from empty (durable states would
otherwise self-skip finished work on a re-run)

// after
The catalog records completed work and skips it on re-run, so a fresh one per run keeps every
run a clean backfill from empty.
```

### 4. Lead with what the thing is and the problem it solves — don't narrate the call graph

Package and type docs especially. A reader wants the concept first, then the mechanism. A sentence
that just chains "component A calls B (which does C) and a D that aggregates the E signals F emits"
is a wiring diagram rendered as prose; it tells you the plumbing without ever telling you the point.

```
// before
Package bench implements the full-history ingestion benchmarks behind the bench-ingest
subcommand: drivers that run the PRODUCTION ingestion paths — backfill.RunBackfill (cold: chunk
freezes plus the cross-chunk txhash index builds, on the daemon's own scheduler) and the
daemon's hot ingestion loop — and a csvSink that aggregates the signals those paths emit.

// after
Package bench benchmarks full-history ingestion: the cold backfill that bulk-materializes past
ledgers at startup, and the hot loop that ingests the live stream as it advances.

A run drives the daemon's production ingestion code over a benchmark-controlled ledger source
and times it: cold calls backfill.RunBackfill, hot calls the production ingestion loop. Both
report their timings through the MetricSink and observability.Metrics interfaces; a csvSink
collects the signals and aggregates each run into percentile CSV reports.
```

### 5. Balance the docs across siblings

Within a struct's fields or a type's methods, comment length should track complexity, not land at
random. A six-line essay on one field sitting next to three undocumented fields is a smell in *both*
directions: the essay is usually hoarding implementation detail that belongs on the function that
owns it, and the bare fields usually need a line. Fill the gaps, trim the essays, and push deep
detail to where it lives.

In the real example, a struct had `Source` and `OutDir` undocumented while `ColdRoot` ran six
lines. The fix gave `Source`/`OutDir` one honest line each, and shrank `ColdRoot` to four by moving
the fresh-temp-catalog internals onto the `openScratchCatalog` helper that actually implements them.

### 6. Don't restate the name, and don't echo the type's doc on its fields

`validate validates the options` is pure noise. A doc earns its place only when it says something
the signature doesn't. That cuts both ways, though: an undocumented member sitting among documented
ones is its own imbalance (see #5) — so fill it, but with a *real* line. For a `validate` method,
`checks the flags and chunk range before runHot touches the filesystem` says *when* it runs, which
the name never told you.

### Length is not the enemy — defensiveness and imbalance are

A long comment that accurately explains genuinely subtle logic (a tricky concurrency invariant, a
non-obvious reconstruction of a value) earns its length. Keep it. You are removing **history,
hedging, counterfactuals, and call-graph narration** — not information. Never shorten an accurate
explanation just to hit a line count.

### The exception: inline correctness comments

An inline comment *inside a function body* that uses "rather than" / "instead of" to pin down why
the current code is shaped a certain way for correctness is describing the present code's reasoning,
not defending a past design — keep it. For example:

```
// Overflow-safe cap: compare against the range's span rather than adding a
// flag-supplied count to a ledger sequence.
```

The bans in #1–#3 are about **doc comments that argue with alternatives**. They are not about
implementation notes that record a real constraint the reader needs.

## Workflow

### Step 1 — Determine scope

- If the user named specific files or directories, use exactly those.
- Otherwise default to the **currently staged diff**: `git diff --cached --name-only`.
- If nothing is staged and the user named nothing, don't guess — tell them and ask what to clean
  (offer the unstaged diff or the branch diff as options).

Restrict to hand-written source files. Skip generated code (`*.pb.go`, `*_gen.go`, anything under
`vendor/`) and, unless asked, leave test files alone — the target is the production docs that ship.

Work on the doc comments **within** the target files. Prioritize the comments the diff added or
changed (those are why this skill was called), but if a neighboring comment in the same file has the
same problem, fix it too — consistency within a file matters more than a tidy diff.

### Step 2 — Reset your voice

Re-read "The voice" above and hold that first-time reader in mind. This is the palette cleanser:
you are switching out of "explain-my-change-to-a-reviewer" mode and into "describe-the-code-to-a-
newcomer" mode.

### Step 3 — Scan for tells

Grep the target files for the giveaway phrases. This is a lead generator, not a verdict — every hit
still needs judgment (especially "The exception: inline correctness comments" in the voice section).

```bash
grep -nE "rather than|instead of|unchanged|no longer|used to|would otherwise|as before|not a |now (does|returns|uses)" <files>
```

Balance problems (#5) and call-graph narration (#4) usually won't show up in grep — catch those by
reading each struct's field docs and each package/type doc directly.

### Step 4 — Rewrite

Edit the comments in place, applying the voice. This is comment-only: **never** change code,
identifiers, or behavior. A couple of Go-specific notes:

- Keep the language's doc idiom. Go doc comments begin with the identifier (`runCold benchmarks…`,
  `Tip reports…`) and use "reports whether" for boolean returns. In an unfamiliar language, glance
  at a couple of well-regarded doc comments nearby to match local tone.
- If a substantial, story-shaped **package** comment is sitting in an arbitrary file, consider
  moving it to `doc.go` (the Go convention for a real package doc). Leave the bare `package x`
  clause behind, and make sure no other file still carries a package comment (two would be a vet
  smell).

### Step 5 — Verify

Comment edits can still break the build: moving a package comment can trigger a duplicate/missing
package-comment vet warning, and a doc that no longer starts with the identifier trips some linters.
Run the repo's build + vet + formatter over the touched packages and fix anything that surfaces. For
Go:

```bash
go build ./<touched-package>/... && go vet ./<touched-package>/... && gofmt -l <files>
```

`gofmt -l` should print nothing; a listed file is unformatted.

### Step 6 — Report

Give a short per-file summary: what you changed and the one-line reason (which principle it was).
Call out anything you deliberately **kept** — e.g. a long-but-accurate explanatory doc, or an inline
correctness comment that reads like defensive framing but isn't — so the user knows it was a choice,
not an oversight. Don't dump full diffs unless the user asks.

## Language note

The principles are language-agnostic — they're about voice, not syntax. The examples and the idiom
notes are Go (godoc), because that's the common case here, but the same pass applies to Python
docstrings, JSDoc/TSDoc, Rustdoc, etc. Only Step 4's idiom bullet and Step 5's exact commands are
Go-specific; swap in the target language's conventions and toolchain.
