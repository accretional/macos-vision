#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
IMG="$ROOT/sample_data/input/images"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

img="$IMG/sad_pablo.png"
if [ ! -f "$img" ]; then fail "sad_pablo.png not found"; echo "0 passed, 1 failed"; exit 1; fi

# ── foreground-mask ───────────────────────────────────────────────────────────
echo "── segment: foreground-mask ─────────────────────────────────────────────────"
"$BINARY" segment --input "$img" --operation foreground-mask --output "$TMP"
got="$TMP/segment_foreground_mask.png"
if [ -f "$got" ]; then
    pass "foreground-mask: output produced"

    got_w=$(sips -g pixelWidth  "$got" | awk '/pixelWidth/  {print $2}')
    got_h=$(sips -g pixelHeight "$got" | awk '/pixelHeight/ {print $2}')
    ref_w=$(sips -g pixelWidth  "$img" | awk '/pixelWidth/  {print $2}')
    ref_h=$(sips -g pixelHeight "$img" | awk '/pixelHeight/ {print $2}')
    [ "$got_w" = "$ref_w" ] && [ "$got_h" = "$ref_h" ] \
        && pass "foreground-mask: dimensions match (${got_w}x${got_h})" \
        || fail "foreground-mask: dimension mismatch (got ${got_w}x${got_h}, expected ${ref_w}x${ref_h})"

    alpha=$(sips -g hasAlpha "$got" | awk '/hasAlpha/ {print $2}')
    [ "$alpha" = "yes" ] && pass "foreground-mask: has alpha channel" || fail "foreground-mask: no alpha channel"
else
    fail "foreground-mask: output not produced"
fi
echo

# ── error handling ────────────────────────────────────────────────────────────
echo "── segment: error handling ──────────────────────────────────────────────────"
err=$("$BINARY" segment 2>&1 || true)
echo "$err" | grep -qiE "img|input|must be provided|provide|error" && pass "segment: missing input error shown" || fail "segment: no error on missing input"
err=$("$BINARY" segment --input "$img" --operation bad-op 2>&1 || true)
echo "$err" | grep -qi "unknown\|supported\|error" && pass "segment: unknown operation rejected" || fail "segment: unknown operation not rejected"
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
