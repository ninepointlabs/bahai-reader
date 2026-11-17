#!/bin/sh
# Converts the rendered desktop screenshots (scripts/screenshots/out/*.png) to the site's WebP files.
set -eu
cd "$(dirname "$0")/../.."
for f in scripts/screenshots/out/*.png; do
  magick "$f" -quality 85 "docs/screenshots/$(basename "${f%.png}").webp"
done
