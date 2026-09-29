#!/usr/bin/env bash
# Cloud environment setup. Runs once per environment snapshot, before Claude Code
# launches. Installs tools and copies this repo's Claude config into ~/.claude so it
# applies to every repository the session works on.
#
# Environment setup script (paste into the claude.ai environment dialog):
#   set -e
#   git clone -q https://github.com/marwen-abid/dot-env.git "$HOME/dot-env"
#   bash "$HOME/dot-env/cloud/install.sh" [profile ...]
# Environment variables are not available to setup scripts, so the repo must be public.
#
# Each profile argument runs cloud/profiles/<profile>.sh, a per-repository
# toolchain (for example "stellar-rpc"). Pass a profile only in the environment
# for that repository. The whole setup must finish in about 5 minutes, or the
# environment is not cached. A setup script that exits non-zero stops the session
# from starting, so a failed step prints a warning and the script continues.
set -uo pipefail

SDF_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
echo "dot-env: user=$(id -un) HOME=$HOME repo=$SDF_DIR"
warn() { echo "dot-env: WARNING: $*" >&2; }

# The image has gh and jq; this is a fallback. jq: the SessionStart hook prints
# its JSON with it.
pkgs=()
command -v gh >/dev/null 2>&1 || pkgs+=(gh)
command -v jq >/dev/null 2>&1 || pkgs+=(jq)
if [ "${#pkgs[@]}" -gt 0 ]; then
  echo "dot-env: installing ${pkgs[*]}"
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq "${pkgs[@]}" >/dev/null \
    || { apt-get update -qq 2>/dev/null || true; apt-get install -y -qq "${pkgs[@]}" >/dev/null; } \
    || warn "could not install ${pkgs[*]}"
fi

git config --global commit.gpgsign false
# Commit as the owner. The SessionStart hook sets this again in case the platform
# resets it at session start.
git config --global user.name "Marwen Abid"
git config --global user.email "marwen.abid@stellar.org"

for profile in "$@"; do
  script="$SDF_DIR/cloud/profiles/$profile.sh"
  if [ ! -f "$script" ]; then
    warn "unknown profile '$profile'"
    continue
  fi
  echo "dot-env: profile $profile"
  bash "$script" || warn "profile $profile failed; the session starts without it"
done

bash "$SDF_DIR/cloud/sync.sh" || warn "sync failed"
echo "dot-env: install done"
exit 0
