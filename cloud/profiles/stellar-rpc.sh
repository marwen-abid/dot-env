#!/usr/bin/env bash
# Toolchain for stellar/stellar-rpc in a cloud environment. Runs from
# cloud/install.sh when the setup script passes the "stellar-rpc" profile:
#   bash "$HOME/dot-env/cloud/install.sh" stellar-rpc
#
# Installs what the image does not have and CI has (.github/actions/setup-go):
#   - Go at the version in go.mod (the image has an older one)
#   - libzstd in ~/.zstd and librocksdb in ~/.rocksdb, built with the repo scripts
#   - golangci-lint at the version that .github/workflows/golang.yml pins
#   - the Rust preflight libs (make build-libs), when the checkout exists
# and writes the cgo variables to $DOT_ENV_STATE/stellar-rpc.env. The SessionStart
# hook loads that file into every session.
#
# Idempotent: each step is skipped when its output is already present.
set -euo pipefail

REPO_DIR="${STELLAR_RPC_DIR:-/home/user/stellar-rpc}"
# The native-lib scripts and the lint pin are on this branch, not on main.
SRC_REF="${STELLAR_RPC_REF:-feature/full-history}"
STATE_DIR="${DOT_ENV_STATE:-$HOME/.config/dot-env}"
ZSTD_HOME="$HOME/.zstd"
ROCKSDB_HOME="$HOME/.rocksdb"
GO_ROOT=/usr/local/go-toolchain

log() { echo "dot-env[stellar-rpc]: $*"; }
mkdir -p "$STATE_DIR"

case "$(uname -m)" in
  x86_64) GOARCH=amd64 ;;
  aarch64 | arm64) GOARCH=arm64 ;;
  *) echo "unsupported arch $(uname -m)" >&2; exit 1 ;;
esac

# The build scripts call `sudo apt-get` when cmake or ninja is missing, and the
# image runs as root without sudo. Install them first. Same apt fallback as gh.
if ! command -v cmake >/dev/null || ! command -v ninja >/dev/null; then
  log "installing cmake and ninja"
  export DEBIAN_FRONTEND=noninteractive
  apt-get install -y -qq cmake ninja-build >/dev/null \
    || { apt-get update -qq 2>/dev/null || true; apt-get install -y -qq cmake ninja-build >/dev/null; }
fi

# --- Source of the build scripts ---------------------------------------------
# A fresh shallow clone of $SRC_REF. The session checkout may be on main, which
# does not have scripts/install-*.sh.
SRC="$(mktemp -d)"
trap 'rm -rf "$SRC"' EXIT
git clone -q --depth 1 --branch "$SRC_REF" https://github.com/stellar/stellar-rpc "$SRC/rpc"
SRC="$SRC/rpc"

# --- Go ------------------------------------------------------------------------
GO_WANT="$(awk '$1 == "go" { print $2; exit }' "$SRC/go.mod")"   # e.g. 1.26
if [ -x "$GO_ROOT/bin/go" ] && [[ "$("$GO_ROOT/bin/go" env GOVERSION)" == go"$GO_WANT"* ]]; then
  log "go $("$GO_ROOT/bin/go" env GOVERSION) already installed"
