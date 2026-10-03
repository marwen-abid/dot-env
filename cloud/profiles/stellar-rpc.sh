#!/usr/bin/env bash
# Toolchain for stellar/stellar-rpc in a cloud environment. Runs from
# cloud/install.sh when the setup script passes the "stellar-rpc" profile:
#   bash "$HOME/dot-env/cloud/install.sh" stellar-rpc
#
# Installs what the image does not have and CI has (.github/actions/setup-go):
#   - Go at the go.mod version, in place of the image's Go
#   - libzstd in ~/.zstd, librocksdb in ~/.rocksdb, golangci-lint at the CI pin,
#     from the prebuilt artifact (see stellar-rpc-native.sh)
#   - the Rust preflight libs (make build-libs), when the checkout exists
# and writes the cgo variables to $DOT_ENV_STATE/stellar-rpc.env.
#
# A cloud setup script must finish in about 5 minutes to be cached, so the slow
# steps run in parallel and RocksDB comes prebuilt. Idempotent: each step is
# skipped when its output is already present. Exits non-zero when a step fails;
# install.sh reports that and continues.
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NATIVE="$HERE/stellar-rpc-native.sh"
REPO_DIR="${STELLAR_RPC_DIR:-/home/user/stellar-rpc}"
# The native-lib scripts and the lint pin are on this branch, not on main.
SRC_REF="${STELLAR_RPC_REF:-feature/full-history}"
STATE_DIR="${DOT_ENV_STATE:-$HOME/.config/dot-env}"
LOG_DIR="$STATE_DIR/logs"

log() { echo "dot-env[stellar-rpc]: $*"; }
mkdir -p "$STATE_DIR" "$LOG_DIR"
# Keep the whole run in a log: the session has no other view of setup output.
exec > >(tee "$LOG_DIR/profile.log") 2>&1

case "$(uname -m)" in
  x86_64) GOARCH=amd64 ;;
  aarch64 | arm64) GOARCH=arm64 ;;
  *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

# --- Source of the build scripts ---------------------------------------------
# A fresh shallow clone of $SRC_REF. The session checkout may be on main, which
# does not have scripts/install-*.sh.
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
SRC="$TMP/rpc"
git clone -q --depth 1 --branch "$SRC_REF" https://github.com/stellar/stellar-rpc "$SRC"

