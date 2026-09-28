# Artifact spec

The page is a **review dossier**: a utilitarian document with real typographic hierarchy, not a landing page. Start from `assets/template.html` (already theme-aware, already has the diff renderer and severity chips). Replace the marked regions; keep the CSS unless the repo has its own design tokens.

## Page structure

```
<title>                   — a NAME, 2–4 words, specific to this change ("Ledger Loans"),
                            never "PR 961 review" or "Changeset explanation"
header                    — name; one-line "how X does Y — and whether it is ready"; repo · branch → base · files · +/− · base SHA
nav (sticky)              — one entry per group + Story / Tests / Verdict
§ The story               — problem (with the number) · the fix in one sentence · before/after table if numbers exist ·
                            one "idea to hold" aside naming the single concept every group builds on
§ Group 1 … N             — see rhythm below
§ Tests                   — table: test · what it proves · assessment (ok / warn)
                            + one paragraph of hygiene facts (pool identity, sleeps, skips, duplicated helpers, file sizes)
§ Review verdict          — verdict box (decision + one paragraph) · verification rows · findings table · "Is it worth including?"
                            (omitted entirely with --no-verdict; the Tests section stays)
```

## The per-group rhythm

Every group has exactly these four beats, in this order. The reader learns the rhythm in group 1 and then scans.

1. **Why** (1–3 sentences, bold lead-in "Why.") — the problem this mechanism solves and, where possible, the number. Present tense, final state: "The old X allocated per call. It is deleted and replaced by Y, which…".
2. **Diff** — one or more `<pre class="diff">` blocks, each with a file header line. Show the hunks that *are* the mechanism; elide the rest with a `note` line (`… bounds check unchanged …`). A group's diff should fit in one screen where possible; two at most. Final state only — if the PR's commits moved a line twice, show its landing spot.
3. **Context you can't see in the diff** (aside, accent) — facts the reader needs and cannot get from the hunks: what a library does with the bytes, what a lock actually guards, which invariant makes a removed check safe, what the deleted wrapper used to do, what else in flight touches these files. Every sentence here is something you verified; write it so the reader could re-verify ("`UnmarshalBinary` goes through `bytes.NewReader` and a stream decoder that `make`s every opaque field").
4. **My take** (aside, muted) — an opinion with its reason. Say when it is right and *why* it holds ("the callback runs after `getLedgerInto` returns, outside the lock — that separation is the load-bearing detail"). Name the single most important risk for this group and its fix. If a finding in the verdict originates here, state it here first in plain words and label it ("this group carries the PR's one **Required** production item").

Group heading: a number plus a verb-phrase title stating what the code now does. The number encodes reading order (the story is a sequence), which is why it's allowed.

Files line under the heading: the files this group touches, monospace, muted.

## Diff rendering rules

The template's `pre.diff` uses `white-space: normal` on the container and `white-space: pre` on each `span.l` line. This is deliberate: with block-level line spans inside a `<pre>`, the newline between spans is *also* rendered and every line double-spaces. Keep the container's `white-space: normal`.

Line classes: `add`, `del`, `hunk` (the `@@` marker — write it as a plain-English location, `@@ GetLedgerRaw → WithLedger @@`, not raw line ranges), `note` (italic elision marker), and unclassed for context. HTML-escape `<`, `>`, `&` in code. Prefix `+`/`-`/space exactly as a diff would so the reader's eye works as usual.

Never include more than ~60 lines in one block. If the mechanism is longer, the group is probably two groups.

## Writing rules

### Write for the reader who has never opened the repo

The page's audience is a reviewer with no codebase context. The failure mode to guard against is a sentence that is correct, dense, and unreadable because it uses the codebase's own vocabulary as if the reader already had it — e.g. *"the response envelope reports the window's oldest/latest close times, and a `closeTime == 0` sentinel meant unknown, so any window edge sitting on an epoch-closed ledger fully decoded a ledger twice per request"*. Five undefined terms, effect before mechanism, zero comprehension. Rules:

