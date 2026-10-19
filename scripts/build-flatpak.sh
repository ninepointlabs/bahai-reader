#!/bin/sh
# Build the single-file Flatpak bundle attached to GitHub releases (not published to Flathub).
# Needs flatpak and flatpak-builder with Flathub reachable for the GNOME runtime and SDK.
set -eu
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
OUT=${1:-"$PWD/dist/bahai-reader-${VERSION}-x86_64.flatpak"}
flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo
flatpak-builder --user --install-deps-from=flathub --force-clean --disable-rofiles-fuse \
  --default-branch=stable --repo=.build/flatpak-repo .build/flatpak-build packaging/flatpak/org.bahai.Reader.yml
mkdir -p "$(dirname "$OUT")"
# The runtime repo lets `flatpak install ./bundle` fetch org.gnome.Platform from Flathub.
flatpak build-bundle --runtime-repo=https://dl.flathub.org/repo/flathub.flatpakrepo \
  .build/flatpak-repo "$OUT" org.bahai.Reader stable
(cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
echo "created Flatpak bundle: $OUT ($(du -h "$OUT" | cut -f1))"
