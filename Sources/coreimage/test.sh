#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

PASS=0; FAIL=0
pass() { echo "  PASS  $1"; PASS=$((PASS+1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL+1)); }

IMG="$ROOT/sample_data/input/images/gorilla.jpg"
HAS_IMG=false
[ -f "$IMG" ] && HAS_IMG=true

# ── error handling ────────────────────────────────────────────────────────────
echo "── coreimage: error handling ────────────────────────────────────────────────"

err=$("$BINARY" coreimage 2>&1 || true)
echo "$err" | grep -qi "filter\|--filter-name\|error" \
    && pass "apply-filter: missing --filter-name error shown" || fail "apply-filter: no error on missing --filter-name"

err=$("$BINARY" coreimage --input "$IMG" --operation apply-filter --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "filter\|--filter-name\|error" \
    && pass "apply-filter: missing --filter-name error shown (with --input)" \
    || fail "apply-filter: no error on missing --filter-name with input"

err=$("$BINARY" coreimage --operation not-real --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "unknown\|valid\|error" \
    && pass "unknown operation rejected" || fail "unknown operation not rejected"

err=$("$BINARY" coreimage --input "$IMG" --operation apply-filter --filter-name NotARealFilter \
      --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "unknown\|filter\|error" \
    && pass "apply-filter: unknown filter-name rejected" || fail "apply-filter: unknown filter-name not rejected"

err=$("$BINARY" coreimage --input "$IMG" --operation apply-filter --filter-name CISepiaTone \
      --filter-params 'not valid json' --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "json\|param\|error" \
    && pass "apply-filter: bad --filter-params rejected" || fail "apply-filter: bad --filter-params not rejected"
echo

# ── list-filters ──────────────────────────────────────────────────────────────
echo "── coreimage: list-filters ──────────────────────────────────────────────────"
"$BINARY" coreimage --operation list-filters --output "$TMP/filters.json"
if [ -f "$TMP/filters.json" ]; then
    pass "list-filters: output produced"
    jq empty "$TMP/filters.json" 2>/dev/null && pass "list-filters: valid JSON" || fail "list-filters: invalid JSON"
    jq -e '.operation == "list-filters"' "$TMP/filters.json" >/dev/null 2>&1 \
        && pass "list-filters: operation field" || fail "list-filters: operation mismatch"
    jq -e '.result.filters | type == "array"' "$TMP/filters.json" >/dev/null 2>&1 \
        && pass "list-filters: filters is array" || fail "list-filters: filters not array"
    jq -e '.result.count | . > 0' "$TMP/filters.json" >/dev/null 2>&1 \
        && pass "list-filters: non-zero count" || fail "list-filters: count is zero"
    jq -e '.result.by_category | type == "object"' "$TMP/filters.json" >/dev/null 2>&1 \
        && pass "list-filters: by_category object present" || fail "list-filters: by_category missing"
    jq -e '[.result.filters[] | select(. == "CISepiaTone")] | length > 0' \
        "$TMP/filters.json" >/dev/null 2>&1 \
        && pass "list-filters: CISepiaTone in list" || fail "list-filters: CISepiaTone not found"
    n=$(jq '.result.count' "$TMP/filters.json" 2>/dev/null || echo 0)
    echo "  INFO  $n filters total"
else
    fail "list-filters: output not produced"
fi
echo

# ── list-filters --category-only ─────────────────────────────────────────────
echo "── coreimage: list-filters --category-only ──────────────────────────────────"
"$BINARY" coreimage --operation list-filters --category-only --output "$TMP/categories.json"
if [ -f "$TMP/categories.json" ]; then
    pass "list-filters --category-only: output produced"
    jq empty "$TMP/categories.json" 2>/dev/null \
        && pass "list-filters --category-only: valid JSON" || fail "list-filters --category-only: invalid JSON"
    jq -e '.operation == "list-filters"' "$TMP/categories.json" >/dev/null 2>&1 \
        && pass "list-filters --category-only: operation field" || fail "list-filters --category-only: operation mismatch"
    jq -e '.result.categories | type == "array"' "$TMP/categories.json" >/dev/null 2>&1 \
        && pass "list-filters --category-only: categories is array" \
        || fail "list-filters --category-only: categories not array"
    jq -e '.result.count | . > 0' "$TMP/categories.json" >/dev/null 2>&1 \
        && pass "list-filters --category-only: non-zero count" || fail "list-filters --category-only: count is zero"
    jq -e '.result.categories[0] | has("name") and has("display_name") and has("filter_count")' \
        "$TMP/categories.json" >/dev/null 2>&1 \
        && pass "list-filters --category-only: entry has name/display_name/filter_count" \
        || fail "list-filters --category-only: entry missing required fields"
    jq -e '.result | has("filters") | not' "$TMP/categories.json" >/dev/null 2>&1 \
        && pass "list-filters --category-only: no filters array (categories-only output)" \
        || fail "list-filters --category-only: unexpected filters array present"
    n=$(jq '.result.count' "$TMP/categories.json" 2>/dev/null || echo 0)
    echo "  INFO  $n categories"
else
    fail "list-filters --category-only: output not produced"
fi
echo

# ── apply-filter ──────────────────────────────────────────────────────────────
echo "── coreimage: apply-filter ──────────────────────────────────────────────────"
if $HAS_IMG; then
    # Basic apply-filter — CISepiaTone
    "$BINARY" coreimage --input "$IMG" --operation apply-filter --filter-name CISepiaTone \
              --artifacts-dir "$TMP" --json-output "$TMP/sepia.json"
    if [ -f "$TMP/sepia.json" ]; then
        pass "apply-filter CISepiaTone: JSON produced"
        jq empty "$TMP/sepia.json" 2>/dev/null \
            && pass "apply-filter CISepiaTone: valid JSON" || fail "apply-filter CISepiaTone: invalid JSON"
        jq -e '.operation == "apply-filter"' "$TMP/sepia.json" >/dev/null 2>&1 \
            && pass "apply-filter CISepiaTone: operation field" || fail "apply-filter CISepiaTone: operation mismatch"
        jq -e '.result.filter == "CISepiaTone"' "$TMP/sepia.json" >/dev/null 2>&1 \
            && pass "apply-filter CISepiaTone: filter field" || fail "apply-filter CISepiaTone: filter field wrong"
        jq -e '.result.artifacts | type == "array"' "$TMP/sepia.json" >/dev/null 2>&1 \
            && pass "apply-filter CISepiaTone: artifacts array" || fail "apply-filter CISepiaTone: artifacts missing"
        [ -f "$TMP/gorilla_CISepiaTone.png" ] \
            && pass "apply-filter CISepiaTone: PNG written to artifacts-dir" \
            || fail "apply-filter CISepiaTone: PNG not found in artifacts-dir"
    else
        fail "apply-filter CISepiaTone: JSON not produced"
    fi

    # apply-filter with --filter-params
    "$BINARY" coreimage --input "$IMG" --operation apply-filter --filter-name CIGaussianBlur \
              --filter-params '{"inputRadius": 5}' \
              --artifacts-dir "$TMP" --json-output "$TMP/blur.json"
    if [ -f "$TMP/blur.json" ]; then
        pass "apply-filter CIGaussianBlur with params: JSON produced"
        jq empty "$TMP/blur.json" 2>/dev/null \
            && pass "apply-filter CIGaussianBlur: valid JSON" || fail "apply-filter CIGaussianBlur: invalid JSON"
        jq -e '.result.params.inputRadius == 5' "$TMP/blur.json" >/dev/null 2>&1 \
            && pass "apply-filter CIGaussianBlur: params echoed in result" \
            || fail "apply-filter CIGaussianBlur: params not echoed"
        [ -f "$TMP/gorilla_CIGaussianBlur.png" ] \
            && pass "apply-filter CIGaussianBlur: PNG written" || fail "apply-filter CIGaussianBlur: PNG not found"
    else
        fail "apply-filter CIGaussianBlur with params: JSON not produced"
    fi

    # apply-filter with --debug
    "$BINARY" coreimage --input "$IMG" --operation apply-filter --filter-name CIColorInvert \
              --debug --artifacts-dir "$TMP" --json-output "$TMP/invert.json"
    if [ -f "$TMP/invert.json" ]; then
        pass "apply-filter --debug: JSON produced"
        jq -e '.result.processing_ms | type == "number"' "$TMP/invert.json" >/dev/null 2>&1 \
            && pass "apply-filter --debug: processing_ms present" || fail "apply-filter --debug: processing_ms missing"
    else
        fail "apply-filter --debug: JSON not produced"
    fi

    # apply-filter with exact --output image path
    "$BINARY" coreimage --input "$IMG" --operation apply-filter --filter-name CISepiaTone \
              --output "$TMP/exact_output.png" --json-output "$TMP/exact.json"
    [ -f "$TMP/exact_output.png" ] \
        && pass "apply-filter: exact --output image path respected" \
        || fail "apply-filter: exact --output image path not written"
else
    pass "apply-filter: skipped (sample image not found at $IMG)"
fi
echo

# ── --format flag ─────────────────────────────────────────────────────────────
echo "── coreimage: --format flag ─────────────────────────────────────────────────"

err=$("$BINARY" coreimage --operation apply-filter --filter-name CISepiaTone \
      --format notaformat --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "format\|unknown\|error" \
    && pass "--format: invalid format rejected" || fail "--format: invalid format not rejected"

if $HAS_IMG; then
    "$BINARY" coreimage --input "$IMG" --operation apply-filter --filter-name CISepiaTone \
              --format jpg --artifacts-dir "$TMP" --json-output "$TMP/sepia_jpg.json"
    if [ -f "$TMP/sepia_jpg.json" ]; then
        pass "--format jpg: JSON produced"
        jq -e '.result.format == "jpg"' "$TMP/sepia_jpg.json" >/dev/null 2>&1 \
            && pass "--format jpg: format field in result" || fail "--format jpg: format field missing/wrong"
        [ -f "$TMP/gorilla_CISepiaTone.jpg" ] \
            && pass "--format jpg: .jpg file written" || fail "--format jpg: .jpg file not found"
    else
        fail "--format jpg: JSON not produced"
    fi

    "$BINARY" coreimage --input "$IMG" --operation apply-filter --filter-name CISepiaTone \
              --format tiff --artifacts-dir "$TMP" --json-output "$TMP/sepia_tiff.json"
    if [ -f "$TMP/sepia_tiff.json" ]; then
        pass "--format tiff: JSON produced"
        [ -f "$TMP/gorilla_CISepiaTone.tiff" ] \
            && pass "--format tiff: .tiff file written" || fail "--format tiff: .tiff file not found"
    else
        fail "--format tiff: JSON not produced"
    fi
else
    pass "--format: skipped (sample image not found)"
fi
echo

# ── auto-adjust ───────────────────────────────────────────────────────────────
echo "── coreimage: auto-adjust ───────────────────────────────────────────────────"

err=$("$BINARY" coreimage --operation auto-adjust --output "$TMP/x.json" 2>&1 || true)
echo "$err" | grep -qi "input\|require\|error" \
    && pass "auto-adjust: missing --input error shown" || fail "auto-adjust: no error on missing --input"

if $HAS_IMG; then
    "$BINARY" coreimage --input "$IMG" --operation auto-adjust \
              --artifacts-dir "$TMP" --json-output "$TMP/autoadj.json"
    if [ -f "$TMP/autoadj.json" ]; then
        pass "auto-adjust: JSON produced"
        jq empty "$TMP/autoadj.json" 2>/dev/null \
            && pass "auto-adjust: valid JSON" || fail "auto-adjust: invalid JSON"
        jq -e '.operation == "auto-adjust"' "$TMP/autoadj.json" >/dev/null 2>&1 \
            && pass "auto-adjust: operation field" || fail "auto-adjust: operation mismatch"
        jq -e '.result.filters | type == "array"' "$TMP/autoadj.json" >/dev/null 2>&1 \
            && pass "auto-adjust: filters array present" || fail "auto-adjust: filters array missing"
        jq -e '.result.artifacts | type == "array"' "$TMP/autoadj.json" >/dev/null 2>&1 \
            && pass "auto-adjust: artifacts array present" || fail "auto-adjust: artifacts missing"
        [ -f "$TMP/gorilla_auto_adjust.png" ] \
            && pass "auto-adjust: output PNG written" || fail "auto-adjust: output PNG not found"
    else
        fail "auto-adjust: JSON not produced"
    fi

    # auto-adjust with --format jpg
    "$BINARY" coreimage --input "$IMG" --operation auto-adjust \
              --format jpg --artifacts-dir "$TMP" --json-output "$TMP/autoadj_jpg.json"
    if [ -f "$TMP/autoadj_jpg.json" ]; then
        pass "auto-adjust --format jpg: JSON produced"
        jq -e '.result.format == "jpg"' "$TMP/autoadj_jpg.json" >/dev/null 2>&1 \
            && pass "auto-adjust --format jpg: format field" || fail "auto-adjust --format jpg: format field wrong"
        [ -f "$TMP/gorilla_auto_adjust.jpg" ] \
            && pass "auto-adjust --format jpg: .jpg written" || fail "auto-adjust --format jpg: .jpg not found"
    else
        fail "auto-adjust --format jpg: JSON not produced"
    fi

    # auto-adjust with --debug
    "$BINARY" coreimage --input "$IMG" --operation auto-adjust \
              --debug --artifacts-dir "$TMP" --json-output "$TMP/autoadj_debug.json"
    if [ -f "$TMP/autoadj_debug.json" ]; then
        pass "auto-adjust --debug: JSON produced"
        jq -e '.result.processing_ms | type == "number"' "$TMP/autoadj_debug.json" >/dev/null 2>&1 \
            && pass "auto-adjust --debug: processing_ms present" || fail "auto-adjust --debug: processing_ms missing"
    else
        fail "auto-adjust --debug: JSON not produced"
    fi
else
    pass "auto-adjust: skipped (sample image not found)"
fi
echo

echo "Results: $PASS passed, $FAIL failed"
[ $FAIL -eq 0 ] || exit 1
