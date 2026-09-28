#!/usr/bin/env bash
# Copies this repo's Claude config into $HOME/.claude. Idempotent. Runs from
# cloud/install.sh at setup and from the SessionStart hook at every session start.
# Copies skills one directory at a time so skills from other sources (for example
# the claude.ai synced skills) are kept.
set -euo pipefail

SDF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLAUDE_DIR="$HOME/.claude"
mkdir -p "$CLAUDE_DIR/agents" "$CLAUDE_DIR/skills"

cp "$SDF_DIR/CLAUDE.md" "$CLAUDE_DIR/CLAUDE.md"

for src in "$SDF_DIR"/.claude/agents/*.md; do
  cp "$src" "$CLAUDE_DIR/agents/$(basename "$src")"
done

for src in "$SDF_DIR"/.claude/skills/*/; do
  name="$(basename "$src")"
  rm -rf "$CLAUDE_DIR/skills/$name"
  cp -R "$src" "$CLAUDE_DIR/skills/$name"
done

# settings: the cloud variant adds the SessionStart hook; the hook path is absolute.
sed "s|__SDF_DIR__|$SDF_DIR|g" "$SDF_DIR/cloud/settings.json" > "$CLAUDE_DIR/settings.json"
chmod +x "$SDF_DIR"/cloud/*.sh
echo "dot-env: synced into $CLAUDE_DIR"
