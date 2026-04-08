run_svg_tests() {
    local img="$IMAGES/fred-yass.png"

    if [ ! -f "$img" ]; then
        fail "svg tests: $img not found"
        echo; return
    fi

    local tmp="$TMPDIR_ROOT/svg"
    mkdir -p "$tmp"

    # ── generate face-landmarks JSON first ────────────────────────────────────

    echo "── svg: setup — generating face-landmarks JSON ──────────────────────────"
    $BINARY face --img "$img" --operation face-landmarks --output "$tmp"
    local lm_json="$tmp/fred-yass_face_landmarks.json"

    if [ ! -f "$lm_json" ]; then
        fail "svg: prerequisite face-landmarks JSON not produced"
        echo; return
    fi
    pass "svg: face-landmarks JSON available"
    echo

    # ── svg from face-landmarks JSON ──────────────────────────────────────────

    echo "── svg: face-landmarks overlay ──────────────────────────────────────────"
    $BINARY svg --json "$lm_json" --output "$tmp"
    local lm_svg="$tmp/fred-yass_face_landmarks.svg"

    if [ -f "$lm_svg" ]; then
        pass "svg: face-landmarks SVG produced"
        if grep -q "<svg" "$lm_svg" 2>/dev/null; then
            pass "svg: file starts with SVG element"
        else
            fail "svg: missing <svg element"
        fi
        if grep -q "<image" "$lm_svg" 2>/dev/null; then
            pass "svg: image element embedded"
        else
            fail "svg: image not embedded"
        fi
        if grep -q "base64" "$lm_svg" 2>/dev/null; then
            pass "svg: base64 image data present"
        else
            fail "svg: base64 image data missing"
        fi
        if grep -q "<rect\|<circle\|<polyline\|<polygon\|<line" "$lm_svg" 2>/dev/null; then
            pass "svg: shape elements present"
        else
            fail "svg: no shape elements found"
        fi
    else
        fail "svg: face-landmarks SVG not produced"
    fi
    echo

    # ── svg from face-rectangles JSON ────────────────────────────────────────

    echo "── svg: face-rectangles overlay ─────────────────────────────────────────"
    $BINARY face --img "$img" --operation face-rectangles --output "$tmp"
    local fr_json="$tmp/fred-yass_face_rectangles.json"
    $BINARY svg --json "$fr_json" --output "$tmp"
    local fr_svg="$tmp/fred-yass_face_rectangles.svg"

    if [ -f "$fr_svg" ]; then
        pass "svg: face-rectangles SVG produced"
        if grep -q "<rect" "$fr_svg" 2>/dev/null; then
            pass "svg: rect elements present for face boxes"
        else
            fail "svg: no rect elements for face boxes"
        fi
    else
        fail "svg: face-rectangles SVG not produced"
    fi
    echo

    # ── img override via --img flag ───────────────────────────────────────────

    echo "── svg: --img override ──────────────────────────────────────────────────"
    $BINARY svg --json "$fr_json" --img "$img" --output "$tmp"
    if [ -f "$fr_svg" ]; then
        pass "svg: --img override accepted"
    else
        fail "svg: --img override failed"
    fi
    echo

    # ── error handling ────────────────────────────────────────────────────────

    echo "── svg: error handling ──────────────────────────────────────────────────"
    local err_out
    err_out=$($BINARY svg 2>&1 || true)
    if echo "$err_out" | grep -qi "json\|required\|error"; then
        pass "svg: missing --json error shown"
    else
        fail "svg: no error on missing --json"
    fi

    local bad_err
    bad_err=$($BINARY svg --json /nonexistent/path.json 2>&1 || true)
    if echo "$bad_err" | grep -qi "error\|not found\|no such"; then
        pass "svg: nonexistent JSON error shown"
    else
        fail "svg: no error for nonexistent JSON"
    fi
    echo
}
