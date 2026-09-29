#!/usr/bin/env bash
# The prebuilt part of the stellar-rpc cloud toolchain: libzstd, librocksdb and
# golangci-lint. A RocksDB build takes about 20 minutes, and a cloud setup script
# must finish in about 5 minutes to be cached. So the workflow
# .github/workflows/stellar-rpc-native.yml builds this once, and cloud setup
# downloads the result from the "artifacts" branch.
#
#   stellar-rpc-native.sh key   <stellar-rpc checkout>          # prints the key
#   stellar-rpc-native.sh build <stellar-rpc checkout> <outdir> # builds into outdir
#   stellar-rpc-native.sh url   <key>                           # prints the download URL
#
# build writes <outdir>/.zstd, <outdir>/.rocksdb, <outdir>/bin/golangci-lint and
# <outdir>/.rocksdb/.dot-env-key. It needs a Go at the go.mod version or newer
# (or GOTOOLCHAIN=auto) on PATH.
set -euo pipefail

# Increase when the layout of the output changes.
FORMAT=1
ARTIFACT_REPO=marwen-abid/dot-env
ARTIFACT_BRANCH=artifacts

lint_version() {
  sed -n 's/^ *version: *\(v[0-9][0-9.]*\).*golangci-lint version.*/\1/p' \
    "$1/.github/workflows/golang.yml" | head -1
}

key() {
  local src="$1" lint
  lint="$(lint_version "$src")"
  [ -n "$lint" ] || { echo "golangci-lint pin not found in $src/.github/workflows/golang.yml" >&2; exit 1; }
  { echo "format=$FORMAT lint=$lint arch=$(uname -m)"
    cat "$src/scripts/install-zstd.sh" "$src/scripts/install-rocksdb.sh"; } \
    | sha256sum | cut -c1-16
}

build() {
  local src="$1" out="$2" k lint work
  k="$(key "$src")"
  lint="$(lint_version "$src")"
  mkdir -p "$out/bin"
  work="$(mktemp -d)"

  echo "native: building libzstd"
  PREFIX="$out/.zstd" bash "$src/scripts/install-zstd.sh"

  # GitHub archive URLs can be blocked in cloud sessions; git clone works there
  # and in CI. Replace the tarball download with a clone of the same tag.
  # shellcheck disable=SC2016 # the variables expand inside the generated script
  sed '/^curl .*rocksdb\.tar\.gz/,/^tar xzf .*rocksdb\.tar\.gz/c\
git clone -q --depth 1 --branch "v${ROCKSDB_VERSION}" https://github.com/facebook/rocksdb "$WORKDIR/rocksdb-${ROCKSDB_VERSION}"' \
    "$src/scripts/install-rocksdb.sh" > "$work/install-rocksdb.sh"
  if grep -q 'rocksdb\.tar\.gz' "$work/install-rocksdb.sh" \
    || ! grep -q '^git clone .*facebook/rocksdb' "$work/install-rocksdb.sh"; then
    echo "could not replace the tarball download in install-rocksdb.sh; update $0" >&2
    exit 1
  fi
  echo "native: building librocksdb"
  # RocksDB builds with -Werror. GCC 12 gives a false -Wrestrict warning in
  # std::string (options/db_options.cc), which stops the build.
  CXXFLAGS="${CXXFLAGS:-} -Wno-restrict -Wno-error=restrict" \
    PREFIX="$out/.rocksdb" ZSTD_HOME="$out/.zstd" bash "$work/install-rocksdb.sh"
  rm -rf "$work"

  echo "native: building golangci-lint $lint"
  (cd "$src" && GOFLAGS='' GOBIN="$out/bin" go install -ldflags='-s -w' \
    "github.com/golangci/golangci-lint/v2/cmd/golangci-lint@$lint")

  echo "$k" > "$out/.rocksdb/.dot-env-key"
  echo "native: done ($k)"
}

case "${1:-}" in
  key) key "$2" ;;
  build) build "$2" "$3" ;;
  url) echo "https://raw.githubusercontent.com/$ARTIFACT_REPO/$ARTIFACT_BRANCH/stellar-rpc-native-$2.tar.gz" ;;
  *) echo "usage: $0 key <src> | build <src> <out> | url <key>" >&2; exit 2 ;;
esac
