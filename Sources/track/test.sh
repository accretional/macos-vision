#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
FRAMES="$ROOT/sample_data/input/videos/selective_attention_test_frames"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

has_frames=false
if [ -d "$FRAMES" ] && { ls "$FRAMES"/*.jpg &>/dev/null 2>&1 || ls "$FRAMES"/*.png &>/dev/null 2>&1; }; then
    has_frames=true
fi

# ── error handling ────────────────────────────────────────────────────────────
echo "── track: error handling ────────────────────────────────────────────────────"
err=$("$BINARY" track 2>&1 || true)
echo "$err" | grep -qiE "video|input|must be provided|provide|error" && pass "track: missing input error shown" || fail "track: no error on missing input"
err=$("$BINARY" track --input /nonexistent/video.mp4 2>&1 || true)
echo "$err" | grep -qi "not found\|error\|failed" && pass "track: missing input error shown" || fail "track: missing input not rejected"
if $has_frames; then
    err=$("$BINARY" track --input "$FRAMES" --operation bad-op 2>&1 || true)
    echo "$err" | grep -qi "unknown\|supported\|error" && pass "track: unknown operation rejected" || fail "track: unknown operation not rejected"
fi
echo

# ── homographic ───────────────────────────────────────────────────────────────
echo "── track: homographic ───────────────────────────────────────────────────────"
if $has_frames; then
    "$BINARY" track --input "$FRAMES" --operation homographic --output "$TMP" --no-stream
    got="$TMP/track_homographic.json"
    if [ -f "$got" ]; then
        pass "homographic: output produced"
        jq empty "$got" 2>/dev/null && pass "homographic: valid JSON" || fail "homographic: invalid JSON"
        jq -e '.result.frames' "$got" >/dev/null 2>&1 && pass "homographic: frames field present" || fail "homographic: frames field missing"
    else
        fail "homographic: output not produced"
    fi
else
    pass "homographic: skipped (frames not found)"
fi
echo

# ── translational ─────────────────────────────────────────────────────────────
echo "── track: translational ─────────────────────────────────────────────────────"
if $has_frames; then
    "$BINARY" track --input "$FRAMES" --operation translational --output "$TMP" --no-stream
    got="$TMP/track_translational.json"
    if [ -f "$got" ]; then
        pass "translational: output produced"
        jq empty "$got" 2>/dev/null && pass "translational: valid JSON" || fail "translational: invalid JSON"
        jq -e '.result.frames' "$got" >/dev/null 2>&1 && pass "translational: frames field present" || fail "translational: frames field missing"
    else
        fail "translational: output not produced"
    fi
else
    pass "translational: skipped (frames not found)"
fi
echo

# ── trajectories ──────────────────────────────────────────────────────────────
echo "── track: trajectories ──────────────────────────────────────────────────────"
if $has_frames; then
    "$BINARY" track --input "$FRAMES" --operation trajectories --output "$TMP" --no-stream
    got="$TMP/track_trajectories.json"
    if [ -f "$got" ]; then
        pass "trajectories: output produced"
        jq empty "$got" 2>/dev/null && pass "trajectories: valid JSON" || fail "trajectories: invalid JSON"
        jq -e '.result.trajectories' "$got" >/dev/null 2>&1 && pass "trajectories: trajectories field present" || fail "trajectories: trajectories field missing"
    else
        fail "trajectories: output not produced"
    fi
else
    pass "trajectories: skipped (frames not found)"
fi
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
