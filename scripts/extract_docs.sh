#!/usr/bin/env bash
# Extracts all /documentation/... paths from docs.txt and prints them deduplicated.
# Usage: bash scripts/extract_docs.sh
set -euo pipefail

DOCS="$(dirname "$0")/../docs3.txt"

if [ ! -s "$DOCS" ]; then
    echo "docs.txt is empty or missing — paste the page source into it first." >&2
    exit 1
fi

grep -oE '/documentation/[a-zA-Z0-9._/-]+' "$DOCS" \
    | sort -u \
    | sed 's|^|https://developer.apple.com|' > links2.txt
