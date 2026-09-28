# shellcheck shell=bash
# Shared helpers for rex scripts. Source only.
set -euo pipefail

REX_HOME="${REX_HOME:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)}"
export REX_HOME

log()  { printf '[rex] %s\n' "$*" >&2; }
die()  { printf '[rex] error: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "missing tool: $1"; }

# run_timeout SECS cmd... ; uses timeout/gtimeout when present.
run_timeout() {
  local secs="$1"; shift
  if command -v timeout >/dev/null 2>&1; then timeout "$secs" "$@"
  elif command -v gtimeout >/dev/null 2>&1; then gtimeout "$secs" "$@"
  else "$@"; fi
}

repo_name() { basename "$(cd "$1" && git rev-parse --show-toplevel)"; }

# claude_call MODEL SCHEMA_FILE SYSTEM_FILE MAX_TURNS OUT_JSON [extra claude args...]
# Reads the user message from stdin. Writes full result JSON to OUT_JSON.
# Prints the structured_output object, or "null" on failure. Never exits non-zero on model failure.
claude_call() {
  local model="$1" schema="$2" system="$3" turns="$4" out="$5"; shift 5
  local msg; msg="$(cat)"
  if ! claude -p --model "$model" --output-format json --max-turns "$turns" \
      --json-schema "$(cat "$schema")" \
      --append-system-prompt "$(cat "$system")" \
      "$@" "$msg" > "$out" 2> "${out%.json}.stderr"; then
    log "claude exited non-zero (see ${out%.json}.stderr)"
  fi
  if ! jq -e . "$out" >/dev/null 2>&1; then echo '{}' > "$out"; fi
  jq -c '.structured_output // null' "$out"
}

# record_cost RUN_DIR STAGE RAW_JSON
record_cost() {
  jq -c --arg stage "$2" '{stage:$stage, cost_usd:(.total_cost_usd//0), turns:(.num_turns//0),
      in:(.usage.input_tokens//0), out:(.usage.output_tokens//0),
      cache_read:(.usage.cache_read_input_tokens//0), subtype:(.subtype//"unknown")}' "$3" >> "$1/costs.jsonl"
}
