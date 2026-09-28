#!/usr/bin/env bash
# Deterministic brief assembly. No LLM calls.
# usage: rex-brief.sh --repo DIR --base REF --head REF --out RUN_DIR [--pr N] [--tree DIR]
#   --tree DIR  checked-out tree at HEAD used for caller search and linters (default: --repo)
source "$(dirname "${BASH_SOURCE[0]}")/_lib.sh"
need git; need jq; need rg

REPO="" BASE="" HEAD="" OUT="" PR="" TREE=""
while [ $# -gt 0 ]; do case "$1" in
  --repo) REPO="$2"; shift 2;; --base) BASE="$2"; shift 2;; --head) HEAD="$2"; shift 2;;
  --out) OUT="$2"; shift 2;; --pr) PR="$2"; shift 2;; --tree) TREE="$2"; shift 2;;
  *) die "unknown arg $1";; esac; done
[ -n "$REPO" ] && [ -n "$BASE" ] && [ -n "$HEAD" ] && [ -n "$OUT" ] || die "usage: --repo --base --head --out"
TREE="${TREE:-$REPO}"
mkdir -p "$OUT"
REPO="$(cd "$REPO" && pwd -P)"; TREE="$(cd "$TREE" && pwd -P)"

git_r() { git -C "$REPO" "$@"; }
MB="$(git_r merge-base "$BASE" "$HEAD")"
HEAD_SHA="$(git_r rev-parse "$HEAD")"
NAME="$(repo_name "$REPO")"

git_r diff -U3 "$MB" "$HEAD_SHA" > "$OUT/diff.patch"
git_r diff --name-only "$MB" "$HEAD_SHA" > "$OUT/changed_files.txt"
STAT="$(git_r diff --stat "$MB" "$HEAD_SHA" | tail -1)"
DIFF_LINES="$(grep -c '^[+-][^+-]' "$OUT/diff.patch" || true)"

# --- changed symbols: enclosing functions from hunk headers + added/removed defs
{
  grep -E '^@@ .* @@ ' "$OUT/diff.patch" | sed -E 's/^@@ .* @@ //' \
    | grep -E '^(func|fn|pub|impl|type|def|class|async|export|function|const|static)\b' || true
  grep -E '^[+-](func|pub(\([a-z]+\))? fn|fn|type|impl)\b' "$OUT/diff.patch" | sed -E 's/^[+-]//' || true
} | sed -E 's/[[:space:]]*\{[[:space:]]*$//' | sort -u > "$OUT/changed_symbols.txt"

# identifiers to search for callers: last identifier before "(" or after type/impl
sed -E -e 's/^func \([^)]*\) ([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
       -e 's/^func ([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
       -e 's/^(pub(\([a-z]+\))? )?(async )?(unsafe )?fn ([A-Za-z_][A-Za-z0-9_]*).*/\5/' \
       -e 's/^type ([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
       -e 's/^impl.* for ([A-Za-z_][A-Za-z0-9_]*).*/\1/' \
       "$OUT/changed_symbols.txt" \
  | grep -E '^[A-Za-z_][A-Za-z0-9_]*$' | grep -vE '^(main|init|new|New|String|Error|Close|Run|Test[A-Za-z0-9_]*|Benchmark[A-Za-z0-9_]*)$' \
  | sort -u > "$OUT/symbol_names.txt"