# --- Go, in place --------------------------------------------------------------
# Replace the image's GOROOT so every PATH finds the new Go. go.dev/dl may be
# blocked; the toolchain module on proxy.golang.org is on the Trusted list.
# The directory keeps its name (for example /usr/local/go1.24.7) and gets the new
# contents. Each step below runs even when an earlier one fails.
status=0
install_go() {
  local want cur ver root tc
  want="$(awk '$1 == "go" { print $2; exit }' "$SRC/go.mod")"   # e.g. 1.26
  cur="$(cd / && GOTOOLCHAIN=local go env GOVERSION)" || return 1
  if [[ "$cur" == go"$want" || "$cur" == go"$want".* ]]; then
    log "$cur already installed"
    return 0
  fi
  ver="$(curl -fsSL https://proxy.golang.org/golang.org/toolchain/@v/list \
    | sed -n "s/^v0\.0\.1-go\(${want//./\\.}\.[0-9]*\)\.linux-${GOARCH}\$/\1/p" \
    | sort -V | tail -1)"
  [ -n "$ver" ] || { log "no go${want}.x toolchain on proxy.golang.org"; return 1; }
  root="$(cd / && GOTOOLCHAIN=local go env GOROOT)" || return 1
  # Replace only a real GOROOT, never a system directory.
  case "$root" in / | /usr | /usr/local | /opt | "$HOME") log "GOROOT is $root; not replacing it"; return 1 ;; esac
  if [ ! -f "$root/VERSION" ] || [ ! -x "$root/bin/go" ] || [ ! -d "$root/src/runtime" ]; then
    log "$root does not look like a GOROOT; not replacing it"
    return 1
  fi
  log "replacing $cur with go$ver in $root"
  tc="$(cd / && GOTOOLCHAIN="go$ver" go env GOROOT)" || return 1
  [ -x "$tc/bin/go" ] || { log "go$ver download failed"; return 1; }
  cp -a "$tc" "$TMP/goroot" && chmod -R u+w "$TMP/goroot" || return 1
  rm -rf "${root:?}"/* && cp -a "$TMP/goroot/." "$root/" || return 1
  log "installed $(cd / && GOTOOLCHAIN=local go env GOVERSION) in $root"
}
if install_go; then
  export GOTOOLCHAIN=local
else
  status=1
  log "Go step failed; go keeps switching to the go.mod toolchain by itself (GOTOOLCHAIN=auto)"
fi

# --- Native libs and golangci-lint ------------------------------------------------
native() {
  local k url
  k="$(bash "$NATIVE" key "$SRC")"
  if [ "$(cat "$HOME/.rocksdb/.dot-env-key" 2>/dev/null)" = "$k" ]; then
    echo "native: already installed ($k)"
    return
  fi
  rm -rf "$TMP/native" && mkdir -p "$TMP/native"
  url="$(bash "$NATIVE" url "$k")"
  if curl -fsSL "$url" | tar xz -C "$TMP/native" \
    && [ "$(cat "$TMP/native/.rocksdb/.dot-env-key" 2>/dev/null)" = "$k" ]; then
    echo "native: downloaded $url"
  else
    # No artifact for this key yet: run the workflow in dot-env
    # (gh workflow run stellar-rpc-native.yml). Build here instead. This takes
    # about 20 minutes, so this setup will not be cached.
    echo "native: no artifact at $url; building from source (about 20 minutes)"
    rm -rf "$TMP/native" && mkdir -p "$TMP/native"
    bash "$NATIVE" build "$SRC" "$TMP/native"
  fi
  rm -rf "$HOME/.zstd" "$HOME/.rocksdb"
  mv "$TMP/native/.zstd" "$TMP/native/.rocksdb" "$HOME/"
  install -m 0755 "$TMP/native/bin/golangci-lint" /usr/local/bin/golangci-lint
  echo "native: installed ($k)"
}

# cgo finds the Rust libs under <checkout>/target, so each checkout needs its own.
# A git worktree can use: ln -s "$REPO_DIR/target" <worktree>/target
rust_libs() {
  if [ -f "$REPO_DIR/Makefile" ]; then
    make -C "$REPO_DIR" build-libs
  else
    echo "rust: no checkout at $REPO_DIR; run 'make build-libs' in the session"
  fi
}

log "native libs and Rust libs in parallel (logs in $LOG_DIR)"
native > "$LOG_DIR/native.log" 2>&1 & native_pid=$!
rust_libs > "$LOG_DIR/rust.log" 2>&1 & rust_pid=$!
wait "$native_pid" || { status=1; log "native step failed:"; tail -20 "$LOG_DIR/native.log"; }
wait "$rust_pid" || { status=1; log "make build-libs failed:"; tail -20 "$LOG_DIR/rust.log"; }
tail -1 "$LOG_DIR/native.log" | sed 's/^/dot-env[stellar-rpc]: /'
tail -1 "$LOG_DIR/rust.log" | sed 's/^/dot-env[stellar-rpc]: /'

# --- Environment for every session ---------------------------------------------
# Same values as CI (.github/actions/setup-go/action.yml). Set the same values
# in the environment's variables (README); the SessionStart hook also loads this file.
cat > "$STATE_DIR/stellar-rpc.env" <<EOF
export CGO_CFLAGS="-I$HOME/.zstd/include -I$HOME/.rocksdb/include"
export CGO_LDFLAGS="-L$HOME/.zstd/lib -L$HOME/.rocksdb/lib"
export LD_LIBRARY_PATH="$HOME/.zstd/lib:$HOME/.rocksdb/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export GOFLAGS=-tags=grocksdb_clean_link
EOF

log "go=$(go env GOVERSION) lint=$(golangci-lint version --short 2>/dev/null || echo '?') status=$status"
exit "$status"
