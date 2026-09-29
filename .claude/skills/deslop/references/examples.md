# Deslop examples (Go)

Cases from a real Go benchmark branch (a paced request dispatcher and its CSV report). Each case shows the slop, the reason it is slop, and the fix or the report line. "Fix" means trivial and behavior-neutral. "Report" means the author decides.

## Contents

1. Field comments that restate names and repeat an ownership rule
2. An essay where an invariant belongs
3. Code shipped ahead of its first use
4. A dominated guard and an inconsistent clamp
5. One function under several names
6. Stringly-typed rows and a laundered unit
7. Extension points with no user
8. Tautological tests and change detectors
9. Cleanup for an imagined crash
10. Review-round accretion
11. Keep: comments and checks that earn their place

---

## 1. Field comments that restate names and repeat an ownership rule

```go
type legRecord struct {
	// dispatched counts the measured requests that ran. Written by the
	// dispatch goroutine only.
	dispatched int
	// shed counts the measured requests dropped at a full maxInFlight. Written
	// by the dispatch goroutine only.
	shed int
	// errs counts the measured requests that returned an error. Written by the
	// request goroutines, under pacedLeg.mu.
	errs int
	// firstErr is the first request error recorded, "first" meaning first to
	// take the mutex. It is nil when no measured request failed; errs counts
	// them all. Written by the request goroutines, under pacedLeg.mu.
	firstErr error
}
```

Each comment restates the field name, and the ownership rule appears once per field. The struct is also embedded in a parent that owns `mu`, so the lock and the fields it guards are in different types.

Fix (comments only): drop the restatements. Keep what a name cannot say: `shed` means "dropped at a full cap".

Report: group the fields by owner in the struct that holds `mu`, with the rule written once:

```go
	// Owned by the dispatch goroutine.
	lags                         []time.Duration
	dispatched, shed, warmupShed int

	mu       sync.Mutex // guards the fields below
	samples  []cellSample
	errs     int
	firstErr error
```

## 2. An essay where an invariant belongs

```go
// maxLegRequests caps a leg's measured positions. A measured request is
// retained twice. The leg holds 40 bytes (a 32-byte cellSample plus an 8-byte
// dispatch lag). ... Sink series grow by append, so capacity can be about 25%
// over length, and a grow holds the old and the new array for a short time.
// At the ceiling of 1e8 positions, the leg holds about 4 GB. The sink holds
// 6 GB (8 GB for txhash) with that slack, plus up to 1.6 GB while one series
// grows. ... 1e8 positions is about 2.7 hours at 10k rps, or 11 days at 100 rps.
const maxLegRequests = 100_000_000
```

The byte arithmetic goes stale the next time `cellSample` changes size. The reader needs the limit and why it exists.

Fix:

```go
// maxLegRequests caps a leg's measured positions so that one run's samples
// stay within a few GB of memory (about 2.7 hours at 10k rps).
const maxLegRequests = 100_000_000
```

## 3. Code shipped ahead of its first use

```go
queryTypeTxPage = "txpage" //nolint:unused // consumed by bench-query/02-read-path, the next PR in this stack

//nolint:unparam // stage is set by the txhash body in bench-query/02-read-path, the next PR in this stack
func timed(stage sampleStage, fn func() (int, error)) (cellSample, error) {
```

The linter says the code is dead in this PR, and the suppression names a branch that will not exist after merge.

Report: move the constants to the PR that uses them; add the `stage` parameter when the first caller passes a non-zero value. Do not delete the code yourself: the next PR in the stack depends on it.

## 4. A dominated guard and an inconsistent clamp

```go
	warmup = max(warmup, 0)
	measured := measuredRequests(rps, duration)
	...
	if warmup > math.MaxInt-measured {
		return legResult{}, errors.New("paced leg warmup plus measured request count overflows an int")
	}
	if warmup > maxLegRequests-measured {
		return legResult{}, fmt.Errorf("paced leg schedules more than %d positions: ...", maxLegRequests)
	}
```

An earlier check bounds `measured` by `maxLegRequests`, so the second guard rejects every input that the first one rejects, and `warmup+measured` cannot overflow once it passes. A table test pins the first guard's message; that test is what keeps the guard alive. Separately, a negative `warmup` is clamped while a bad rate or duration returns an error.

Report both. The redundant guard runs first, so removing it changes which message a caller sees for a huge `warmup`; give the one-sentence proof and let the author drop it with its test row. Rejecting the clamp also changes behavior. If the order were reversed, the redundant guard would be unreachable and removing it would be a fix.

## 5. One function under several names

```go
func rateRow(label string, rps float64) string { return label + "_r" + formatRPS(rps) }

func queryTotalRow(rps float64) string              { return rateRow(queryRowTotalPrefix, rps) }
func queryServiceRow(rps float64) string            { return rateRow(queryRowServicePrefix, rps) }
func queryStageRow(stage string, rps float64) string { return rateRow(stage, rps) }
func queryDriverRow(qtype string, rps float64) string { return rateRow(qtype, rps) }
```

