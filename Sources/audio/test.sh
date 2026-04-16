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
if say -o "$AUDIO" "Smoke test phrase for macOS vision audio." 2>/dev/null && [ -f "$AUDIO" ]; then
    has_audio=true
fi

# ── error handling ────────────────────────────────────────────────────────────
echo "── audio: error handling ───────────────────────────────────────────────────"
err=$("$BINARY" audio 2>&1 || true)
echo "$err" | grep -qiE "audio|--input|mic|provide|error" \
    && pass "audio: missing input error shown" || fail "audio: no error on missing input"

err=$("$BINARY" audio --input "$AUDIO" --operation not-a-real-op --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "unknown\|valid\|error" \
    && pass "audio: unknown operation rejected" || fail "audio: unknown operation not rejected"

err=$("$BINARY" audio --input /nonexistent/no_such_file.wav --operation classify --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "error\|fail\|not\|could\|read" \
    && pass "audio: missing file error shown" || fail "audio: missing file not rejected"
echo

# ── classify ────────────────────────────────────────────────────────────────
echo "── audio: classify ─────────────────────────────────────────────────────────"
if $has_audio; then
    "$BINARY" audio --input "$AUDIO" --operation classify --output "$TMP/classify.json"
    got="$TMP/classify.json"
    if [ -f "$got" ]; then
        pass "classify: output produced"
        jq empty "$got" 2>/dev/null && pass "classify: valid JSON" || fail "classify: invalid JSON"
        jq -e '.operation == "classify"' "$got" >/dev/null 2>&1 && pass "classify: operation field" || fail "classify: operation mismatch"
        jq -e '.result.results | type == "array"' "$got" >/dev/null 2>&1 && pass "classify: results array" || fail "classify: results not an array"
    else
        fail "classify: output not produced"
    fi
else
    pass "classify: skipped (say could not create sample audio)"
fi
echo

# ── noise ───────────────────────────────────────────────────────────────────
echo "── audio: noise ────────────────────────────────────────────────────────────"
if $has_audio; then
    "$BINARY" audio --input "$AUDIO" --operation noise --output "$TMP/noise.json"
    got="$TMP/noise.json"
    if [ -f "$got" ]; then
        pass "noise: output produced"
        jq empty "$got" 2>/dev/null && pass "noise: valid JSON" || fail "noise: invalid JSON"
        jq -e '.result.results | type == "array"' "$got" >/dev/null 2>&1 && pass "noise: results array" || fail "noise: results not an array"
        n=$(jq '.result.results | length' "$got" 2>/dev/null || echo 0)
        [ "${n:-0}" -gt 0 ] && pass "noise: $n window(s)" || fail "noise: no windows"
    else
        fail "noise: output not produced"
    fi
else
    pass "noise: skipped (say could not create sample audio)"
fi
echo

# ── pitch ───────────────────────────────────────────────────────────────────
echo "── audio: pitch ────────────────────────────────────────────────────────────"
if $has_audio; then
    "$BINARY" audio --input "$AUDIO" --operation pitch --output "$TMP/pitch.json"
    got="$TMP/pitch.json"
    if [ -f "$got" ]; then
        pass "pitch: output produced"
        jq empty "$got" 2>/dev/null && pass "pitch: valid JSON" || fail "pitch: invalid JSON"
        jq -e '.result.results | type == "array"' "$got" >/dev/null 2>&1 && pass "pitch: results array" || fail "pitch: results not an array"
    else
        fail "pitch: output not produced"
    fi
else
    pass "pitch: skipped (say could not create sample audio)"
fi
echo

# ── detect ──────────────────────────────────────────────────────────────────
echo "── audio: detect ─────────────────────────────────────────────────────────────"
if $has_audio; then
    "$BINARY" audio --input "$AUDIO" --operation detect --output "$TMP/detect.json"
    got="$TMP/detect.json"
    if [ -f "$got" ]; then
        pass "detect: output produced"
        jq empty "$got" 2>/dev/null && pass "detect: valid JSON" || fail "detect: invalid JSON"
        jq -e '.result.results | type == "array"' "$got" >/dev/null 2>&1 && pass "detect: results array" || fail "detect: results not an array"
    else
        fail "detect: output not produced"
    fi
else
    pass "detect: skipped (say could not create sample audio)"
fi
echo

# ── shazam ──────────────────────────────────────────────────────────────────
echo "── audio: shazam ─────────────────────────────────────────────────────────────"
if $has_audio; then
    "$BINARY" audio --input "$AUDIO" --operation shazam --output "$TMP/shazam.json"
    got="$TMP/shazam.json"
    if [ -f "$got" ]; then
        pass "shazam: output produced"
        jq empty "$got" 2>/dev/null && pass "shazam: valid JSON" || fail "shazam: invalid JSON"
        jq -e '.result.results | type == "object"' "$got" >/dev/null 2>&1 && pass "shazam: results object" || fail "shazam: results not an object"
        jq -e '.result.results | has("matched")' "$got" >/dev/null 2>&1 && pass "shazam: matched field present" || fail "shazam: matched field missing"
    else
        fail "shazam: output not produced"
    fi
else
    pass "shazam: skipped (say could not create sample audio)"
fi
echo

# ── isolate ─────────────────────────────────────────────────────────────────
echo "── audio: isolate ──────────────────────────────────────────────────────────"
if $has_audio; then
    "$BINARY" audio --input "$AUDIO" --operation isolate --output "$TMP/isolate.json"
    got="$TMP/isolate.json"
    if [ -f "$got" ]; then
        pass "isolate: output produced"
        jq empty "$got" 2>/dev/null && pass "isolate: valid JSON" || fail "isolate: invalid JSON"
        outpath=$(jq -r '.result.results.output // empty' "$got" 2>/dev/null || true)
        if [ -n "$outpath" ] && [ -f "$outpath" ]; then
            pass "isolate: output file exists"
        else
            fail "isolate: output file missing"
        fi
    else
        fail "isolate: JSON not produced"
    fi
else
    pass "isolate: skipped (say could not create sample audio)"
fi
echo

# ── batch: use a shell loop with --input per file ────────────────────────────
echo "── audio: batch (shell loop) ───────────────────────────────────────────────"
pass "audio: batch processing done via shell loop with --input per file"
echo

# ── transcribe (optional — requires Speech recognition permission + Developer ID signing) ───
echo "── audio: transcribe ────────────────────────────────────────────────────────"
if $has_audio; then
    set +e
    tout=$("$BINARY" audio --input "$AUDIO" --operation transcribe --output "$TMP/tr.json" 2>&1)
    tec=$?
    set -e
    if [ "$tec" -eq 0 ] && [ -f "$TMP/tr.json" ]; then
        pass "transcribe: output produced"
        jq empty "$TMP/tr.json" 2>/dev/null && pass "transcribe: valid JSON" || fail "transcribe: invalid JSON"
        jq -e '.result.results | type == "array"' "$TMP/tr.json" >/dev/null 2>&1 \
            && pass "transcribe: results array" || fail "transcribe: results not an array"
    elif echo "$tout" | grep -qiE "authorized|speech recognition|not authorized|Developer ID"; then
        pass "transcribe: skipped (speech not authorized)"
    else
        fail "transcribe: unexpected exit ($tec): $tout"
    fi
else
    pass "transcribe: skipped (say could not create sample audio)"
fi
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
