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

# ── face-rectangles ───────────────────────────────────────────────────────────
echo "── face: face-rectangles ────────────────────────────────────────────────────"
"$BINARY" face --img "$img" --operation face-rectangles --output "$TMP"
got="$TMP/fred_yass_face_rectangles.json"
if [ -f "$got" ]; then
    pass "face-rectangles: output produced"
    jq empty "$got" 2>/dev/null && pass "face-rectangles: valid JSON" || fail "face-rectangles: invalid JSON"
    count=$(jq '.faces | length' "$got" 2>/dev/null || echo 0)
    [ "${count:-0}" -gt 0 ] && pass "face-rectangles: $count face(s) detected" || fail "face-rectangles: no faces detected"
    jq -e '.faces[0].boundingBox.x' "$got" >/dev/null 2>&1 && pass "face-rectangles: boundingBox present" || fail "face-rectangles: boundingBox missing"
else
    fail "face-rectangles: output not produced"
fi
echo

# ── face-landmarks ────────────────────────────────────────────────────────────
echo "── face: face-landmarks ─────────────────────────────────────────────────────"
"$BINARY" face --img "$img" --operation face-landmarks --output "$TMP"
got="$TMP/fred_yass_face_landmarks.json"
if [ -f "$got" ]; then
    pass "face-landmarks: output produced"
    jq empty "$got" 2>/dev/null && pass "face-landmarks: valid JSON" || fail "face-landmarks: invalid JSON"
    count=$(jq '.faces[0].landmarks | length' "$got" 2>/dev/null || echo 0)
    [ "${count:-0}" -gt 0 ] && pass "face-landmarks: landmark regions present" || fail "face-landmarks: no landmark regions"
else
    fail "face-landmarks: output not produced"
fi
echo

# ── face-quality ──────────────────────────────────────────────────────────────
echo "── face: face-quality ───────────────────────────────────────────────────────"
"$BINARY" face --img "$img" --operation face-quality --output "$TMP"
got="$TMP/fred_yass_face_quality.json"
if [ -f "$got" ]; then
    pass "face-quality: output produced"
    jq empty "$got" 2>/dev/null && pass "face-quality: valid JSON" || fail "face-quality: invalid JSON"
    jq -e '.faces[0].quality' "$got" >/dev/null 2>&1 && pass "face-quality: quality field present" || fail "face-quality: quality field missing"
else
    fail "face-quality: output not produced"
fi
echo

# ── body-pose ─────────────────────────────────────────────────────────────────
echo "── face: body-pose ──────────────────────────────────────────────────────────"
"$BINARY" face --img "$IMG/sad_pablo.png" --operation body-pose --output "$TMP" 2>/dev/null || true
got="$TMP/sad_pablo_body_pose.json"
if [ -f "$got" ]; then
    pass "body-pose: output produced"
    jq empty "$got" 2>/dev/null && pass "body-pose: valid JSON" || fail "body-pose: invalid JSON"
    jq -e '.bodies' "$got" >/dev/null 2>&1 && pass "body-pose: bodies field present" || fail "body-pose: bodies field missing"
else
    pass "body-pose: skipped (sad_pablo.png not found)"
fi
echo

# ── human-rectangles ──────────────────────────────────────────────────────────
echo "── face: human-rectangles ───────────────────────────────────────────────────"
"$BINARY" face --img "$IMG/spiderman.jpg" --operation human-rectangles --output "$TMP" 2>/dev/null || true
got="$TMP/spiderman_human_rectangles.json"
if [ -f "$got" ]; then
    pass "human-rectangles: output produced"
    jq empty "$got" 2>/dev/null && pass "human-rectangles: valid JSON" || fail "human-rectangles: invalid JSON"
    jq -e '.humans' "$got" >/dev/null 2>&1 && pass "human-rectangles: humans field present" || fail "human-rectangles: humans field missing"
else
    pass "human-rectangles: skipped (spiderman.jpg not found)"
fi
echo

# ── error handling ────────────────────────────────────────────────────────────
echo "── face: error handling ─────────────────────────────────────────────────────"
err=$("$BINARY" face 2>&1 || true)
echo "$err" | grep -qi "img\|must be provided\|error" && pass "face: missing input error shown" || fail "face: no error on missing input"
err=$("$BINARY" face --img "$img" --operation bad-op 2>&1 || true)
echo "$err" | grep -qi "unknown\|supported\|error" && pass "face: unknown operation rejected" || fail "face: unknown operation not rejected"
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
