run_classify_tests() {
    local img="$IMAGES/macos-vision-ocr.jpg"

    if [ ! -f "$img" ]; then
        fail "classify tests: $img not found"
        echo; return
    fi

    local tmp="$TMPDIR_ROOT/classify"
    mkdir -p "$tmp"

    # ── classify ──────────────────────────────────────────────────────────────

    echo "── classify: classify ───────────────────────────────────────────────────"
    $BINARY classify --img "$img" --operation classify --output "$tmp"
    local got="$tmp/macos-vision-ocr_classify.json"

    if [ -f "$got" ]; then
        pass "classify: output produced"
        if jq empty "$got" 2>/dev/null; then
            pass "classify: valid JSON"
        else
            fail "classify: invalid JSON"
        fi
        local count
        count=$(jq '.classifications | length' "$got" 2>/dev/null || echo 0)
        if [ "${count:-0}" -gt 0 ]; then
            pass "classify: $count classification(s) returned"
        else
            fail "classify: no classifications returned"
        fi
        if jq -e '.classifications[0].identifier' "$got" > /dev/null 2>&1; then
            pass "classify: identifier field present"
        else
            fail "classify: identifier field missing"
        fi
    else
        fail "classify: output not produced"
    fi
    echo

    # ── rectangles ────────────────────────────────────────────────────────────

    echo "── classify: rectangles ─────────────────────────────────────────────────"
    $BINARY classify --img "$img" --operation rectangles --output "$tmp"
    local rect_got="$tmp/macos-vision-ocr_rectangles.json"

    if [ -f "$rect_got" ]; then
        pass "rectangles: output produced"
        if jq empty "$rect_got" 2>/dev/null; then
            pass "rectangles: valid JSON"
        else
            fail "rectangles: invalid JSON"
        fi
        if jq -e '.rectangles' "$rect_got" > /dev/null 2>&1; then
            pass "rectangles: rectangles field present"
        else
            fail "rectangles: rectangles field missing"
        fi
    else
        fail "rectangles: output not produced"
    fi
    echo

    # ── horizon ───────────────────────────────────────────────────────────────

    echo "── classify: horizon ────────────────────────────────────────────────────"
    $BINARY classify --img "$img" --operation horizon --output "$tmp"
    local hz_got="$tmp/macos-vision-ocr_horizon.json"

    if [ -f "$hz_got" ]; then
        pass "horizon: output produced"
        if jq empty "$hz_got" 2>/dev/null; then
            pass "horizon: valid JSON"
        else
            fail "horizon: invalid JSON"
        fi
        if jq -e '.horizon' "$hz_got" > /dev/null 2>&1; then
            pass "horizon: horizon field present"
        else
            fail "horizon: horizon field missing"
        fi
    else
        fail "horizon: output not produced"
    fi
    echo

    # ── contours (macOS 11+) ──────────────────────────────────────────────────

    echo "── classify: contours ───────────────────────────────────────────────────"
    $BINARY classify --img "$img" --operation contours --output "$tmp"
    local ct_got="$tmp/macos-vision-ocr_contours.json"

    if [ -f "$ct_got" ]; then
        pass "contours: output produced"
        if jq empty "$ct_got" 2>/dev/null; then
            pass "contours: valid JSON"
        else
            fail "contours: invalid JSON"
        fi
        if jq -e '.contourCount' "$ct_got" > /dev/null 2>&1; then
            pass "contours: contourCount field present"
        else
            fail "contours: contourCount field missing"
        fi
        local cnt
        cnt=$(jq '.contourCount' "$ct_got" 2>/dev/null || echo 0)
        if [ "${cnt:-0}" -gt 0 ]; then
            pass "contours: $cnt contour(s) detected"
        else
            fail "contours: no contours detected"
        fi
    else
        fail "contours: output not produced"
    fi
    echo

    # ── feature-print ─────────────────────────────────────────────────────────

    echo "── classify: feature-print ──────────────────────────────────────────────"
    $BINARY classify --img "$img" --operation feature-print --output "$tmp"
    local fp_got="$tmp/macos-vision-ocr_feature_print.json"

    if [ -f "$fp_got" ]; then
        pass "feature-print: output produced"
        if jq empty "$fp_got" 2>/dev/null; then
            pass "feature-print: valid JSON"
        else
            fail "feature-print: invalid JSON"
        fi
        if jq -e '.featurePrint.elementCount' "$fp_got" > /dev/null 2>&1; then
            pass "feature-print: elementCount present"
        else
            fail "feature-print: elementCount missing"
        fi
        if jq -e '.featurePrint.data' "$fp_got" > /dev/null 2>&1; then
            pass "feature-print: data (base64) present"
        else
            fail "feature-print: data missing"
        fi
    else
        fail "feature-print: output not produced"
    fi
    echo

    # ── error handling ────────────────────────────────────────────────────────

    echo "── classify: error handling ─────────────────────────────────────────────"
    local err_out
    err_out=$($BINARY classify 2>&1 || true)
    if echo "$err_out" | grep -qi "img\|must be provided\|error"; then
        pass "classify: missing input error shown"
    else
        fail "classify: no error on missing input"
    fi

    local op_err
    op_err=$($BINARY classify --img "$img" --operation bad-op 2>&1 || true)
    if echo "$op_err" | grep -qi "unknown\|supported\|error"; then
        pass "classify: unknown operation error shown"
    else
        fail "classify: unknown operation not rejected"
    fi
    echo
}
