#!/bin/sh
# Regenerate the committed hicolor PNGs from packaging/org.bahai.Reader.svg. Needs rsvg-convert.
set -eu
cd "$(dirname "$0")/.."
for size in 16 24 32 48 64 128 256 512; do
  dir="packaging/icons/hicolor/${size}x${size}/apps"
  mkdir -p "$dir"
  rsvg-convert -w "$size" -h "$size" packaging/org.bahai.Reader.svg -o "$dir/org.bahai.Reader.png"
done
