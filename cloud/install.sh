#!/usr/bin/env bash
# Cloud environment setup. Runs once per environment snapshot, before Claude Code
# launches. Installs tools and copies this repo's Claude config into ~/.claude so it
# applies to every repository the session works on.
#
# Environment setup script (paste into the claude.ai environment dialog):
#   set -e
#   git clone -q https://github.com/marwen-abid/dot-env.git "$HOME/dot-env"
#   bash "$HOME/dot-env/cloud/install.sh"
# Environment variables are not available to setup scripts, so the repo must be public.
set -euo pipefail

SDF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "dot-env: user=$(id -un) HOME=$HOME repo=$SDF_DIR"

if ! command -v gh >/dev/null 2>&1; then
  echo "dot-env: installing gh"
  export DEBIAN_FRONTEND=noninteractive
  # The image's apt lists already contain gh. `apt-get update` is only a fallback:
  # third-party PPAs in the image are blocked by the Trusted network and would fail it.
  apt-get install -y -qq gh >/dev/null \
    || { apt-get update -qq 2>/dev/null || true; apt-get install -y -qq gh >/dev/null; }
fi

git config --global commit.gpgsign false

bash "$SDF_DIR/cloud/sync.sh"
echo "dot-env: install done"
