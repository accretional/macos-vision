#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

# ── error handling ────────────────────────────────────────────────────────────
echo "── imagecapture: error handling ─────────────────────────────────────────────"

err=$("$BINARY" imagecapture --operation bad-op 2>&1 || true)
echo "$err" | grep -qi "unknown\|valid\|error" \
    && pass "unknown operation rejected" || fail "unknown operation not rejected"

# camera ops without a device should fail gracefully, not crash
for op in list-files "camera/files" camera/thumbnail camera/metadata camera/import camera/delete camera/capture camera/sync-clock; do
    err=$("$BINARY" imagecapture --operation "$op" 2>&1 || true)
    echo "$err" | grep -qiE "no camera|device|connect|error|require" \
        && pass "$op: graceful error when no camera" \
        || fail "$op: unexpected output when no camera"
done

# scanner ops without a device should fail gracefully
for op in scanner/preview scanner/scan; do
    err=$("$BINARY" imagecapture --operation "$op" 2>&1 || true)
    echo "$err" | grep -qiE "no scanner|device|connect|error" \
        && pass "$op: graceful error when no scanner" \
        || fail "$op: unexpected output when no scanner"
done
echo

# ── camera/import: missing --output should error ──────────────────────────────
echo "── imagecapture: camera/import requires --output ────────────────────────────"
err=$("$BINARY" imagecapture --operation camera/import 2>&1 || true)
echo "$err" | grep -qiE "output|require|error" \
    && pass "camera/import: error when --output missing" \
    || fail "camera/import: no error when --output missing"
echo

# ── list-devices ──────────────────────────────────────────────────────────────
echo "── imagecapture: list-devices ───────────────────────────────────────────────"
"$BINARY" imagecapture --operation list-devices --output "$TMP/devices.json"
if [ -f "$TMP/devices.json" ]; then
    pass "list-devices: output produced"
    jq empty "$TMP/devices.json" 2>/dev/null \
        && pass "list-devices: valid JSON" || fail "list-devices: invalid JSON"
    jq -e '.subcommand == "imagecapture"' "$TMP/devices.json" >/dev/null 2>&1 \
        && pass "list-devices: subcommand field correct" || fail "list-devices: subcommand mismatch"
    jq -e '.operation == "list-devices"' "$TMP/devices.json" >/dev/null 2>&1 \
        && pass "list-devices: operation field correct" || fail "list-devices: operation mismatch"
    jq -e '.result | has("cameras") and has("scanners") and has("camera_count") and has("scanner_count")' \
        "$TMP/devices.json" >/dev/null 2>&1 \
        && pass "list-devices: result has required keys" || fail "list-devices: result missing required keys"
    jq -e '.result.cameras | type == "array"' "$TMP/devices.json" >/dev/null 2>&1 \
        && pass "list-devices: cameras is array" || fail "list-devices: cameras not array"
    jq -e '.result.scanners | type == "array"' "$TMP/devices.json" >/dev/null 2>&1 \
        && pass "list-devices: scanners is array" || fail "list-devices: scanners not array"
    cam_count=$(jq '.result.camera_count' "$TMP/devices.json" 2>/dev/null || echo 0)
    scn_count=$(jq '.result.scanner_count' "$TMP/devices.json" 2>/dev/null || echo 0)
    echo "  INFO  $cam_count camera(s), $scn_count scanner(s) found"
else
    fail "list-devices: output not produced"
fi
echo

# ── list-devices --debug ──────────────────────────────────────────────────────
echo "── imagecapture: list-devices --debug ───────────────────────────────────────"
"$BINARY" imagecapture --operation list-devices --debug --output "$TMP/devices_debug.json"
if [ -f "$TMP/devices_debug.json" ]; then
    pass "list-devices --debug: output produced"
    jq -e '.result.processing_ms | type == "number"' "$TMP/devices_debug.json" >/dev/null 2>&1 \
        && pass "list-devices --debug: processing_ms present" \
        || fail "list-devices --debug: processing_ms missing"
else
    fail "list-devices --debug: output not produced"
fi
echo

# ── default operation (list-devices) ─────────────────────────────────────────
echo "── imagecapture: default operation ──────────────────────────────────────────"
"$BINARY" imagecapture --output "$TMP/default.json"
if [ -f "$TMP/default.json" ]; then
    pass "default operation: output produced"
    jq -e '.operation == "list-devices"' "$TMP/default.json" >/dev/null 2>&1 \
        && pass "default operation: defaults to list-devices" \
        || fail "default operation: unexpected operation value"
else
    fail "default operation: output not produced"
fi
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
