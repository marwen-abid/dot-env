#!/usr/bin/env bash
# Join candidates + verdicts. Output: report.md, surfaced.json, rejected.jsonl, summary.json
# usage: rex-report.sh --run RUN_DIR
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
need jq
RUN=""
while [ $# -gt 0 ]; do case "$1" in --run) RUN="$2"; shift 2;; *) die "unknown arg $1";; esac; done
[ -n "$RUN" ] || die "usage: --run"
MIN_SEV="${REX_MIN_SEVERITY:-low}"

jq --slurpfile v "$RUN/verdicts.json" --arg minsev "$MIN_SEV" '
  def rank: {critical:0, high:1, medium:2, low:3}[.];
  ($v[0].verdicts | map({key:.id, value:.}) | from_entries) as $vs
  | [.findings[] | . as $f | ($vs[$f.id] // {}) as $vd
     | $f + {verdict: ($vd.verdict // "REJECTED"), final_severity: ($vd.severity // $f.severity),
             evidence: ($vd.evidence // ""), reason: ($vd.reason // ""), reproduced: ($vd.reproduced // false),
             suggested_fix: ($vd.suggested_fix // "")}]
  | {surfaced: ([.[] | select(.verdict != "REJECTED" and ((.final_severity|rank) <= ($minsev|rank)))] | sort_by(.final_severity|rank)),
     rejected: [.[] | select(.verdict == "REJECTED" or ((.final_severity|rank) > ($minsev|rank)))]}' \
  "$RUN/candidates.json" > "$RUN/.report.json"
jq '{findings: .surfaced}' "$RUN/.report.json" > "$RUN/surfaced.json"
jq -c '.rejected[] | {id, file, line, severity, verdict, claim, reason}' "$RUN/.report.json" > "$RUN/rejected.jsonl"

META="$RUN/meta.json"
{
  echo "# Rex review: $(jq -r .name "$META") @ $(jq -r '.head[:10]' "$META")"
  echo
  echo "$(jq '.surfaced|length' "$RUN/.report.json") finding(s) surfaced. $(jq '.rejected|length' "$RUN/.report.json") rejected by the adjudicator, $(wc -l < "$RUN/dropped.jsonl" | tr -d ' ') dropped by the mechanical gate."
  echo
  if [ "$(jq '.surfaced|length' "$RUN/.report.json")" = 0 ]; then
    echo "No verified defects."
  else
    jq -r '.surfaced[] | "## [\(.final_severity|ascii_upcase)] \(.verdict)\(if .reproduced then " (reproduced)" else "" end): \(.claim)\n\n`\(.file):\(.line)` — \(.category), lens `\(.lens)`, confidence \(.confidence)\n\n**Trigger path.** \(.trigger_path)\n\n**Evidence.** \(.evidence)\n\n**Falsifying test.** \(.falsifying_test)\n\(if .suggested_fix != "" then "\n**Suggested fix.** \(.suggested_fix)\n" else "" end)"' "$RUN/.report.json"
  fi
  echo
  echo "---"
  echo "Cost: \$$(jq -s 'map(.cost_usd)|add // 0 | .*100|round/100' "$RUN/costs.jsonl" 2>/dev/null || echo 0) · $(jq -r -s 'map("\(.stage) \(.turns)t") | join(", ")' "$RUN/costs.jsonl" 2>/dev/null || echo)"
} > "$RUN/report.md"

jq -n --slurpfile meta "$META" --slurpfile rep "$RUN/.report.json" \
      --argjson raw "$(jq '.findings|length' "$RUN/all_findings.json" 2>/dev/null || echo 0)" \
      --argjson cand "$(jq '.findings|length' "$RUN/candidates.json")" \
      --argjson cost "$(jq -s 'map(.cost_usd)|add // 0' "$RUN/costs.jsonl" 2>/dev/null || echo 0)" '
  {name:$meta[0].name, head:$meta[0].head, diff_lines:$meta[0].diff_lines, raw_findings:$raw, candidates:$cand,
   surfaced:($rep[0].surfaced|length), confirmed:([$rep[0].surfaced[]|select(.verdict=="CONFIRMED")]|length),
   likely:([$rep[0].surfaced[]|select(.verdict=="LIKELY")]|length), rejected:($rep[0].rejected|length),
   cost_usd:$cost, surfaced_locs:[$rep[0].surfaced[]|{file,line,severity:.final_severity}]}' > "$RUN/summary.json"
log "report: $RUN/report.md"
