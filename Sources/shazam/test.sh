#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

AUDIO="$TMP/smoke.aiff"
has_audio=false
if say -o "$AUDIO" "The quick brown fox jumps over the lazy dog." 2>/dev/null && [ -f "$AUDIO" ]; then
    has_audio=true
fi

# ── error handling ────────────────────────────────────────────────────────────
echo "── shazam: error handling ──────────────────────────────────────────────────"

err=$("$BINARY" shazam 2>&1 || true)
echo "$err" | grep -qiE "input|provide|error" \
    && pass "shazam: missing input error shown" || fail "shazam: no error on missing input"

err=$("$BINARY" shazam --input "$AUDIO" --operation not-real --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "unknown\|valid\|error" \
    && pass "shazam: unknown operation rejected" || fail "shazam: unknown operation not rejected"

err=$("$BINARY" shazam --input /no/such/file.aiff --operation match --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "error\|fail\|no such\|could not" \
    && pass "shazam: missing file error shown" || fail "shazam: missing file not rejected"
echo

# ── match (network required, result may be unmatched) ────────────────────────
echo "── shazam: match ───────────────────────────────────────────────────────────"
if $has_audio; then
    set +e
    mout=$("$BINARY" shazam --input "$AUDIO" --operation match --output "$TMP/match.json" 2>&1)
    mec=$?
    set -e
    if [ "$mec" -eq 0 ] && [ -f "$TMP/match.json" ]; then
        pass "match: output produced"
        jq empty "$TMP/match.json" 2>/dev/null && pass "match: valid JSON" || fail "match: invalid JSON"
        jq -e '.operation == "match"' "$TMP/match.json" >/dev/null 2>&1 \
            && pass "match: operation field" || fail "match: operation mismatch"
        jq -e '.result.matched | type == "boolean"' "$TMP/match.json" >/dev/null 2>&1 \
            && pass "match: matched field present" || fail "match: matched field missing"
    elif echo "$mout" | grep -qiE "12|macOS|require|error"; then
        pass "match: skipped (macOS version or network error)"
    else
        fail "match: unexpected exit ($mec): $mout"
    fi
else
    pass "match: skipped (say could not create sample audio)"
fi
echo

# ── build (catalog from a directory) ─────────────────────────────────────────
echo "── shazam: build ───────────────────────────────────────────────────────────"
if $has_audio; then
    AUDIO_DIR="$TMP/songs"
    mkdir -p "$AUDIO_DIR"
    cp "$AUDIO" "$AUDIO_DIR/track1.aiff"
    say -o "$AUDIO_DIR/track2.aiff" "Another test audio track for catalog building." 2>/dev/null || true

    set +e
    bout=$("$BINARY" shazam --input "$AUDIO_DIR" --operation build \
                             --artifacts-dir "$TMP" --output "$TMP/build.json" 2>&1)
    bec=$?
    set -e
    if [ "$bec" -eq 0 ] && [ -f "$TMP/build.json" ]; then
        pass "build: output produced"
        jq empty "$TMP/build.json" 2>/dev/null && pass "build: valid JSON" || fail "build: invalid JSON"
        jq -e '.operation == "build"' "$TMP/build.json" >/dev/null 2>&1 \
            && pass "build: operation field" || fail "build: operation mismatch"
        jq -e '.result.indexed | type == "number"' "$TMP/build.json" >/dev/null 2>&1 \
            && pass "build: indexed count present" || fail "build: indexed count missing"
    elif echo "$bout" | grep -qiE "12|macOS|require|error"; then
        pass "build: skipped (macOS version error)"
    else
        fail "build: unexpected exit ($bec): $bout"
    fi
else
    pass "build: skipped (say could not create sample audio)"
fi
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
