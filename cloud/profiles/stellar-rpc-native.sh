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
FORMAT=2
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

# git_source <script> <name> <version var>: prints <script> with its
# `curl ... <name>.tar.gz` and `tar xzf ... <name>.tar.gz` lines replaced by a
# git clone of github.com/facebook/<name> at tag v$<version var>, into the
# directory the script's cmake step reads. Fails when the lines are not found.
git_source() {
  local script="$1" name="$2" var="$3" out
  out="$(sed "/^curl .*${name}\.tar\.gz/,/^tar xzf .*${name}\.tar\.gz/c\\
git clone -q --depth 1 --branch \"v\${${var}}\" https://github.com/facebook/${name} \"\$WORKDIR/${name}-\${${var}}\"" "$script")"
  if grep -q "${name}\.tar\.gz" <<<"$out" || ! grep -q "^git clone .*facebook/${name}" <<<"$out"; then
    echo "could not replace the tarball download in $script; update $0" >&2
    return 1
  fi
  printf '%s\n' "$out"
}

build() {
  local src="$1" out="$2" k lint work
  k="$(key "$src")"
  lint="$(lint_version "$src")"
  mkdir -p "$out/bin"
  work="$(mktemp -d)"

  # In cloud sessions, GitHub archive and release-asset downloads can be blocked
  # for repositories not attached to the session; git clone works there and in CI.
  # Replace each script's tarball download with a clone of the same tag.
  git_source "$src/scripts/install-zstd.sh" zstd ZSTD_VERSION > "$work/install-zstd.sh"
  git_source "$src/scripts/install-rocksdb.sh" rocksdb ROCKSDB_VERSION > "$work/install-rocksdb.sh"

  echo "native: building libzstd"
  PREFIX="$out/.zstd" bash "$work/install-zstd.sh"

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
