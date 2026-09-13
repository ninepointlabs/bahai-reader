#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
dest="${XDG_DATA_HOME:-$HOME/.local/share}/applications"
mkdir -p "$dest"
cat > "$dest/org.bahai.Reader.desktop" <<EOF
[Desktop Entry]
Type=Application
Name=Bahá’í Reader
Comment=Prayers, Hidden Words and Bahá’í writings
Exec="$root/launch.sh"
Icon=accessories-dictionary
Terminal=false
Categories=Education;Literature;
StartupNotify=true
EOF
