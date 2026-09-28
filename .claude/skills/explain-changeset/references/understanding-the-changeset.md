# Understanding the changeset

The sequence below is what separates a page that *explains* a change from one that *narrates* its diff. Do it before forming any opinion. It is adapted from the context-gathering half of a full code review; the judgment half (five-axis review, severity, remedies) lives in `artifact-spec.md`.

## Step 1 — Intent, in the author's words

Pull the PR body, the commit subjects, and any linked issue or design doc. Extract four things and keep them verbatim where you can:

1. **The problem.** What was broken, slow, or missing — with the number that made it matter (an OOM at N rps, a p99, a byte count). If the author gives no number, say so on the page; it is itself a review signal.
2. **The fix in one sentence.** If you can't write it, you don't understand the change yet — keep reading.
3. **The author's own risks and follow-ups.** They usually name the seams ("rebases over #902 with two known conflicts", "10 ms objective not met"). Those become "context you can't see" items or FYIs, not discoveries.
4. **The compatibility story.** What else is in flight that touches the same files; what landing order the author proposes.

A good PR description is most of the page's opening section. A poor one means you write it, and the page says the description should be improved.

## Step 2 — Prior review, so you don't repeat it

```
gh api repos/O/R/pulls/N/comments --paginate   # inline threads, with in_reply_to_id
gh api repos/O/R/pulls/N/reviews               # review bodies + states
gh api repos/O/R/issues/N/comments             # top-level conversation
```

For each thread: who raised it, on which file:line, what the author replied, and whether the fix is actually present in the final diff (grep for the test name or the doc wording the author cites). Threads from bots (Copilot, CodeRabbit, etc.) count — a finding you repeat from a bot looks like you didn't read the PR. Also read the top-level conversation for force-push notes: "replaced the v1 design with v2" tells you which earlier threads are moot, and it tells you the page must describe v2 only.

Record the count and disposition; the page states it in one line.

## Step 3 — Tests first

Tests are the author's own statement of what the change guarantees. Before the production code:

- List the new and renamed test functions (`grep -n '^func Test' <test diff>`); their names are the claimed behaviours.
- Note deleted tests and what replaced them.
- Hand the test diff to the **test-auditor** subagent with the claimed behaviours as its checklist. You want back: for each behaviour, the test that pins it and whether it would actually fail on regression.

You will use the audit twice: the page's Tests table, and the "My take" on each group (a group whose guarantee is untested gets that said in its take, not buried in a findings table).

## Step 4 — Production diff, by hand

Read it in slices per mechanism, lowest layer first. `git diff BASE..HEAD -- <files of one group>` per slice; never the whole thing at once. While reading, keep three running lists:

**(a) New concepts.** Every type, interface method, pool, lock scope, sentinel, flag, or invariant a reader must now hold. If the count went up, the page must justify each one.

**(b) Deleted concepts.** Every wrapper type, helper, interface method, or sentinel removed. Deletions are the strongest evidence a refactor reduced rather than relocated complexity — count them and say so.

**(c) Out-of-diff dependencies.** Every place where the diff's correctness rests on a fact the diff does not show. Typical shapes:

- A library call's *copy vs alias* behaviour (does `Unmarshal` retain input bytes? does `Decode(dst, src)` reuse `dst`'s capacity?). Look in the module cache: `$(go env GOMODCACHE)/<module>@<version>/…`.
- A lock's *scope* — what it actually guards (lifecycle only? data?), who takes the write side, whether a callback runs inside or outside it.
- A type's *field list* when code enumerates fields by hand (a hand-maintained copy of a struct's slice fields is a hazard the moment the struct is external).
- An *invariant established elsewhere* ("seq is always ≥ 2 here because the floor chunk starts at 2") that makes a removed check safe.
- A *routing or snapshot* assumption ("the view is immutable for the request, so the tier decision can't race a freeze").
- An *error-mapping* contract ("`ErrNotFound` on an exact index must surface as `ErrInconsistent`") that the refactor must preserve.

List (c) is the most valuable output of this step: each item is either a "Context you can't see" paragraph (once you verify it) or a question for the **risk-auditor** (if verifying it is a sweep). Verify the cheap ones yourself with one `grep`/`sed`; delegate the rest.

Also note, for the page's verdict:

- Does the change keep the module boundaries it found (or does a lower layer now document itself by pointing at a higher one)?
- Is feature logic leaking into a shared module?
- Does any file grow past ~1,000 lines, or is a >1,000-line file grown further?
- Does a new conditional bolt onto an unrelated flow (a missing abstraction), or do repeated conditionals on the same shape appear (a missing dispatcher)?

## Step 5 — Group into a story

Order the groups so each one's *reader* is prepared by the previous one. A dependable default is bottom-up: storage primitive → the store that uses it → the router/plumbing → the consumer → the contract or type change that made the rest possible → tests. Six groups is typical; four is fine for a small change; eight is the ceiling before the page stops being one story.

For each group, before you write anything, you should be able to fill in:

- **Why** — the problem this mechanism solves, one or two sentences, with the number where there is one. Written in the order mechanism → flaw → cost, and with every codebase term either defined in place or already defined in The story. Keep a running list of the terms you have introduced so far; a Why that uses one you haven't is the sentence the reader will stop on.
- **The key hunks** — the 10–60 lines that *are* the mechanism. Trim the rest with `… n lines unchanged …`.
- **Context you can't see** — the verified (c) items for this group.
- **My take** — is it right? is it the simplest version? what would you change? what does it depend on that could drift? A take that only says "clean" has failed; a take that names the load-bearing line and says why it holds is what the reviewer came for.

If a group's take has nothing to say, the group is probably plumbing that belongs folded into its neighbour.