# --- callers (cap per symbol and total)
: > "$OUT/callers.txt"
TOTAL=0
while IFS= read -r sym; do
  [ -z "$sym" ] && continue
  [ "$TOTAL" -ge 400 ] && { echo "... caller search truncated at 400 lines" >> "$OUT/callers.txt"; break; }
  hits="$(cd "$TREE" && rg -n --no-heading -w "$sym" -g '!vendor/**' -g '!*.pb.go' -g '!*_gen.go' -g '!*.lock' \
          -g '*.go' -g '*.rs' -g '*.ts' -g '*.js' -g '*.py' 2>/dev/null \
          | grep -E "\b${sym}(\(|\.|<|::|\{|\[)" | head -30 || true)"
  if [ -n "$hits" ]; then
    n="$(printf '%s\n' "$hits" | wc -l | tr -d ' ')"
    printf '## %s (%s refs shown)\n%s\n\n' "$sym" "$n" "$hits" >> "$OUT/callers.txt"
    TOTAL=$((TOTAL + n))
  fi
done < "$OUT/symbol_names.txt"

# --- intent
{
  if [ -n "$PR" ] && command -v gh >/dev/null 2>&1; then
    (cd "$REPO" && gh pr view "$PR" --json title,body,url -q '"### PR: " + .title + "\n" + .url + "\n\n" + (.body // "")' 2>/dev/null) || true
    echo
  fi
  echo "### Commits"
  git_r log --no-merges --format='- %h %s%n%w(0,2,2)%b' "$MB..$HEAD_SHA" | sed '/^[[:space:]]*$/d'
} > "$OUT/intent.md"

# --- deterministic checks (linters), scoped to changed code where the tool allows
{
  if [ -f "$TREE/go.mod" ] && command -v golangci-lint >/dev/null 2>&1 && [ "${REX_LINT_GO:-1}" = "1" ]; then
    echo "### golangci-lint (new issues since merge-base)"
    (cd "$TREE" && run_timeout 600 golangci-lint run --new-from-rev "$MB" --timeout 9m ./... 2>&1 | head -150) || echo "(golangci-lint failed or timed out)"
    echo
  fi
  if [ -f "$TREE/Cargo.toml" ] && command -v cargo >/dev/null 2>&1 && [ "${REX_LINT_RUST:-0}" = "1" ]; then
    echo "### cargo clippy"
    (cd "$TREE" && run_timeout 900 cargo clippy --quiet --message-format short 2>&1 | head -150) || echo "(clippy failed or timed out)"
    echo
  fi
} > "$OUT/lint.txt"
[ -s "$OUT/lint.txt" ] || echo "(no linters ran)" > "$OUT/lint.txt"

# --- context cards: $REPO/.review/context then $REX_HOME/context/<repo>
: > "$OUT/cards.md"
shopt -s extglob nullglob
for dir in "$REPO/.review/context" "$REX_HOME/context/$NAME"; do
  [ -d "$dir" ] || continue
  for card in "$dir"/*.md; do
    b="$(basename "$card")"
    include=0
    case "$b" in invariants.md|bug-patterns.md|architecture.md) include=1;; esac
    if [ "$include" = 0 ]; then
      # frontmatter: globs: [a/**, b/*.go]  or one glob per "- " line
      globs="$(awk 'NR==1&&$0!="---"{exit} NR>1&&$0=="---"{exit} NR>1{print}' "$card" \
               | grep -E '^(globs:|[[:space:]]*- )' | sed -E 's/^globs:[[:space:]]*//; s/^[[:space:]]*- //; s/[][,"]/ /g')"
      for g in $globs; do
        while IFS= read -r f; do
          # ** -> match any depth; use case with pattern
          pat="$(printf '%s' "$g" | sed -E 's#\*\*/#*#g; s#\*\*#*#g')"
          # shellcheck disable=SC2254
          case "$f" in $pat) include=1; break;; esac
        done < "$OUT/changed_files.txt"
        [ "$include" = 1 ] && break
      done
    fi
    if [ "$include" = 1 ]; then
      printf '\n---\n<!-- card: %s -->\n' "$b" >> "$OUT/cards.md"
      awk 'BEGIN{fm=0} NR==1&&$0=="---"{fm=1;next} fm==1&&$0=="---"{fm=2;next} fm!=1{print}' "$card" >> "$OUT/cards.md"
    fi
  done
done
[ -s "$OUT/cards.md" ] || echo "(no context cards available for this repo yet)" > "$OUT/cards.md"

# --- assemble
{
  echo "# Review brief: $NAME"
  echo
  echo "- Repo: \`$NAME\`  merge-base: \`${MB:0:10}\`  head: \`${HEAD_SHA:0:10}\`"
  echo "- Files changed: $(wc -l < "$OUT/changed_files.txt" | tr -d ' ')  ($STAT)"
  echo "- Line numbers in findings must refer to the HEAD version. Compute them from the \`+\` side of hunk headers, or read the file."
  echo
  echo "## Intent"; cat "$OUT/intent.md"; echo
  echo "## Changed files"; sed 's/^/- /' "$OUT/changed_files.txt"; echo
  echo "## Changed symbols"; if [ -s "$OUT/changed_symbols.txt" ]; then sed 's/^/- /' "$OUT/changed_symbols.txt"; else echo "(none detected)"; fi; echo
  echo "## Callers and references of changed symbols (HEAD tree)"; echo '```'; cat "$OUT/callers.txt"; echo '```'; echo
  echo "## Deterministic checks"; echo '```'; cat "$OUT/lint.txt"; echo '```'; echo
  echo "## Context cards"; cat "$OUT/cards.md"; echo
  echo "## Diff"; echo '```diff'; cat "$OUT/diff.patch"; echo '```'
} > "$OUT/brief.md"

jq -n --arg repo "$REPO" --arg name "$NAME" --arg base "$BASE" --arg head "$HEAD_SHA" --arg mb "$MB" \
      --arg pr "$PR" --argjson diff_lines "${DIFF_LINES:-0}" \
      --argjson files "$(jq -R -s 'split("\n")|map(select(length>0))' "$OUT/changed_files.txt")" \
      '{repo:$repo,name:$name,base:$base,head:$head,merge_base:$mb,pr:$pr,diff_lines:$diff_lines,files:$files}' > "$OUT/meta.json"
log "brief: $(wc -c < "$OUT/brief.md" | tr -d ' ') bytes, $DIFF_LINES diff lines, $(wc -l < "$OUT/symbol_names.txt" | tr -d ' ') symbols"
