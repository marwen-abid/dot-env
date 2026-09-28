#!/usr/bin/env bash
# Mechanical gate + dedup over all lens outputs. Output: RUN_DIR/candidates.json, RUN_DIR/dropped.jsonl
# usage: rex-validate.sh --run RUN_DIR --tree DIR
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
need jq
RUN="" TREE=""
while [ $# -gt 0 ]; do case "$1" in
  --run) RUN="$2"; shift 2;; --tree) TREE="$2"; shift 2;; *) die "unknown arg $1";; esac; done
[ -n "$RUN" ] && [ -n "$TREE" ] || die "usage: --run --tree"
MIN_CONF="${REX_MIN_CONF:-0.3}"

ls "$RUN"/findings.*.json >/dev/null 2>&1 || { echo '{"findings":[]}' > "$RUN/candidates.json"; exit 0; }
jq -s '{findings: ((map(.findings) | add) // [])}' "$RUN"/findings.*.json > "$RUN/all_findings.json"

# file existence check happens in bash; produce a list of existing files
jq -r '.findings[].file' "$RUN/all_findings.json" | sort -u | while IFS= read -r f; do
  [ -n "$f" ] && [ -f "$TREE/$f" ] && printf '%s\n' "$f"; done > "$RUN/.existing_files.txt" || true

jq --slurpfile changed <(jq -R -s 'split("\n")|map(select(length>0))' "$RUN/changed_files.txt") \
   --slurpfile existing <(jq -R -s 'split("\n")|map(select(length>0))' "$RUN/.existing_files.txt") \
   --argjson minconf "$MIN_CONF" '
  def reason:
    if (.trigger_path|length) < 40 then "trigger_path too short"
    elif (.trigger_path | test("->|→") | not) then "trigger_path has no call chain"
    elif (.confidence < $minconf) then "confidence below \($minconf)"
    elif ([.file] | inside($existing[0]) | not) then "file does not exist in tree"
    elif ([.file] | inside($changed[0]) | not) then "file not in diff"
    else null end;
  .findings
  | map(. + {drop: reason})
  | {dropped: map(select(.drop != null)),
     kept: (map(select(.drop == null)) | map(del(.drop))
            # dedup: same file, same category, |line diff| <= 3 -> keep highest confidence
            | sort_by(.file, .category, .line)
            | reduce .[] as $f ([]; if (length > 0 and (.[-1].file == $f.file) and (.[-1].category == $f.category) and (($f.line - .[-1].line) | fabs) <= 3)
                                    then (if $f.confidence > .[-1].confidence then .[:-1] + [$f + {merged_with: .[-1].id}] else . end)
                                    else . + [$f] end))}
' "$RUN/all_findings.json" > "$RUN/.validate.json"
jq -c '.dropped[] | {id, file, line, drop, claim}' "$RUN/.validate.json" > "$RUN/dropped.jsonl"
jq '{findings: .kept}' "$RUN/.validate.json" > "$RUN/candidates.json"
log "validate: $(jq '.findings|length' "$RUN/all_findings.json") in, $(jq '.findings|length' "$RUN/candidates.json") kept, $(wc -l < "$RUN/dropped.jsonl" | tr -d ' ') dropped"