else
  # go.dev/dl may be blocked. The image's go can fetch a newer toolchain module
  # through proxy.golang.org, which works; copy that GOROOT out of the module cache.
  GO_VER="$(curl -fsSL https://proxy.golang.org/golang.org/toolchain/@v/list \
    | sed -n "s/^v0\.0\.1-go\(${GO_WANT//./\\.}\.[0-9]*\)\.linux-${GOARCH}\$/\1/p" \
    | sort -V | tail -1)"
  [ -n "$GO_VER" ] || { echo "no go${GO_WANT}.x toolchain found on proxy.golang.org" >&2; exit 1; }
  log "installing go$GO_VER into $GO_ROOT"
  TC_ROOT="$(cd / && GOTOOLCHAIN="go$GO_VER" go env GOROOT)"
  [ -x "$TC_ROOT/bin/go" ] || { echo "go$GO_VER download failed" >&2; exit 1; }
  [ -d "$GO_ROOT" ] && chmod -R u+w "$GO_ROOT" && rm -rf "$GO_ROOT"
  cp -a "$TC_ROOT" "$GO_ROOT"
  chmod -R u+w "$GO_ROOT"
fi
ln -sf "$GO_ROOT/bin/go" /usr/local/bin/go
ln -sf "$GO_ROOT/bin/gofmt" /usr/local/bin/gofmt
export PATH="$GO_ROOT/bin:$PATH"
export GOTOOLCHAIN=local

# --- libzstd and librocksdb ----------------------------------------------------
# The marker holds a hash of both scripts, the same key CI uses for its cache.
LIBS_KEY="$(cat "$SRC/scripts/install-zstd.sh" "$SRC/scripts/install-rocksdb.sh" | sha256sum | cut -c1-16)"
if [ "$(cat "$ROCKSDB_HOME/.dot-env-key" 2>/dev/null)" = "$LIBS_KEY" ]; then
  log "libzstd and librocksdb already built ($LIBS_KEY)"
else
  log "building libzstd into $ZSTD_HOME"
  rm -rf "$ZSTD_HOME" "$ROCKSDB_HOME"
  PREFIX="$ZSTD_HOME" bash "$SRC/scripts/install-zstd.sh"

  # The network policy blocks github.com/*/archive/* and codeload.github.com,
  # so replace the tarball download with a git clone of the same tag.
  # shellcheck disable=SC2016 # the variables expand inside the generated script
  sed '/^curl .*rocksdb\.tar\.gz/,/^tar xzf .*rocksdb\.tar\.gz/c\
git clone -q --depth 1 --branch "v${ROCKSDB_VERSION}" https://github.com/facebook/rocksdb "$WORKDIR/rocksdb-${ROCKSDB_VERSION}"' \
    "$SRC/scripts/install-rocksdb.sh" > "$SRC/install-rocksdb-git.sh"
  if grep -q 'rocksdb\.tar\.gz' "$SRC/install-rocksdb-git.sh" \
    || ! grep -q '^git clone .*facebook/rocksdb' "$SRC/install-rocksdb-git.sh"; then
    echo "could not replace the tarball download in install-rocksdb.sh; update this profile" >&2
    exit 1
  fi
  log "building librocksdb into $ROCKSDB_HOME (about 20 minutes)"
  # RocksDB builds with -Werror. GCC 12 gives a false -Wrestrict warning in
  # std::string (options/db_options.cc), which stops the build.
  CXXFLAGS="${CXXFLAGS:-} -Wno-restrict -Wno-error=restrict" \
    PREFIX="$ROCKSDB_HOME" ZSTD_HOME="$ZSTD_HOME" bash "$SRC/install-rocksdb-git.sh"
  echo "$LIBS_KEY" > "$ROCKSDB_HOME/.dot-env-key"
fi

# --- Environment for every session ---------------------------------------------
# Same values as CI (.github/actions/setup-go/action.yml).
cat > "$STATE_DIR/stellar-rpc.env" <<EOF
export PATH="$GO_ROOT/bin:\$PATH"
export CGO_CFLAGS="-I$ZSTD_HOME/include -I$ROCKSDB_HOME/include"
export CGO_LDFLAGS="-L$ZSTD_HOME/lib -L$ROCKSDB_HOME/lib"
export LD_LIBRARY_PATH="$ZSTD_HOME/lib:$ROCKSDB_HOME/lib\${LD_LIBRARY_PATH:+:\$LD_LIBRARY_PATH}"
export GOFLAGS=-tags=grocksdb_clean_link
EOF
log "wrote $STATE_DIR/stellar-rpc.env"

# --- golangci-lint -------------------------------------------------------------
LINT_VER="$(sed -n 's/^ *version: *\(v[0-9][0-9.]*\).*golangci-lint version.*/\1/p' \
  "$SRC/.github/workflows/golang.yml" | head -1)"
[ -n "$LINT_VER" ] || { echo "golangci-lint pin not found in golang.yml" >&2; exit 1; }
if golangci-lint version 2>/dev/null | grep -q "version ${LINT_VER#v} .*go$GO_WANT"; then
  log "golangci-lint $LINT_VER already installed"
else
  log "installing golangci-lint $LINT_VER into /usr/local/bin"
  GOFLAGS='' GOBIN=/usr/local/bin go install "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$LINT_VER"
fi

# --- Rust preflight libs -------------------------------------------------------
# cgo finds them under <checkout>/target, so each checkout needs its own. A git
# worktree can use: ln -s "$REPO_DIR/target" <worktree>/target
if [ -f "$REPO_DIR/Makefile" ]; then
  log "make build-libs in $REPO_DIR"
  make -C "$REPO_DIR" build-libs
else
  log "no checkout at $REPO_DIR; run 'make build-libs' in the session"
fi

log "go=$(go env GOVERSION) lint=$(golangci-lint version --short 2>/dev/null || echo '?') libs=$LIBS_KEY"
