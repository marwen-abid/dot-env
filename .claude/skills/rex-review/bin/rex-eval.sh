#!/usr/bin/env bash
# Run the pipeline over the eval sets and print precision/recall.
# usage: rex-eval.sh --repo DIR [--set clean|fixes|all] [--limit N] [--lenses a,b] [--tag label] [--dry-run]
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
need git; need jq
REPO="" SET="all" LIMIT=1000 LENSES="${REX_LENSES:-correctness}" TAG="" DRY=0 EXTRA=()
while [ $# -gt 0 ]; do case "$1" in
  --repo) REPO="$2"; shift 2;; --set) SET="$2"; shift 2;; --limit) LIMIT="$2"; shift 2;; --lenses) LENSES="$2"; shift 2;;
  --tag) TAG="$2"; shift 2;; --dry-run) DRY=1; shift;; --) shift; EXTRA=("$@"); break;;
  *) die "unknown arg $1";; esac; done
[ -n "$REPO" ] || die "usage: --repo DIR"
REPO="$(cd "$REPO" && git rev-parse --show-toplevel)"; NAME="$(repo_name "$REPO")"
EV="$REX_HOME/evals/$NAME"; [ -d "$EV" ] || die "no eval set for $NAME; run rex-eval-mine.sh first"
TS="$(date +%Y%m%d-%H%M%S)"; RES="$REX_HOME/evals/results/$NAME/$TS${TAG:+-$TAG}"; mkdir -p "$RES"
LINE_TOL="${REX_HIT_TOLERANCE:-15}"

run_case() { # kind id base head [fixjson]
  local kind="$1" id="$2" base="$3" head="$4" fixjson="${5:-}"
  local run="$RES/$kind-$id"
  if [ "$DRY" = 1 ]; then echo "would run $kind $id $base..$head"; return; fi
  "$REX_HOME/bin/rex-review.sh" --repo "$REPO" --base "$base" --head "$head" --lenses "$LENSES" --run-dir "$run" "${EXTRA[@]}" >/dev/null 2>"$run.log" \
    || log "case $kind/$id failed (see $run.log)"
  [ -f "$run/summary.json" ] || echo '{"surfaced":0,"raw_findings":0,"candidates":0,"cost_usd":0,"surfaced_locs":[],"error":true}' > "$run/summary.json"
  if [ "$kind" = fix ]; then
    jq --slurpfile fx "$fixjson" --argjson tol "$LINE_TOL" '
      ($fx[0].regions) as $r
      | .file_hit = ([.surfaced_locs[] | select($r[.file] != null)] | length > 0)
      | .line_hit = ([.surfaced_locs[] | . as $l | select($r[$l.file] != null and ([$r[$l.file][] | select((. - $l.line)|fabs <= $tol)] | length > 0))] | length > 0)
      | .kind="fix" | .id=$fx[0].fix | .subject=$fx[0].subject' "$run/summary.json"
  else
    jq --arg id "$id" '.kind="clean" | .id=$id | .fp = .surfaced' "$run/summary.json"
  fi
}

: > "$RES/cases.jsonl"
n=0
if [ "$SET" = all ] || [ "$SET" = clean ]; then
  while IFS=$'\t' read -r base head dl subject; do
    [ "$n" -ge "$LIMIT" ] && break; n=$((n+1))
    log "clean ${head:0:8}: $subject"
    run_case clean "${head:0:8}" "$base" "$head" | jq -c --arg s "$subject" '. + {subject:$s}' >> "$RES/cases.jsonl"
  done < "$EV/clean.tsv"
fi
n=0
if [ "$SET" = all ] || [ "$SET" = fixes ]; then
  for fj in "$EV"/fixes/*.json; do
    [ -f "$fj" ] || continue
    [ "$n" -ge "$LIMIT" ] && break; n=$((n+1))
    intro="$(jq -r .intro "$fj")"
    log "fix $(jq -r '.fix[:8]' "$fj") <- intro ${intro:0:8}: $(jq -r .subject "$fj")"
    run_case fix "${intro:0:8}" "$intro^" "$intro" "$fj" >> "$RES/cases.jsonl"
  done
fi
[ "$DRY" = 1 ] && exit 0

jq -s '
  def avg: if length>0 then add/length else 0 end;
  (map(select(.kind=="clean"))) as $c | (map(select(.kind=="fix"))) as $f
  | {clean_cases: ($c|length), clean_prs_with_fp: ([$c[]|select(.fp>0)]|length), total_fp: ([$c[]|.fp]|add//0),
     fp_per_pr: ([$c[]|.fp]|avg),
     fix_cases: ($f|length), recall_file: ([$f[]|select(.file_hit)]|length), recall_line: ([$f[]|select(.line_hit)]|length),
     lens_raw_total: (map(.raw_findings)|add//0), candidates_total: (map(.candidates)|add//0), surfaced_total: (map(.surfaced)|add//0),
     cost_usd: (map(.cost_usd)|add//0), wall_secs: (map(.wall_secs//0)|add), errors: ([.[]|select(.error)]|length)}' "$RES/cases.jsonl" > "$RES/metrics.json"
{
  echo "# rex eval: $NAME  ($TS${TAG:+ · $TAG})  lenses=$LENSES"; echo
  jq -r '"- Clean set: \(.clean_cases) PRs, \(.total_fp) false positives, \(.clean_prs_with_fp) PRs with ≥1 FP (\(if .clean_cases>0 then (100*.clean_prs_with_fp/.clean_cases|round) else 0 end)%)\n- Fix set: \(.fix_cases) cases, recall file-level \(.recall_file)/\(.fix_cases), line-level (±'"$LINE_TOL"') \(.recall_line)/\(.fix_cases)\n- Funnel: \(.lens_raw_total) raw → \(.candidates_total) after gate → \(.surfaced_total) surfaced\n- Cost: $\(.cost_usd*100|round/100), wall \(.wall_secs)s, errors \(.errors)"' "$RES/metrics.json"
  echo; echo "## Cases"; echo; echo "| kind | id | subject | raw | cand | surfaced | hit | cost |"; echo "|---|---|---|---|---|---|---|---|"
  jq -r '"| \(.kind) | \(.id[:8]) | \(.subject[:60]|gsub("\\|";"/")) | \(.raw_findings) | \(.candidates) | \(.surfaced) | \(if .kind=="fix" then (if .line_hit then "line" elif .file_hit then "file" else "miss" end) else (if .fp>0 then "FP" else "ok" end) end) | \(.cost_usd*100|round/100) |"' "$RES/cases.jsonl"
} > "$RES/report.md"
cat "$RES/report.md"
