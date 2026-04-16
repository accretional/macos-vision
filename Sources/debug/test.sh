#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
IMG="$ROOT/sample_data/input/images"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

img="$IMG/handwriting.png"
if [ ! -f "$img" ]; then fail "handwriting.png not found"; echo "0 passed, 1 failed"; exit 1; fi

# ── single image ──────────────────────────────────────────────────────────────
echo "── debug: single image ──────────────────────────────────────────────────────"
"$BINARY" debug --input "$img" --output "$TMP"
got="$TMP/handwriting.json"
if [ -f "$got" ]; then
    pass "debug: output produced"
    jq empty "$got" 2>/dev/null && pass "debug: valid JSON" || fail "debug: invalid JSON"
    for field in filename filepath width height filesize; do
        val=$(jq -r ".result.$field // empty" "$got")
        [ -n "$val" ] && pass "debug: $field present ($val)" || fail "debug: $field missing"
    done
    w=$(jq '.result.width'  "$got"); [ "$w" = "1600" ] && pass "debug: width=1600"  || fail "debug: width (got $w)"
    h=$(jq '.result.height' "$got"); [ "$h" = "720"  ] && pass "debug: height=720"  || fail "debug: height (got $h)"
    fn=$(jq -r '.result.filename' "$got"); [ "$fn" = "handwriting.png" ] && pass "debug: filename correct" || fail "debug: filename (got $fn)"
else
    fail "debug: output not produced"
fi
echo

# ── error handling ────────────────────────────────────────────────────────────
echo "── debug: error handling ────────────────────────────────────────────────────"
err=$("$BINARY" debug 2>&1 || true)
echo "$err" | grep -qi "img\|input\|must be provided\|provide\|error" && pass "debug: missing input error shown" || fail "debug: no error on missing input"
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
