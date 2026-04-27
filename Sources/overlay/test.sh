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
echo "── overlay: setup ───────────────────────────────────────────────────────────"
"$BINARY" face --input "$img" --operation face-landmarks --output "$TMP" --no-stream 2>/dev/null
lm_json="$TMP/fred_yass_face_landmarks.json"
if [ ! -f "$lm_json" ]; then
    fail "overlay: prerequisite face-landmarks JSON not produced"
    echo "0 passed, 1 failed"; exit 1
fi
pass "overlay: face-landmarks JSON available"
echo

# ── overlay subcommand ────────────────────────────────────────────────────────
echo "── overlay: face-landmarks overlay ─────────────────────────────────────────"
"$BINARY" overlay --json "$lm_json" --output "$TMP" --no-stream
lm_svg="$TMP/fred_yass_face_landmarks.svg"
if [ -f "$lm_svg" ]; then
    pass "overlay: SVG produced"
    grep -q "<svg"            "$lm_svg" && pass "overlay: <svg element present"           || fail "overlay: <svg element missing"
    grep -q "<image"          "$lm_svg" && pass "overlay: <image element present"         || fail "overlay: <image element missing"
    grep -q "base64"          "$lm_svg" && pass "overlay: base64 data present"            || fail "overlay: base64 data missing"
    grep -qE "<rect|<circle|<polyline|<polygon|<line" "$lm_svg" \
                              && pass "overlay: shape elements present"                   || fail "overlay: no shape elements"
    grep -q "data-label"      "$lm_svg" && pass "overlay: data-label attributes present"  || fail "overlay: data-label missing"
    grep -q "<title>"         "$lm_svg" && pass "overlay: <title> tooltips present"       || fail "overlay: <title> missing"
    grep -q "layer-landmarks" "$lm_svg" && pass "overlay: layer-landmarks group present"  || fail "overlay: layer-landmarks missing"
    grep -q "ov-panel"        "$lm_svg" && pass "overlay: info panel present"             || fail "overlay: info panel missing"
    grep -q "ovToggleLayer"   "$lm_svg" && pass "overlay: layer toggle API present"       || fail "overlay: ovToggleLayer missing"
    grep -q "<style>"         "$lm_svg" && pass "overlay: embedded CSS present"           || fail "overlay: embedded CSS missing"
    grep -q "<script"         "$lm_svg" && pass "overlay: embedded JS present"            || fail "overlay: embedded JS missing"
else
    fail "overlay: SVG not produced"
fi
echo

# ── svg alias (backwards compat) ─────────────────────────────────────────────
echo "── overlay: svg alias ───────────────────────────────────────────────────────"
"$BINARY" svg --json "$lm_json" --output "$TMP" --no-stream
[ -f "$lm_svg" ] && pass "overlay: svg alias accepted" || fail "overlay: svg alias failed"
echo

# ── --input override ─────────────────────────────────────────────────────────
echo "── overlay: --input override ────────────────────────────────────────────────"
"$BINARY" overlay --json "$lm_json" --input "$img" --output "$TMP" --no-stream
[ -f "$lm_svg" ] && pass "overlay: --input override accepted" || fail "overlay: --input override failed"
echo

# ── body pose: check bones are drawn ─────────────────────────────────────────
echo "── overlay: body pose bones ─────────────────────────────────────────────────"
body_img="$IMG/sad_pablo.png"
if [ -f "$body_img" ]; then
    "$BINARY" face --input "$body_img" --operation body-pose --output "$TMP" --no-stream 2>/dev/null
    body_json="$TMP/sad_pablo_body_pose.json"
    if [ -f "$body_json" ]; then
        "$BINARY" overlay --json "$body_json" --output "$TMP" --no-stream
        body_svg="$TMP/sad_pablo_body_pose.svg"
        if [ -f "$body_svg" ]; then
            grep -q "layer-bones"  "$body_svg" && pass "overlay: layer-bones group present"  || fail "overlay: layer-bones missing"
            grep -q "layer-joints" "$body_svg" && pass "overlay: layer-joints group present" || fail "overlay: layer-joints missing"
            grep -q "ov-bone"      "$body_svg" && pass "overlay: ov-bone elements present"   || fail "overlay: ov-bone missing"
            grep -q "data-label"   "$body_svg" && pass "overlay: body pose data-label on joints" || fail "overlay: body pose data-label missing"
        else
            fail "overlay: body pose SVG not produced"
        fi
    else
        fail "overlay: body pose JSON not produced"
    fi
else
    echo "  SKIP  overlay: sad_pablo.png not found"
fi
echo

# ── error handling ────────────────────────────────────────────────────────────
echo "── overlay: error handling ──────────────────────────────────────────────────"
err=$("$BINARY" overlay 2>&1 || true)
echo "$err" | grep -qi "json\|required\|error" && pass "overlay: missing --json error shown" || fail "overlay: no error on missing --json"
err=$("$BINARY" overlay --json /nonexistent/path.json 2>&1 || true)
echo "$err" | grep -qi "error\|not found\|no such" && pass "overlay: nonexistent JSON error shown" || fail "overlay: no error for nonexistent JSON"
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
