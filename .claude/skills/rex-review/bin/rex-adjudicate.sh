#!/usr/bin/env bash
# Adversarial verification of candidates. Output: RUN_DIR/verdicts.json
# usage: rex-adjudicate.sh --run RUN_DIR --tree DIR [--model M] [--repro]
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
need claude; need jq
RUN="" TREE="" MODEL="${REX_ADJ_MODEL:-opus}" REPRO=0
while [ $# -gt 0 ]; do case "$1" in
  --run) RUN="$2"; shift 2;; --tree) TREE="$2"; shift 2;; --model) MODEL="$2"; shift 2;; --repro) REPRO=1; shift;;
  *) die "unknown arg $1";; esac; done
[ -n "$RUN" ] && [ -n "$TREE" ] || die "usage: --run --tree"
N="$(jq '.findings|length' "$RUN/candidates.json")"
if [ "$N" = 0 ]; then echo '{"verdicts":[]}' > "$RUN/verdicts.json"; log "adjudicate: no candidates"; exit 0; fi

RAW="$RUN/adjudicator.raw.json"
TOOLS="Read,Grep,Glob"; ALLOWED=(--allowedTools "Read" "Grep" "Glob")
REPRO_NOTE="Reproduction is disabled. Do not write or run tests."
if [ "$REPRO" = 1 ]; then
  TOOLS="Read,Grep,Glob,Bash,Write,Edit"
  ALLOWED=(--allowedTools "Read" "Grep" "Glob" "Write" "Edit" "Bash(go test:*)" "Bash(go vet:*)" "Bash(cargo test:*)" "Bash(rm *_rex_test.go)" "Bash(git checkout *)" "Bash(git status*)" "Bash(git diff*)")
  REPRO_NOTE="Reproduction is enabled for CONFIRMED critical/high findings. Name test files *_rex_test.go (Go) or put Rust tests in a #[cfg(test)] module you then remove. Delete what you added when done."
fi

log "adjudicate $N candidates ($MODEL, repro=$REPRO)"
out="$(cd "$TREE" && {
  printf '%s\n\n# Candidates to adjudicate\n\n```json\n' "$REPRO_NOTE"
  jq '.findings | map(del(.lens, .merged_with))' "$RUN/candidates.json"
  printf '```\n\n# Brief\n\n'
  cat "$RUN/brief.md"
} | claude_call "$MODEL" "$REX_HOME/schemas/verdict.schema.json" "$REX_HOME/prompts/adjudicator.md" "${REX_ADJ_TURNS:-80}" "$RAW" \
      --tools "$TOOLS" "${ALLOWED[@]}" --permission-mode acceptEdits)"
record_cost "$RUN" "adjudicate" "$RAW"
if [ "$out" = "null" ]; then log "adjudicator produced no structured output"; out='{"verdicts":[]}'; fi
printf '%s' "$out" > "$RUN/verdicts.json"
# candidates with no verdict are treated as REJECTED (fail closed)
jq --slurpfile v "$RUN/verdicts.json" '
  ($v[0].verdicts | map({key:.id, value:.}) | from_entries) as $vs
  | {verdicts: [.findings[] | ($vs[.id] // {id:.id, verdict:"REJECTED", severity:.severity, evidence:"", reason:"adjudicator returned no verdict for this id", reproduced:false})]}' \
  "$RUN/candidates.json" > "$RUN/.verdicts.full.json" && mv "$RUN/.verdicts.full.json" "$RUN/verdicts.json"
log "adjudicate: $(jq '[.verdicts[]|select(.verdict=="CONFIRMED")]|length' "$RUN/verdicts.json") confirmed, $(jq '[.verdicts[]|select(.verdict=="LIKELY")]|length' "$RUN/verdicts.json") likely, $(jq '[.verdicts[]|select(.verdict=="REJECTED")]|length' "$RUN/verdicts.json") rejected"
