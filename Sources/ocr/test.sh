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
echo "── ocr: single image ────────────────────────────────────────────────────────"
"$BINARY" ocr --input "$img" --output "$TMP" --no-stream
got="$TMP/handwriting.json"
if [ -f "$got" ]; then
    pass "ocr: output produced"
    jq empty "$got" 2>/dev/null && pass "ocr: valid JSON" || fail "ocr: invalid JSON"
    jq -e '.result.observations' "$got" >/dev/null 2>&1 && pass "ocr: observations field present" || fail "ocr: observations field missing"
    count=$(jq '.result.observations | length' "$got" 2>/dev/null || echo 0)
    [ "${count:-0}" -gt 0 ] && pass "ocr: $count observation(s) returned" || fail "ocr: no observations returned"
    jq -e '.result.texts' "$got" >/dev/null 2>&1 && pass "ocr: texts field present" || fail "ocr: texts field missing"
    jq -e '.operation' "$got" >/dev/null 2>&1 && pass "ocr: operation field present" || fail "ocr: operation field missing"
else
    fail "ocr: output not produced"
fi
echo

# ── --lang flag ───────────────────────────────────────────────────────────────
echo "── ocr: --lang ──────────────────────────────────────────────────────────────"
lang_out=$("$BINARY" ocr --lang --no-stream 2>&1)
echo "$lang_out" | grep -q "^Supported recognition languages:" && pass "--lang: header present" || fail "--lang: header missing"
lang_count=$(echo "$lang_out" | grep -c "^- " || true)
[ "${lang_count:-0}" -gt 0 ] && pass "--lang: $lang_count languages listed" || fail "--lang: no languages listed"
echo

# ── error handling ────────────────────────────────────────────────────────────
echo "── ocr: error handling ──────────────────────────────────────────────────────"
err=$("$BINARY" ocr 2>&1 || true)
echo "$err" | grep -qi "img\|input\|must be provided\|provide\|error" && pass "ocr: missing input error shown" || fail "ocr: no error on missing input"
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
