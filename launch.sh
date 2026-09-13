#!/bin/sh
set -eu
root=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
if command -v uwsm-app >/dev/null 2>&1 && [ -n "${HYPRLAND_INSTANCE_SIGNATURE:-}" ]; then
  exec uwsm-app -- /usr/bin/python3 "$root/reader.py" "$@"
fi
exec /usr/bin/python3 "$root/reader.py" "$@"
