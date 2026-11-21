#!/bin/sh
# Rebuilds test/fixtures/worksheet.pdf, a two-page sample workbook (our own text) for the Study tests.
set -eu
cd "$(dirname "$0")/../.."
chromium --headless=new --no-sandbox --disable-gpu --no-pdf-header-footer --generate-pdf-document-outline \
  --print-to-pdf=test/fixtures/worksheet.pdf scripts/fixtures/worksheet.html
