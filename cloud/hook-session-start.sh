#!/usr/bin/env bash
# SessionStart hook (cloud). Pulls the latest config, re-syncs it into ~/.claude,
# then asks Claude Code to re-scan skills. Fails open: a failed pull keeps the
# copy already on disk.
set -uo pipefail

SDF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
note="dot-env: config synced"
if git -C "$SDF_DIR" pull -q --ff-only >/dev/null 2>&1; then
  note="dot-env: config synced ($(git -C "$SDF_DIR" rev-parse --short HEAD))"
else
  note="dot-env: pull failed, using cached config ($(git -C "$SDF_DIR" rev-parse --short HEAD))"
fi
bash "$SDF_DIR/cloud/sync.sh" >/dev/null 2>&1 || note="dot-env: sync failed"

# Commit as the owner, not as the container default (Claude <noreply@anthropic.com>).
# Set here, not in install.sh, because the platform sets its identity after setup.
git config --global user.name "Marwen Abid"
git config --global user.email "marwen.abid@stellar.org"

# Profile env files (cloud/profiles/*.sh write them) go into every Bash command
# of the session through CLAUDE_ENV_FILE.
STATE_DIR="${DOT_ENV_STATE:-$HOME/.config/dot-env}"
if [ -n "${CLAUDE_ENV_FILE:-}" ]; then
  for env in "$STATE_DIR"/*.env; do
    [ -f "$env" ] || continue
    cat "$env" >> "$CLAUDE_ENV_FILE"
    note="$note; env $(basename "$env" .env)"
  done
fi

jq -nc --arg ctx "$note" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",reloadSkills:true,additionalContext:$ctx}}'
