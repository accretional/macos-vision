#!/usr/bin/env bash
# validate.sh — validate that a PNG screenshot file is non-empty and well-formed.
# Usage: validate.sh <path-to-png>
# Exits 0 on pass, 1 on fail.

set -euo pipefail

die() { printf '\033[1;31m[validate]\033[0m %s\n' "$*" >&2; exit 1; }
ok()  { printf '\033[1;32m[validate]\033[0m %s\n' "$*"; }

PNG="$1"

[ -f "$PNG" ] || die "not found: $PNG"

# Minimum size: a real headless-Chrome screenshot is hundreds of KB.
# We accept anything over 1 KB to weed out placeholder writes.
SIZE=$(wc -c < "$PNG" | tr -d ' ')
[ "$SIZE" -gt 1024 ] || die "$PNG is too small ($SIZE bytes) — expected a real PNG screenshot (>1KB)"

# Check PNG magic bytes: 89 50 4E 47 0D 0A 1A 0A
MAGIC=$(dd if="$PNG" bs=1 count=4 2>/dev/null | od -A n -t x1 | tr -d ' \n')
[ "$MAGIC" = "89504e47" ] || die "$PNG does not start with PNG magic bytes (got: $MAGIC)"

ok "$PNG — ${SIZE} bytes, valid PNG header"
