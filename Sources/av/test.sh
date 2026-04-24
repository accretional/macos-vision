#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

# Generate a synthetic audio file for testing
AUDIO="$TMP/smoke.aiff"
has_audio=false
if say -o "$AUDIO" "The quick brown fox jumps over the lazy dog." 2>/dev/null && [ -f "$AUDIO" ]; then
    has_audio=true
fi

# ── error handling ────────────────────────────────────────────────────────────
echo "── av: error handling ──────────────────────────────────────────────────────"

err=$("$BINARY" av --operation not-real --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "unknown\|valid\|error" \
    && pass "av: unknown operation rejected" || fail "av: unknown operation not rejected"

err=$("$BINARY" av --operation noise --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "input\|provide\|error" \
    && pass "av noise: missing input rejected" || fail "av noise: missing input not rejected"
echo

# ── noise ─────────────────────────────────────────────────────────────────────
echo "── av: noise ───────────────────────────────────────────────────────────────"
if $has_audio; then
    "$BINARY" av --input "$AUDIO" --operation noise --output "$TMP/noise.json"
    if [ -f "$TMP/noise.json" ]; then
        pass "noise: output produced"
        jq empty "$TMP/noise.json" 2>/dev/null && pass "noise: valid JSON" || fail "noise: invalid JSON"
        jq -e '.operation == "noise"' "$TMP/noise.json" >/dev/null 2>&1 \
            && pass "noise: operation field" || fail "noise: operation mismatch"
        jq -e '.result.windows | type == "array"' "$TMP/noise.json" >/dev/null 2>&1 \
            && pass "noise: windows array" || fail "noise: windows not array"
        jq -e '.result.windows | length > 0' "$TMP/noise.json" >/dev/null 2>&1 \
            && pass "noise: at least one window" || fail "noise: no windows produced"
        jq -e '.result.windows[0] | has("time") and has("rms") and has("db") and has("level")' "$TMP/noise.json" >/dev/null 2>&1 \
            && pass "noise: window fields present" || fail "noise: window fields missing"
    else
        fail "noise: output not produced"
    fi
else
    pass "noise: skipped (say could not create sample audio)"
fi
echo

# ── pitch ─────────────────────────────────────────────────────────────────────
echo "── av: pitch ───────────────────────────────────────────────────────────────"
if $has_audio; then
    "$BINARY" av --input "$AUDIO" --operation pitch --output "$TMP/pitch.json"
    if [ -f "$TMP/pitch.json" ]; then
        pass "pitch: output produced"
        jq empty "$TMP/pitch.json" 2>/dev/null && pass "pitch: valid JSON" || fail "pitch: invalid JSON"
        jq -e '.operation == "pitch"' "$TMP/pitch.json" >/dev/null 2>&1 \
            && pass "pitch: operation field" || fail "pitch: operation mismatch"
        jq -e '.result.frames | type == "array"' "$TMP/pitch.json" >/dev/null 2>&1 \
            && pass "pitch: frames array" || fail "pitch: frames not array"
        jq -e '.result.sample_rate | type == "number"' "$TMP/pitch.json" >/dev/null 2>&1 \
            && pass "pitch: sample_rate present" || fail "pitch: sample_rate missing"
    else
        fail "pitch: output not produced"
    fi
else
    pass "pitch: skipped (say could not create sample audio)"
fi
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
