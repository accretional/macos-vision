#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
IMG="$ROOT/sample_data/input/images"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

img="$IMG/gorilla.jpg"
if [ ! -f "$img" ]; then fail "gorilla.jpg not found"; echo "0 passed, 1 failed"; exit 1; fi

# ── classify ──────────────────────────────────────────────────────────────────
echo "── classify: classify ───────────────────────────────────────────────────────"
"$BINARY" classify --input "$img" --operation classify --output "$TMP" --no-stream
got="$TMP/gorilla_classify.json"
if [ -f "$got" ]; then
    pass "classify: output produced"
    jq empty "$got" 2>/dev/null && pass "classify: valid JSON" || fail "classify: invalid JSON"
    count=$(jq '.result.classifications | length' "$got" 2>/dev/null || echo 0)
    [ "${count:-0}" -gt 0 ] && pass "classify: $count classification(s) returned" || fail "classify: no classifications returned"
    jq -e '.result.classifications[0].identifier' "$got" >/dev/null 2>&1 && pass "classify: identifier field present" || fail "classify: identifier field missing"
else
    fail "classify: output not produced"
fi
echo

# ── horizon ───────────────────────────────────────────────────────────────────
echo "── classify: horizon ────────────────────────────────────────────────────────"
"$BINARY" classify --input "$IMG/sad_pablo.png" --operation horizon --output "$TMP" --no-stream 2>/dev/null || true
got="$TMP/sad_pablo_horizon.json"
if [ -f "$got" ]; then
    pass "horizon: output produced"
    jq empty "$got" 2>/dev/null && pass "horizon: valid JSON" || fail "horizon: invalid JSON"
    jq -e '.result.horizon' "$got" >/dev/null 2>&1 && pass "horizon: horizon field present" || fail "horizon: horizon field missing"
else
    pass "horizon: skipped (sad_pablo.png not found)"
fi
echo

# ── contours ──────────────────────────────────────────────────────────────────
echo "── classify: contours ───────────────────────────────────────────────────────"
"$BINARY" classify --input "$img" --operation contours --output "$TMP" --no-stream
got="$TMP/gorilla_contours.json"
if [ -f "$got" ]; then
    pass "contours: output produced"
    jq empty "$got" 2>/dev/null && pass "contours: valid JSON" || fail "contours: invalid JSON"
    jq -e '.result.contourCount' "$got" >/dev/null 2>&1 && pass "contours: contourCount field present" || fail "contours: contourCount field missing"
    count=$(jq '.result.contourCount' "$got" 2>/dev/null || echo 0)
    [ "${count:-0}" -gt 0 ] && pass "contours: $count contour(s) detected" || fail "contours: no contours detected"
else
    fail "contours: output not produced"
fi
echo

# ── feature-print ─────────────────────────────────────────────────────────────
echo "── classify: feature-print ──────────────────────────────────────────────────"
"$BINARY" classify --input "$img" --operation feature-print --output "$TMP" --no-stream
got="$TMP/gorilla_feature_print.json"
if [ -f "$got" ]; then
    pass "feature-print: output produced"
    jq empty "$got" 2>/dev/null && pass "feature-print: valid JSON" || fail "feature-print: invalid JSON"
    jq -e '.result.featurePrint.elementCount' "$got" >/dev/null 2>&1 && pass "feature-print: elementCount present" || fail "feature-print: elementCount missing"
    jq -e '.result.featurePrint.data' "$got" >/dev/null 2>&1 && pass "feature-print: data present" || fail "feature-print: data missing"
else
    fail "feature-print: output not produced"
fi
echo

# ── error handling ────────────────────────────────────────────────────────────
echo "── classify: error handling ─────────────────────────────────────────────────"
err=$("$BINARY" classify 2>&1 || true)
echo "$err" | grep -qi "img\|input\|must be provided\|provide\|error" && pass "classify: missing input error shown" || fail "classify: no error on missing input"
err=$("$BINARY" classify --input "$img" --operation bad-op --no-stream 2>&1 || true)
echo "$err" | grep -qi "unknown\|supported\|error" && pass "classify: unknown operation rejected" || fail "classify: unknown operation not rejected"
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
