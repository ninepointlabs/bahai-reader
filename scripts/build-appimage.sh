#!/bin/sh
# Build the host-GTK AppImage plus its .zsync and .sha256. Needs curl, zsyncmake
# (package "zsync") and, when available, desktop-file-validate and appstreamcli.
set -eu
cd "$(dirname "$0")/.."
VERSION=$(cat VERSION)
ROOT=${APPDIR:-"$PWD/.build/AppDir"}
OUT=${1:-"$PWD/dist/bahai-reader-${VERSION}-x86_64.AppImage"}
UPDATE_INFO=${UPDATE_INFO:-"gh-releases-zsync|ninepointlabs|bahai-reader|latest|bahai-reader-*x86_64.AppImage.zsync"}
APPIMAGETOOL_URL=https://github.com/AppImage/appimagetool/releases/download/1.9.1/appimagetool-x86_64.AppImage
APPIMAGETOOL_SHA256=ed4ce84f0d9caff66f50bcca6ff6f35aae54ce8135408b3fa33abfc3cb384eb0
RUNTIME_URL=https://github.com/AppImage/type2-runtime/releases/download/20251108/runtime-x86_64
RUNTIME_SHA256=2fca8b443c92510f1483a883f60061ad09b46b978b2631c807cd873a47ec260d

grep -q "<release version=\"$VERSION\"" packaging/org.bahai.Reader.metainfo.xml || {
  echo "packaging/org.bahai.Reader.metainfo.xml has no <release> for $VERSION" >&2
  exit 1
}
command -v zsyncmake >/dev/null || { echo "zsyncmake is required (install the zsync package)" >&2; exit 1; }

rm -rf "$ROOT"
mkdir -p "$ROOT/usr/share/bahai-reader/data" "$ROOT/usr/share/applications" "$ROOT/usr/share/metainfo" "$ROOT/usr/share/licenses/bahai-reader"
cp reader.py VERSION "$ROOT/usr/share/bahai-reader/"
cp data/*.json "$ROOT/usr/share/bahai-reader/data/"
cp LICENSE DATA-NOTICE.md "$ROOT/usr/share/licenses/bahai-reader/"
cp packaging/AppRun "$ROOT/AppRun"
chmod 0755 "$ROOT/AppRun"
{ cat packaging/org.bahai.Reader.desktop; echo "X-AppImage-Version=$VERSION"; } > "$ROOT/usr/share/applications/org.bahai.Reader.desktop"
cp "$ROOT/usr/share/applications/org.bahai.Reader.desktop" "$ROOT/org.bahai.Reader.desktop"
# appimagetool validates AppStream data found under this name.
cp packaging/org.bahai.Reader.metainfo.xml "$ROOT/usr/share/metainfo/org.bahai.Reader.appdata.xml"
cp -R packaging/icons "$ROOT/usr/share/"
mkdir -p "$ROOT/usr/share/icons/hicolor/scalable/apps"
cp packaging/org.bahai.Reader.svg "$ROOT/usr/share/icons/hicolor/scalable/apps/"
cp packaging/icons/hicolor/256x256/apps/org.bahai.Reader.png "$ROOT/org.bahai.Reader.png"
ln -s usr/share/icons/hicolor/256x256/apps/org.bahai.Reader.png "$ROOT/.DirIcon"

if command -v desktop-file-validate >/dev/null; then desktop-file-validate "$ROOT/org.bahai.Reader.desktop"; fi
if command -v appstreamcli >/dev/null; then appstreamcli validate --no-net "$ROOT/usr/share/metainfo/org.bahai.Reader.appdata.xml"; fi

fetch() { # url sha256 destination
  if [ ! -f "$3" ] || ! echo "$2  $3" | sha256sum -c --status; then
    mkdir -p "$(dirname "$3")"
    curl -fsSL "$1" -o "$3.part"
    echo "$2  $3.part" | sha256sum -c --quiet
    mv "$3.part" "$3"
  fi
}
tool=${APPIMAGETOOL:-"$PWD/.build/appimagetool-1.9.1-x86_64.AppImage"}
runtime="$PWD/.build/type2-runtime-20251108-x86_64"
[ -n "${APPIMAGETOOL:-}" ] || fetch "$APPIMAGETOOL_URL" "$APPIMAGETOOL_SHA256" "$tool"
fetch "$RUNTIME_URL" "$RUNTIME_SHA256" "$runtime"
chmod 0755 "$tool"

mkdir -p "$(dirname "$OUT")"
OUT=$(CDPATH= cd -- "$(dirname "$OUT")" && pwd)/$(basename "$OUT")
rm -f "$OUT" "$OUT.zsync" "$OUT.sha256"
# Extract-and-run lets the build work in containers without FUSE.
(cd "$(dirname "$OUT")" && ARCH=x86_64 APPIMAGE_EXTRACT_AND_RUN=1 "$tool" --runtime-file "$runtime" -u "$UPDATE_INFO" "$ROOT" "$OUT")
test -f "$OUT.zsync" || { echo "appimagetool did not write $OUT.zsync" >&2; exit 1; }
(cd "$(dirname "$OUT")" && sha256sum "$(basename "$OUT")" > "$(basename "$OUT").sha256")
echo "created AppImage: $OUT ($(du -h "$OUT" | cut -f1))"
