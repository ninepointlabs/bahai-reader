#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
ROOT=${APPDIR:-"$PWD/.build/AppDir"}
OUT=${1:-"$PWD/dist/bahai-reader-${VERSION}-x86_64.AppImage"}
rm -rf "$ROOT"
mkdir -p "$ROOT/usr/share/bahai-reader/data" "$ROOT/usr/bin" "$ROOT/usr/share/applications" "$ROOT/usr/share/icons/hicolor/scalable/apps"
cp reader.py "$ROOT/usr/share/bahai-reader/reader.py"
cp data/*.json "$ROOT/usr/share/bahai-reader/data/"
cp packaging/AppRun "$ROOT/AppRun"
cp packaging/org.bahai.Reader.desktop "$ROOT/org.bahai.Reader.desktop"
cp packaging/org.bahai.Reader.desktop "$ROOT/usr/share/applications/org.bahai.Reader.desktop"
cp packaging/org.bahai.Reader.svg "$ROOT/org.bahai.Reader.svg"
cp packaging/org.bahai.Reader.svg "$ROOT/usr/share/icons/hicolor/scalable/apps/org.bahai.Reader.svg"
chmod 0755 "$ROOT/AppRun"
mkdir -p "$(dirname "$OUT")"
tool=${APPIMAGETOOL:-"$PWD/.build/appimagetool.AppImage"}
if [ ! -x "$tool" ]; then
  mkdir -p "$(dirname "$tool")"
  url=https://github.com/AppImage/appimagetool/releases/download/continuous/appimagetool-x86_64.AppImage
  curl -fL "$url" -o "$tool"
  chmod 0755 "$tool"
fi
ARCH=x86_64 "$tool" "$ROOT" "$OUT"
sha256sum "$OUT" > "$OUT.sha256"
echo "created AppImage: $OUT"
