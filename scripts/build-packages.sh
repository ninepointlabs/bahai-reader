#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
export VERSION
mkdir -p dist
for format in deb rpm archlinux; do
  "${NFPM:-nfpm}" package --config packaging/nfpm.yaml --packager "$format" --target dist/
done
(cd dist && sha256sum ./*.deb ./*.rpm ./*.pkg.tar.zst > SHA256SUMS)
