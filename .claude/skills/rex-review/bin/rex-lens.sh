#!/usr/bin/env bash
# Run one lens over a brief. Output: RUN_DIR/findings.<lens>.json ({"findings":[...]} with ids)
# usage: rex-lens.sh --run RUN_DIR --tree DIR --lens NAME [--model M]
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
need claude; need jq
RUN="" TREE="" LENS="" MODEL="${REX_LENS_MODEL:-sonnet}"
while [ $# -gt 0 ]; do case "$1" in
  --run) RUN="$2"; shift 2;; --tree) TREE="$2"; shift 2;; --lens) LENS="$2"; shift 2;; --model) MODEL="$2"; shift 2;;
  *) die "unknown arg $1";; esac; done
[ -n "$RUN" ] && [ -n "$TREE" ] && [ -n "$LENS" ] || die "usage: --run --tree --lens"
PROMPT="$REX_HOME/prompts/lens-$LENS.md"; [ -f "$PROMPT" ] || die "no prompt for lens '$LENS' ($PROMPT)"
RAW="$RUN/lens.$LENS.raw.json"

log "lens $LENS ($MODEL)"
out="$(cd "$TREE" && claude_call "$MODEL" "$REX_HOME/schemas/finding.schema.json" "$PROMPT" "${REX_LENS_TURNS:-40}" "$RAW" \
        --tools "Read,Grep,Glob" --allowedTools "Read" "Grep" "Glob" < "$RUN/brief.md")"
record_cost "$RUN" "lens:$LENS" "$RAW"
if [ "$out" = "null" ]; then log "lens $LENS produced no structured output"; out='{"findings":[]}'; fi
printf '%s' "$out" | jq --arg lens "$LENS" '{findings: [.findings | to_entries[] | .value + {id: ("\($lens)-\(.key+1)"), lens: $lens}]}' > "$RUN/findings.$LENS.json"
log "lens $LENS: $(jq '.findings|length' "$RUN/findings.$LENS.json") findings"