`queryStageRow` and `queryDriverRow` are `rateRow` renamed. A reader must open each one to learn that.

Fix: call `rateRow` directly at their one call site each. `queryTotalRow` and `queryServiceRow` at least bind a constant; leave them unless the surrounding code already calls `rateRow` for the same kind of row.

## 6. Stringly-typed rows and a laundered unit

```go
func keepsZeroSamples(file, label string) bool {
	return (file == fileDriver || file == fileQueryAccounting) &&
		(strings.HasSuffix(label, driverLegLagSuffix) ||
			driverLegCountSuffix(label) != "" ||
			strings.HasSuffix(label, driverLegDrainSuffix) ||
			strings.HasSuffix(label, driverLegRPSSuffix))
}

	case count != "":
		logger.Infof("%-10s %-12s n=%-7d %s=%d", fileName, r.name, r.n, count[1:], r.items)

	// from the test: a target rate of 10 rps, recorded as a time.Duration
	sink.observe(fileQueryAccounting, name, 10*milliPerUnit, 0)
```

The row's kind (latency, count, rate, bytes) is known when it is recorded. The code throws it away, parses it back from the label with suffix tests, and stores rates, counts and bytes in `time.Duration` fields so they fit the latency columns.

Report (design): record the kind with the sample, or give non-latency rows their own type. Not a trivial fix.

## 7. Extension points with no user

```go
type runEnv struct {
	OutDir string
	// Extra is written by the run goroutine only and read once run returns.
	Extra map[string]string
}

// Temp-dir prefixes for scratch catalogs, one per bench.
const (
	scratchPrefixIngest = "bench-ingest-catalog-"
)
```

No production code in the diff writes `Extra`. The const block has one member, and the new `prefix` parameter has one value at every call site.

Report: add them with their first user.

## 8. Tautological tests and change detectors

```go
	assert.Equal(t, max(res.offered, res.wall), res.elapsed)
	assert.Equal(t, max(res.wall-res.offered, 0), res.drain)
```

These copy the production formula, so they pass when the formula is wrong. Assert concrete values from a controlled input instead (a later table test in the same file already does this).

```go
func TestKeepsZeroSamples(t *testing.T) {
	for _, tc := range []struct{ file, label string; want bool }{
		{fileDriver, "pace_lag", true},
		{fileDriver, "txhash_r300_lag", true},
		// ... 20 more rows, one per suffix ...
	}
```

The table lists the predicate's own cases back to it. Test the behavior it drives: a zero-valued lag row is written, and a zero-valued latency row is dropped. The same file already has that test.

Report both. Deletion is fix-worthy only for the pure copy of the formula.

## 9. Cleanup for an imagined crash

```go
	// A kill between CreateTemp and Rename leaves the temp file; the next write
	// removes it. The match is on the entry name only, because outDir can hold
	// glob metacharacters.
	if entries, err := os.ReadDir(outDir); err == nil {
		for _, e := range entries {
			if ok, _ := filepath.Match(invocationTempPattern, e.Name()); ok {
				_ = os.Remove(filepath.Join(outDir, e.Name()))
			}
		}
	}
```

This defends a benchmark's metadata file against a leftover that nothing reads, and it ignores every error it meets. The temp-and-rename write before it is fine.

Report: remove the sweep and its test, unless a real run left such files.

## 10. Review-round accretion

Between two review rounds, the `maxLegRequests` comment grew from 11 to 15 lines. Each `legRecord` field gained an ownership sentence. A `minLegRPS` guard, a `Status` field and a stale-temp-file sweep appeared, each with new tests. The dispatch loop itself changed in one place.

Report: point at the growth and propose the one-line invariant for each comment. For each new guard or field, ask whether it answers an observed failure or a hypothetical, and name the hypothetical.

## 11. Keep: comments and checks that earn their place

```go
// launch runs position pos's request on its own goroutine when a slot is free
// and sheds it otherwise. A measured position records its lag, now minus due,
// whether or not it is shed.
```

This states an invariant that the report depends on: shed positions still count in the lag distribution. Keep it.

```go
	//nolint:gosec // validate() proved StartChunk+NumChunks-1 <= maxChunkID
	end := opts.StartChunk + chunk.ID(uint32(opts.NumChunks-1))
```

The suppression names the proof and where it lives. Keep it.

```go
	if rps <= 0 || math.IsNaN(rps) || math.IsInf(rps, 0) {
		return legResult{}, fmt.Errorf("paced leg needs a positive finite rate, got %v", rps)
	}
```

The rate comes from a `--target-rps` flag. This is boundary validation. Keep it.
