#!/bin/sh
# Check a built AppImage on a host with Python 3.11+, PyGObject and GTK 4.8+.
# Run under Xvfb: xvfb-run -a tests/appimage_check.sh dist/bahai-reader-<version>-x86_64.AppImage
# Needs desktop-file-validate and xprop/xwininfo (x11-utils).
set -eu
app=$(CDPATH= cd -- "$(dirname -- "$1")" && pwd)/$(basename -- "$1")
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
export APPIMAGE_EXTRACT_AND_RUN=1

"$app" --check-host

# Opt-in menu entry: created, valid, pointing at the AppImage, then removed again.
XDG_DATA_HOME="$work/data" "$app" --install-desktop-entry
desktop-file-validate "$work/data/applications/org.bahai.Reader.desktop"
grep -qx "Exec=\"$app\"" "$work/data/applications/org.bahai.Reader.desktop"
for size in 16 24 32 48 64 128 256 512; do
  test -f "$work/data/icons/hicolor/${size}x${size}/apps/org.bahai.Reader.png"
done
test -f "$work/data/icons/hicolor/scalable/apps/org.bahai.Reader.svg"
XDG_DATA_HOME="$work/data" "$app" --remove-desktop-entry
test -z "$(find "$work/data" -name 'org.bahai.Reader*')"

# Fresh home, no Omarchy or Hyprland tools: the app starts with its own palette.
HOME="$work/home" PATH=/usr/bin:/bin "$app" >"$work/app.log" 2>&1 &
pid=$!
sleep 8
kill -0 "$pid" || { cat "$work/app.log"; echo "AppImage exited early" >&2; exit 1; }
class=
for win in $(xwininfo -root -children | grep -o '^ *0x[0-9a-f]*'); do
  if xprop -id "$win" _GTK_APPLICATION_ID 2>/dev/null | grep -q '"org.bahai.Reader"'; then
    class=$(xprop -id "$win" WM_CLASS)
  fi
done
kill "$pid"
wait "$pid" 2>/dev/null || true
cat "$work/app.log"
if grep -q Traceback "$work/app.log"; then echo "Python traceback in AppImage output" >&2; exit 1; fi
echo "$class"
test "$class" = 'WM_CLASS(STRING) = "org.bahai.Reader", "org.bahai.Reader"'
echo "AppImage check passed"
