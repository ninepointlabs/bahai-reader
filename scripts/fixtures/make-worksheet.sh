#!/bin/sh
# Rebuilds the Study test PDFs from our own sample text: test/fixtures/worksheet.pdf (two pages) and
# test/fixtures/worksheet-2.pdf (a "revised edition": a paragraph added at the top moves everything down).
set -eu
cd "$(dirname "$0")/../.."
for name in worksheet worksheet-2; do
  chromium --headless=new --no-sandbox --disable-gpu --no-pdf-header-footer --generate-pdf-document-outline \
    --print-to-pdf="test/fixtures/$name.pdf" "scripts/fixtures/$name.html"
done
