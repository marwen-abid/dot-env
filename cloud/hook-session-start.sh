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

jq -nc --arg ctx "$note" \
  '{hookSpecificOutput:{hookEventName:"SessionStart",reloadSkills:true,additionalContext:$ctx}}'
