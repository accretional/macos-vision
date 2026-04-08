#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
IMG="$ROOT/sample_data/input/images"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

img="$IMG/fred_yass.png"
if [ ! -f "$img" ]; then fail "fred_yass.png not found"; echo "0 passed, 1 failed"; exit 1; fi

# ── setup: generate face-landmarks JSON ───────────────────────────────────────
echo "── svg: setup ───────────────────────────────────────────────────────────────"
"$BINARY" face --img "$img" --operation face-landmarks --output "$TMP"
lm_json="$TMP/fred_yass_face_landmarks.json"
if [ ! -f "$lm_json" ]; then
    fail "svg: prerequisite face-landmarks JSON not produced"
    echo "0 passed, 1 failed"; exit 1
fi
pass "svg: face-landmarks JSON available"
echo

# ── face-landmarks overlay ────────────────────────────────────────────────────
echo "── svg: face-landmarks overlay ──────────────────────────────────────────────"
"$BINARY" svg --json "$lm_json" --output "$TMP"
lm_svg="$TMP/fred_yass_face_landmarks.svg"
if [ -f "$lm_svg" ]; then
    pass "svg: SVG produced"
    grep -q "<svg"    "$lm_svg" && pass "svg: <svg element present"    || fail "svg: <svg element missing"
    grep -q "<image"  "$lm_svg" && pass "svg: <image element present"  || fail "svg: <image element missing"
    grep -q "base64"  "$lm_svg" && pass "svg: base64 data present"     || fail "svg: base64 data missing"
    grep -qE "<rect|<circle|<polyline|<polygon|<line" "$lm_svg" \
        && pass "svg: shape elements present" || fail "svg: no shape elements"
else
    fail "svg: SVG not produced"
fi
echo

# ── --img override ────────────────────────────────────────────────────────────
echo "── svg: --img override ──────────────────────────────────────────────────────"
"$BINARY" svg --json "$lm_json" --img "$img" --output "$TMP"
[ -f "$lm_svg" ] && pass "svg: --img override accepted" || fail "svg: --img override failed"
echo

# ── error handling ────────────────────────────────────────────────────────────
echo "── svg: error handling ──────────────────────────────────────────────────────"
err=$("$BINARY" svg 2>&1 || true)
echo "$err" | grep -qi "json\|required\|error" && pass "svg: missing --json error shown" || fail "svg: no error on missing --json"
err=$("$BINARY" svg --json /nonexistent/path.json 2>&1 || true)
echo "$err" | grep -qi "error\|not found\|no such" && pass "svg: nonexistent JSON error shown" || fail "svg: no error for nonexistent JSON"
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
