#!/usr/bin/env bash
# Build eval sets from a repo's history. Output: evals/<repo>/clean.tsv, evals/<repo>/fixes/<sha>.json
#   clean: merged PR commits (squash "(#N)" or merge commits). Every surfaced finding on these is a false positive.
#   fixes: commits whose subject says fix; SZZ-lite blames the removed lines to find the introducing commit.
# usage: rex-eval-mine.sh --repo DIR [--n 20] [--max-diff-lines 1500] [--since 2025-01-01]
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
need git; need jq
REPO="" N=20 MAX=1500 SINCE="" MAX_FIX="${REX_MAX_FIX_LINES:-250}"
while [ $# -gt 0 ]; do case "$1" in
  --repo) REPO="$2"; shift 2;; --n) N="$2"; shift 2;; --max-diff-lines) MAX="$2"; shift 2;; --since) SINCE="$2"; shift 2;;
  *) die "unknown arg $1";; esac; done
[ -n "$REPO" ] || die "usage: --repo DIR"
REPO="$(cd "$REPO" && git rev-parse --show-toplevel)"; NAME="$(repo_name "$REPO")"
OUT="$REX_HOME/evals/$NAME"; mkdir -p "$OUT/fixes"
g() { git -C "$REPO" "$@"; }
diff_lines() { g diff "$1" "$2" -- . ':!vendor' ':!*.pb.go' ':!go.sum' ':!Cargo.lock' | grep -c '^[+-][^+-]' || true; }
code_lines() { g diff "$1" "$2" --numstat -- '*.go' '*.rs' ':!*_test.go' ':!vendor' | awk '{s+=$1+$2} END{print s+0}'; }

# ---- clean set
: > "$OUT/clean.tsv"
count=0
while IFS=$'\t' read -r sha parents subject; do
  [ "$count" -ge "$N" ] && break
  case "$subject" in *[Mm]erge\ main*|*merge-main*|*[Rr]elease*|*[Bb]ump*) continue;; esac
  set -- $parents
  if [ $# -ge 2 ]; then base="$(g merge-base "$1" "$2")"; head="$2"
  else base="$1"; head="$sha"; fi
  [ "$(code_lines "$base" "$head")" -gt 0 ] || continue          # skip non-code PRs
  dl="$(diff_lines "$base" "$head")"; [ "$dl" -le "$MAX" ] || continue
  printf '%s\t%s\t%s\t%s\n' "$base" "$head" "$dl" "$subject" >> "$OUT/clean.tsv"
  count=$((count+1))
done < <(g log --first-parent ${SINCE:+--since="$SINCE"} --format='%H%x09%P%x09%s' -n 400 | grep -E '\(#[0-9]+\)$|^[0-9a-f]+'$'\t''[0-9a-f]+ [0-9a-f]+'$'\t')
log "clean: $count cases -> $OUT/clean.tsv"

# ---- fixes set (SZZ-lite)
count=0
while IFS=$'\t' read -r fix subject; do
  [ "$count" -ge "$N" ] && break
  printf '%s' "$subject" | grep -qiE '(^|[^a-z])fix' || continue                # subject must say fix, not just the body
  case "$subject" in *[Ll]int*|*[Tt]ypo*|*[Ff]lak*|*[Tt]est*|*CI*|*[Dd]oc*|*[Cc]omment*|*[Rr]elease*|*[Mm]erge*) continue;; esac
  parent="$fix^"
  fdl="$(code_lines "$parent" "$fix")"; [ "$fdl" -gt 0 ] && [ "$fdl" -le "${MAX_FIX:-250}" ] || continue   # real bugfixes are small"
  # removed non-test code lines in the fix
  regions="$(g diff -U0 "$parent" "$fix" -- '*.go' '*.rs' ':!*_test.go' ':!vendor' \
    | awk '/^diff --git/{f=$3; sub("^a/","",f)} /^@@/{split($2,a,","); n=substr(a[1],2); c=(a[2]==""?1:a[2]); if(c>0) print f"\t"n"\t"c}')"
  [ -n "$regions" ] || continue
  # blame each removed line at parent -> introducing sha + original line
  blame="$(printf '%s\n' "$regions" | while IFS=$'\t' read -r f n c; do
      g blame --porcelain -L "$n,+$c" "$parent" -- "$f" 2>/dev/null | awk -v f="$f" '
        /^[0-9a-f]{40} /{sha=$1; orig=$2} /^filename /{print sha"\t"$2"\t"orig}'
    done)"
  [ -n "$blame" ] || continue
  intro="$(printf '%s\n' "$blame" | cut -f1 | sort | uniq -c | sort -rn | head -1 | awk '{print $2}')"
  [ -n "$intro" ] && [ "$intro" != "$fix" ] || continue
  [ "$(g rev-list --count "$intro" 2>/dev/null)" -gt 1 ] || continue  # skip root commit
  dl="$(diff_lines "$intro^" "$intro")"; [ "$dl" -gt 0 ] && [ "$dl" -le "$MAX" ] || continue
  printf '%s\n' "$blame" | awk -F'\t' -v i="$intro" '$1==i{print $2"\t"$3}' \
    | jq -R -s --arg fix "$fix" --arg intro "$intro" --arg subject "$subject" --argjson dl "$dl" '
        {fix:$fix, intro:$intro, subject:$subject, intro_diff_lines:$dl,
         regions: (split("\n") | map(select(length>0) | split("\t") | {file:.[0], line:(.[1]|tonumber)})
                   | group_by(.file) | map({key:.[0].file, value:(map(.line)|unique)}) | from_entries)}' \
    > "$OUT/fixes/${fix:0:12}.json"
  count=$((count+1))
done < <(g log --no-merges ${SINCE:+--since="$SINCE"} -i --grep='fix' --format='%H%x09%s' -n 1500)
log "fixes: $count cases -> $OUT/fixes/"
