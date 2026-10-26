#!/bin/sh
# Desktop-entry install/remove from the AppImage launcher, without building an AppImage.
# Needs desktop-file-validate; uses GIO from python3-gi when available.
set -eu
repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
appdir=$work/AppDir
mkdir -p "$appdir/usr/share/bahai-reader"
cp "$repo/packaging/AppRun" "$appdir/AppRun"
cp "$repo/VERSION" "$appdir/usr/share/bahai-reader/"
{ cat "$repo/packaging/org.bahai.Reader.desktop"; echo "X-AppImage-Version=test"; } > "$appdir/org.bahai.Reader.desktop"
mkdir -p "$appdir/usr/share/icons"; cp -R "$repo/packaging/icons/hicolor" "$appdir/usr/share/icons/"
mkdir -p "$appdir/usr/share/icons/hicolor/scalable/apps"; cp "$repo/packaging/org.bahai.Reader.svg" "$appdir/usr/share/icons/hicolor/scalable/apps/"
entry=$work/data/applications/org.bahai.Reader.desktop
icon=$work/data/icons/hicolor/256x256/apps/org.bahai.Reader.png
run() { APPDIR=$appdir XDG_DATA_HOME=$work/data "$appdir/AppRun" "$@"; }

# A path with % (QA L11): valid entry, loadable by GIO, and it starts the right file.
mkdir -p "$work/dl 100%"
printf '#!/bin/sh\nprintf "%%s" "$0" > "%s/launched"\n' "$work" > "$work/dl 100%/app.AppImage"
chmod +x "$work/dl 100%/app.AppImage"
APPIMAGE="$work/dl 100%/app.AppImage" run --install-desktop-entry >/dev/null
desktop-file-validate "$entry"
if /usr/bin/python3 -c 'import gi' 2>/dev/null; then
    /usr/bin/python3 -W ignore -c '
import sys, time
from gi.repository import Gio
info = Gio.DesktopAppInfo.new_from_filename(sys.argv[1])
info.launch([], None)
for _ in range(50):
    try: print(open(sys.argv[2]).read()); break
    except OSError: time.sleep(0.1)
' "$entry" "$work/launched" > "$work/gio.out"
    test "$(cat "$work/gio.out")" = "$work/dl 100%/app.AppImage"
fi
run --remove-desktop-entry >/dev/null
test ! -e "$entry" && test ! -e "$icon"

# A plain path keeps the plain Exec line.
APPIMAGE="$work/Bahai Reader.AppImage" run --install-desktop-entry >/dev/null
grep -qx "Exec=\"$work/Bahai Reader.AppImage\"" "$entry"
run --remove-desktop-entry >/dev/null

# Someone else's entry and icons with the same name are left alone (QA L10).
mkdir -p "$(dirname "$entry")" "$(dirname "$icon")"
printf '[Desktop Entry]\nType=Application\nName=Other\nExec=other\n' > "$entry"
cp "$appdir/usr/share/icons/hicolor/256x256/apps/org.bahai.Reader.png" "$icon"
run --remove-desktop-entry >/dev/null 2>&1
test -f "$entry" && test -f "$icon"
# A changed icon is not ours even without an entry.
rm "$entry"; printf 'other icon' > "$icon"
run --remove-desktop-entry >/dev/null 2>&1
test -f "$icon"
echo "AppRun desktop entry check passed"
