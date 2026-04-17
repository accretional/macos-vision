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
echo "── speech: error handling ──────────────────────────────────────────────────"
err=$("$BINARY" speech 2>&1 || true)
echo "$err" | grep -qiE "audio|--input|provide|error" \
    && pass "speech: missing input error shown" || fail "speech: no error on missing input"

err=$("$BINARY" speech --input "$AUDIO" --operation not-a-real-op --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "unknown\|valid\|error" \
    && pass "speech: unknown operation rejected" || fail "speech: unknown operation not rejected"

err=$("$BINARY" speech --input /nonexistent/no_such_file.wav --operation transcribe --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "error\|fail\|not\|could\|read\|authorized" \
    && pass "speech: missing file or auth error shown" || fail "speech: missing file not rejected"
echo

# ── list-locales ──────────────────────────────────────────────────────────────
echo "── speech: list-locales ────────────────────────────────────────────────────"
"$BINARY" speech --operation list-locales --output "$TMP/locales.json"
if [ -f "$TMP/locales.json" ]; then
    pass "list-locales: output produced"
    jq empty "$TMP/locales.json" 2>/dev/null && pass "list-locales: valid JSON" || fail "list-locales: invalid JSON"
    jq -e '.operation == "list-locales"' "$TMP/locales.json" >/dev/null 2>&1 \
        && pass "list-locales: operation field" || fail "list-locales: operation mismatch"
    jq -e '.result.count | . > 0' "$TMP/locales.json" >/dev/null 2>&1 \
        && pass "list-locales: non-zero count" || fail "list-locales: count is zero"
    jq -e '.result.locales | type == "array"' "$TMP/locales.json" >/dev/null 2>&1 \
        && pass "list-locales: locales array" || fail "list-locales: locales not array"
    n=$(jq '.result.count' "$TMP/locales.json" 2>/dev/null || echo 0)
    echo "  INFO  $n supported locales"
else
    fail "list-locales: output not produced"
fi
echo

# ── transcribe (optional — requires Speech recognition permission + Developer ID signing) ───
echo "── speech: transcribe ──────────────────────────────────────────────────────"
if $has_audio; then
    set +e
    tout=$("$BINARY" speech --input "$AUDIO" --operation transcribe --output "$TMP/transcribe.json" 2>&1)
    tec=$?
    set -e
    if [ "$tec" -eq 0 ] && [ -f "$TMP/transcribe.json" ]; then
        pass "transcribe: output produced"
        jq empty "$TMP/transcribe.json" 2>/dev/null && pass "transcribe: valid JSON" || fail "transcribe: invalid JSON"
        jq -e '.operation == "transcribe"' "$TMP/transcribe.json" >/dev/null 2>&1 \
            && pass "transcribe: operation field" || fail "transcribe: operation mismatch"
        jq -e '.result.transcript | type == "string"' "$TMP/transcribe.json" >/dev/null 2>&1 \
            && pass "transcribe: transcript string" || fail "transcribe: transcript not string"
        jq -e '.result.segments | type == "array"' "$TMP/transcribe.json" >/dev/null 2>&1 \
            && pass "transcribe: segments array" || fail "transcribe: segments not array"
        jq -e '.result.locale | type == "string"' "$TMP/transcribe.json" >/dev/null 2>&1 \
            && pass "transcribe: locale string" || fail "transcribe: locale missing"
    elif echo "$tout" | grep -qiE "authorized|speech recognition|not authorized|Developer ID"; then
        pass "transcribe: skipped (speech not authorized)"
    else
        fail "transcribe: unexpected exit ($tec): $tout"
    fi
else
    pass "transcribe: skipped (say could not create sample audio)"
fi
echo

# ── voice-analytics (optional — requires Speech recognition permission) ─────
echo "── speech: voice-analytics ─────────────────────────────────────────────────"
if $has_audio; then
    set +e
    vout=$("$BINARY" speech --input "$AUDIO" --operation voice-analytics --output "$TMP/va.json" 2>&1)
    vec=$?
    set -e
    if [ "$vec" -eq 0 ] && [ -f "$TMP/va.json" ]; then
        pass "voice-analytics: output produced"
        jq empty "$TMP/va.json" 2>/dev/null && pass "voice-analytics: valid JSON" || fail "voice-analytics: invalid JSON"
        jq -e '.operation == "voice-analytics"' "$TMP/va.json" >/dev/null 2>&1 \
            && pass "voice-analytics: operation field" || fail "voice-analytics: operation mismatch"
        jq -e '.result.transcript | type == "string"' "$TMP/va.json" >/dev/null 2>&1 \
            && pass "voice-analytics: transcript present" || fail "voice-analytics: transcript missing"
    elif echo "$vout" | grep -qiE "authorized|speech recognition|not authorized|Developer ID"; then
        pass "voice-analytics: skipped (speech not authorized)"
    else
        fail "voice-analytics: unexpected exit ($vec): $vout"
    fi
else
    pass "voice-analytics: skipped (say could not create sample audio)"
fi
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
