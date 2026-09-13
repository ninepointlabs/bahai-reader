#!/bin/sh
set -eu
# Pinned builder; verify the official checksum before executing it.
dest="${1:?destination directory required}"
mkdir -p "$dest"
base=https://github.com/goreleaser/nfpm/releases/download/v2.47.0
archive=nfpm_2.47.0_Linux_x86_64.tar.gz
curl -fsSL "$base/$archive" -o "$dest/$archive"
curl -fsSL "$base/checksums.txt" -o "$dest/checksums.txt"
(cd "$dest" && awk -v file="$archive" '$2 == file { print }' checksums.txt > selected-checksum && test -s selected-checksum && sha256sum -c selected-checksum && tar -xzf "$archive" nfpm)
