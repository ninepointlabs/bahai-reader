#!/bin/sh
# .deb, .rpm and pacman packages from the Linux release bundle (flutter build linux --release first).
set -eu
cd "$(dirname "$0")/.."
VERSION=$(scripts/version.sh)
export VERSION
test -x build/linux/x64/release/bundle/bahai-reader || { echo "Run flutter build linux --release first" >&2; exit 1; }
mkdir -p dist
for format in deb rpm archlinux; do
  "${NFPM:-nfpm}" package --config packaging/nfpm.yaml --packager "$format" --target dist/
done
