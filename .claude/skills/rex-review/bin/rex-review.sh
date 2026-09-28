#!/usr/bin/env bash
# Orchestrator: brief -> lenses -> mechanical gate -> adjudicator -> report
# usage: rex-review.sh --repo DIR [--base REF] [--head REF] [--pr N] [--lenses a,b] [--repro]
#                      [--lens-model M] [--adj-model M] [--run-dir DIR] [--in-place] [--keep-tree] [--max-diff-lines N]
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
need git; need jq; need claude

REPO="" BASE="" HEAD="HEAD" PR="" LENSES="${REX_LENSES:-correctness}" REPRO=0 RUN="" IN_PLACE=0 KEEP=0
LENS_MODEL="${REX_LENS_MODEL:-sonnet}" ADJ_MODEL="${REX_ADJ_MODEL:-opus}" MAX_DIFF="${REX_MAX_DIFF_LINES:-4000}"
while [ $# -gt 0 ]; do case "$1" in
  --repo) REPO="$2"; shift 2;; --base) BASE="$2"; shift 2;; --head) HEAD="$2"; shift 2;; --pr) PR="$2"; shift 2;;
  --lenses) LENSES="$2"; shift 2;; --repro) REPRO=1; shift;; --run-dir) RUN="$2"; shift 2;;
  --lens-model) LENS_MODEL="$2"; shift 2;; --adj-model) ADJ_MODEL="$2"; shift 2;;
  --in-place) IN_PLACE=1; shift;; --keep-tree) KEEP=1; shift;; --max-diff-lines) MAX_DIFF="$2"; shift 2;;
  -h|--help) sed -n '2,5p' "$0"; exit 0;;
  *) die "unknown arg $1";; esac; done
[ -n "$REPO" ] || REPO="$(pwd)"
REPO="$(cd "$REPO" && git rev-parse --show-toplevel)"
NAME="$(repo_name "$REPO")"

# resolve base/head
if [ -n "$PR" ] && [ -z "$BASE" ]; then
  need gh
  BASE="origin/$(cd "$REPO" && gh pr view "$PR" --json baseRefName -q .baseRefName)"
  [ "$HEAD" = "HEAD" ] && HEAD="$(cd "$REPO" && gh pr view "$PR" --json headRefOid -q .headRefOid)"
fi
if [ -z "$BASE" ]; then
  BASE="$(git -C "$REPO" symbolic-ref -q --short refs/remotes/origin/HEAD 2>/dev/null || true)"
  [ -n "$BASE" ] || BASE="$(git -C "$REPO" rev-parse --verify -q origin/main >/dev/null && echo origin/main || echo origin/master)"
fi
HEAD_SHA="$(git -C "$REPO" rev-parse "$HEAD")"

TS="$(date +%Y%m%d-%H%M%S)"
RUN="${RUN:-$REX_HOME/runs/$NAME/$TS-${HEAD_SHA:0:8}}"
mkdir -p "$RUN"
START="$(date +%s)"
log "run: $RUN"

# tree: detached worktree at HEAD so the lens/adjudicator read the exact reviewed code
TREE="$REPO"
if [ "$IN_PLACE" = 0 ]; then
  TREE="$RUN/tree"
  git -C "$REPO" worktree add --detach -q "$TREE" "$HEAD_SHA" 2>>"$RUN/worktree.log" || die "worktree add failed (see $RUN/worktree.log)"
  cleanup() { if [ "$KEEP" = 0 ]; then git -C "$REPO" worktree remove --force "$TREE" >/dev/null 2>&1 || true; fi; }
  trap cleanup EXIT
fi

"$REX_HOME/bin/rex-brief.sh" --repo "$REPO" --base "$BASE" --head "$HEAD_SHA" --out "$RUN" --tree "$TREE" ${PR:+--pr "$PR"}
DIFF_LINES="$(jq .diff_lines "$RUN/meta.json")"
if [ "$DIFF_LINES" -gt "$MAX_DIFF" ]; then
  log "diff has $DIFF_LINES lines > $MAX_DIFF; skipping LLM stages (raise with --max-diff-lines)"
  echo '{"findings":[]}' > "$RUN/candidates.json"; echo '{"verdicts":[]}' > "$RUN/verdicts.json"; : > "$RUN/dropped.jsonl"
  echo '{"findings":[]}' > "$RUN/all_findings.json"
  "$REX_HOME/bin/rex-report.sh" --run "$RUN"; jq '. + {skipped:"diff too large"}' "$RUN/summary.json" > "$RUN/.s" && mv "$RUN/.s" "$RUN/summary.json"
  exit 0
fi
if [ "$DIFF_LINES" -eq 0 ]; then log "empty diff"; fi

# lenses run concurrently
pids=""
for L in $(printf '%s' "$LENSES" | tr ',' ' '); do
  "$REX_HOME/bin/rex-lens.sh" --run "$RUN" --tree "$TREE" --lens "$L" --model "$LENS_MODEL" &
  pids="$pids $!"
done
for p in $pids; do wait "$p" || log "a lens failed"; done

"$REX_HOME/bin/rex-validate.sh" --run "$RUN" --tree "$TREE"
"$REX_HOME/bin/rex-adjudicate.sh" --run "$RUN" --tree "$TREE" --model "$ADJ_MODEL" $([ "$REPRO" = 1 ] && echo --repro)
"$REX_HOME/bin/rex-report.sh" --run "$RUN"
jq --argjson secs "$(( $(date +%s) - START ))" '. + {wall_secs:$secs}' "$RUN/summary.json" > "$RUN/.s" && mv "$RUN/.s" "$RUN/summary.json"
log "done in $(( $(date +%s) - START ))s: $(jq -c '{raw_findings,candidates,surfaced,cost_usd}' "$RUN/summary.json")"
echo "$RUN"