1. **One new term per sentence, defined where it first appears.** Codebase words — envelope, window, stamp, tier, chunk, freeze, sentinel, loan — are jargon to this reader. Either define the term in the same sentence ("the close time — the Unix timestamp when the network finalised the ledger") or use the plain phrase instead. If a term recurs across groups, define it once in The story (a short "words this page uses" aside is fine) and reuse it consistently.
2. **Concrete before abstract.** Name the actual thing first, then the label: "four fields on every reply: the sequence and close time of the oldest and newest ledgers the node has" *before* "the envelope". A reader can hold an abstraction only after seeing an instance.
3. **Mechanism → flaw → cost, in that order.** What the code did; why that was wrong; what it cost (with the number). Stating the consequence first ("a worse leak") before the mechanism forces the reader to hold an unexplained claim.
4. **Prefer the plain word.** "A value used as a flag" not "sentinel"; "the oldest and newest ledgers the node still has" not "window edges"; "kept in memory" not "stamped". Use the codebase's word only when the reader will meet it in the diff and needs to recognise it — then introduce it as *the code calls this X*.
5. **Twice the words is the right trade.** A defined sentence is longer than a dense one. Brevity is for the reader who has context; this reader doesn't. Cut ideas, not definitions.
6. **Read it back as the newcomer.** Before publishing, reread The story and every Why paragraph and ask, per sentence: could someone who has never seen this repo say what each noun refers to? If not, fix the sentence — that check is cheaper than the user asking "what are you talking about?".

### General

- Present tense, final state. No "in commit 3 the author then…".
- Specific over general. "~18 MB per call at 200 rps OOM-killed the daemon" beats "high memory usage".
- Name the load-bearing line. Every take should point at the one line or ordering that makes the group correct — that is what a reviewer will want to stare at.
- Praise is information only when specific. "Correct and well-bounded" is filler; "the clip-at-the-choke-point enforces a property for three APIs with one line and fixes a latent bug nobody had hit" is a review.
- Prior review threads are excluded from findings and acknowledged once, in the verdict box ("N inline threads, all answered; each fix verified present in the final diff. Nothing below repeats them.").
- Keep running text under ~70ch; tables and diffs may run full width inside their own scroll container.

## Severity vocabulary (findings table)

| Chip | Meaning | The author must… |
|---|---|---|
| **Critical** | Security, data loss, corruption, broken functionality | fix before merge; blocks |
| **Required** | Correctness or a real maintenance hazard; a test that doesn't guard what it claims | fix before merge |
| **Optional** | Worth doing, not blocking | consider |
| **Nit** | Style, placement, naming | may ignore |
| **FYI** | Context for the reviewer; nothing to change | nothing |

Order findings by leverage: Critical, Required, then Optional, Nit, FYI. Each row: chip · where (file + function or ~line) · finding → fix. One structural problem and ten nits means the structural problem *is* the review — don't let it drown.

Presumptive blockers to look for and propose the simpler design for: a refactor that relocates complexity instead of reducing it; a change that grows an already-oversized file with no decomposition; feature logic added to a shared module; a near-duplicate of an existing canonical helper; a silent fallback hiding an unclear invariant; a hand-maintained enumeration of an external type's fields.

## The verdict box

- Heading: the decision — "Approve", "Approve, with the N Required fixes before merge", "Request changes", or "Not yet — split it".
- One paragraph: why the production code is (or isn't) sound, and where the weaknesses actually are.
- Verification rows (`dl.kv`): Build / vet · Tests (incl. race, flakiness, and any timing anomaly) · Lint (tool version, new vs pre-existing) · Changelog · Dead code · Prior review. Fill from the verifier's file; mark anything still running as "in progress" and redeploy when it lands.
- "Is it worth including?" — one paragraph answering the reviewer's real question: what it buys, what it costs in concepts, whether the risk is present-tense or drift, and the landing order if other work is in flight.

## Redeploy discipline

Publish once with an `icon` and a `label`; every later fix redeploys the *same file path* (same URL) with a short `label` and `note`. When a subagent result lands after publication, patch the row and redeploy — don't wait to batch.
