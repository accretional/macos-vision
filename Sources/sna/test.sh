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
# Use a phrase long enough to exceed the built-in classifier's ~3 s default window.
if say -o "$AUDIO" \
    "Testing sound classification. The quick brown fox jumps over the lazy dog. Hello world, this is a smoke test." \
    2>/dev/null && [ -f "$AUDIO" ]; then
    has_audio=true
fi

# ── error handling ────────────────────────────────────────────────────────────
echo "── sna: error handling ─────────────────────────────────────────────────────"

err=$("$BINARY" sna 2>&1 || true)
echo "$err" | grep -qiE "input|audio|provide|error" \
    && pass "sna: missing input error shown" || fail "sna: no error on missing input"

err=$("$BINARY" sna --input "$AUDIO" --operation not-real --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "unknown\|valid\|error" \
    && pass "sna: unknown operation rejected" || fail "sna: unknown operation not rejected"

err=$("$BINARY" sna --input /no/such/file.wav --operation classify --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "error\|fail\|no such\|could not" \
    && pass "sna: missing file error shown" || fail "sna: missing file not rejected"

err=$("$BINARY" sna --input "$AUDIO" --operation classify-custom --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "model\|--model\|error" \
    && pass "sna: classify-custom without --model rejected" || fail "sna: classify-custom without --model not rejected"

err=$("$BINARY" sna --input "$AUDIO" --operation classify --classify-overlap 1.5 --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "overlap\|\[0\|error" \
    && pass "sna: invalid overlap rejected" || fail "sna: invalid overlap not rejected"
echo

# ── list-labels (no input required, no auth required) ────────────────────────
echo "── sna: list-labels ────────────────────────────────────────────────────────"
"$BINARY" sna --operation list-labels --output "$TMP/labels.json"
if [ -f "$TMP/labels.json" ]; then
    pass "list-labels: output produced"
    jq empty "$TMP/labels.json" 2>/dev/null && pass "list-labels: valid JSON" || fail "list-labels: invalid JSON"
    jq -e '.operation == "list-labels"' "$TMP/labels.json" >/dev/null 2>&1 \
        && pass "list-labels: operation field" || fail "list-labels: operation mismatch"
    jq -e '.result.count | . > 0' "$TMP/labels.json" >/dev/null 2>&1 \
        && pass "list-labels: non-zero count" || fail "list-labels: count is zero"
    jq -e '.result.labels | type == "array"' "$TMP/labels.json" >/dev/null 2>&1 \
        && pass "list-labels: labels is array" || fail "list-labels: labels not array"
    jq -e '.result.classifier | type == "string"' "$TMP/labels.json" >/dev/null 2>&1 \
        && pass "list-labels: classifier field present" || fail "list-labels: classifier field missing"
    n=$(jq '.result.count' "$TMP/labels.json" 2>/dev/null || echo 0)
    echo "  INFO  $n known sound labels"
else
    fail "list-labels: output not produced"
fi
echo

# ── classify ──────────────────────────────────────────────────────────────────
echo "── sna: classify ───────────────────────────────────────────────────────────"
if $has_audio; then
    "$BINARY" sna --input "$AUDIO" --operation classify --output "$TMP/classify.json"
    if [ -f "$TMP/classify.json" ]; then
        pass "classify: output produced"
        jq empty "$TMP/classify.json" 2>/dev/null && pass "classify: valid JSON" || fail "classify: invalid JSON"
        jq -e '.operation == "classify"' "$TMP/classify.json" >/dev/null 2>&1 \
            && pass "classify: operation field" || fail "classify: operation mismatch"
        jq -e '.result.windows | type == "array"' "$TMP/classify.json" >/dev/null 2>&1 \
            && pass "classify: windows array" || fail "classify: windows not array"
        jq -e '.result.windows | length > 0' "$TMP/classify.json" >/dev/null 2>&1 \
            && pass "classify: at least one window" || fail "classify: no windows produced"
        jq -e '.result.windows[0].classifications | type == "array"' "$TMP/classify.json" >/dev/null 2>&1 \
            && pass "classify: classifications array in window[0]" || fail "classify: no classifications in window[0]"
        jq -e '.result.windows[0].classifications[0] | has("identifier") and has("confidence")' "$TMP/classify.json" >/dev/null 2>&1 \
            && pass "classify: identifier+confidence fields present" || fail "classify: identifier/confidence fields missing"
        jq -e '.result.classifier == "built-in:v1"' "$TMP/classify.json" >/dev/null 2>&1 \
            && pass "classify: classifier=built-in:v1" || fail "classify: classifier field wrong"
    else
        fail "classify: output not produced"
    fi
else
    pass "classify: skipped (say could not create sample audio)"
fi
echo

# ── classify with --topk ──────────────────────────────────────────────────────
echo "── sna: classify --topk ────────────────────────────────────────────────────"
if $has_audio; then
    "$BINARY" sna --input "$AUDIO" --operation classify --topk 3 --output "$TMP/classify_k3.json"
    if [ -f "$TMP/classify_k3.json" ]; then
        pass "classify --topk 3: output produced"
        jq empty "$TMP/classify_k3.json" 2>/dev/null && pass "classify --topk 3: valid JSON" || fail "classify --topk 3: invalid JSON"
        n=$(jq '.result.windows[0].classifications | length' "$TMP/classify_k3.json" 2>/dev/null || echo -1)
        [ "${n:-0}" -le 3 ] && pass "classify --topk 3: at most 3 results per window" || fail "classify --topk 3: more than 3 results"
    else
        fail "classify --topk 3: output not produced"
    fi
else
    pass "classify --topk 3: skipped (say could not create sample audio)"
fi
echo

# ── classify with --debug ─────────────────────────────────────────────────────
echo "── sna: classify --debug ───────────────────────────────────────────────────"
if $has_audio; then
    "$BINARY" sna --input "$AUDIO" --operation classify --debug --output "$TMP/classify_dbg.json"
    if [ -f "$TMP/classify_dbg.json" ]; then
        pass "classify --debug: output produced"
        jq empty "$TMP/classify_dbg.json" 2>/dev/null && pass "classify --debug: valid JSON" || fail "classify --debug: invalid JSON"
        jq -e '.result.processing_ms | type == "number"' "$TMP/classify_dbg.json" >/dev/null 2>&1 \
            && pass "classify --debug: processing_ms present" || fail "classify --debug: processing_ms missing"
    else
        fail "classify --debug: output not produced"
    fi
else
    pass "classify --debug: skipped (say could not create sample audio)"
fi
echo

# ── detect ────────────────────────────────────────────────────────────────────
echo "── sna: detect ─────────────────────────────────────────────────────────────"
if $has_audio; then
    "$BINARY" sna --input "$AUDIO" --operation detect --output "$TMP/detect.json"
    if [ -f "$TMP/detect.json" ]; then
        pass "detect: output produced"
        jq empty "$TMP/detect.json" 2>/dev/null && pass "detect: valid JSON" || fail "detect: invalid JSON"
        jq -e '.operation == "detect"' "$TMP/detect.json" >/dev/null 2>&1 \
            && pass "detect: operation field" || fail "detect: operation mismatch"
        jq -e '.result.windows | type == "array"' "$TMP/detect.json" >/dev/null 2>&1 \
            && pass "detect: windows array" || fail "detect: windows not array"
        jq -e '.result.targets | type == "array"' "$TMP/detect.json" >/dev/null 2>&1 \
            && pass "detect: targets array present" || fail "detect: targets field missing"
        jq -e '.result.classifier == "built-in:v1"' "$TMP/detect.json" >/dev/null 2>&1 \
            && pass "detect: classifier field" || fail "detect: classifier field wrong"
    else
        fail "detect: output not produced"
    fi
else
    pass "detect: skipped (say could not create sample audio)"
fi
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
