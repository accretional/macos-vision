run_face_tests() {
    local img="$IMAGES/fred-yass.png"

    if [ ! -f "$img" ]; then
        fail "face tests: $img not found"
        echo; return
    fi

    # ── face-rectangles ───────────────────────────────────────────────────────

    echo "── face: face-rectangles ────────────────────────────────────────────────"
    local tmp="$TMPDIR_ROOT/face"
    mkdir -p "$tmp"

    $BINARY face --img "$img" --operation face-rectangles --output "$tmp"
    local got="$tmp/fred-yass_face_rectangles.json"

    if [ -f "$got" ]; then
        pass "face-rectangles: output produced"
        if jq empty "$got" 2>/dev/null; then
            pass "face-rectangles: valid JSON"
        else
            fail "face-rectangles: invalid JSON"
        fi
        local face_count
        face_count=$(jq '.faces | length' "$got" 2>/dev/null || echo 0)
        if [ "$face_count" -gt 0 ]; then
            pass "face-rectangles: $face_count face(s) detected"
        else
            fail "face-rectangles: no faces detected"
        fi
        if jq -e '.faces[0].boundingBox.x' "$got" > /dev/null 2>&1; then
            pass "face-rectangles: boundingBox present"
        else
            fail "face-rectangles: boundingBox missing"
        fi
    else
        fail "face-rectangles: output not produced"
    fi
    echo

    # ── face-landmarks ────────────────────────────────────────────────────────

    echo "── face: face-landmarks ─────────────────────────────────────────────────"
    $BINARY face --img "$img" --operation face-landmarks --output "$tmp"
    local lm="$tmp/fred-yass_face_landmarks.json"

    if [ -f "$lm" ]; then
        pass "face-landmarks: output produced"
        if jq empty "$lm" 2>/dev/null; then
            pass "face-landmarks: valid JSON"
        else
            fail "face-landmarks: invalid JSON"
        fi
        local has_landmarks
        has_landmarks=$(jq '.faces[0].landmarks | length' "$lm" 2>/dev/null || echo 0)
        if [ "${has_landmarks:-0}" -gt 0 ]; then
            pass "face-landmarks: landmark regions present"
        else
            fail "face-landmarks: no landmark regions found"
        fi
    else
        fail "face-landmarks: output not produced"
    fi
    echo

    # ── face-quality ──────────────────────────────────────────────────────────

    echo "── face: face-quality ───────────────────────────────────────────────────"
    $BINARY face --img "$img" --operation face-quality --output "$tmp"
    local fq="$tmp/fred-yass_face_quality.json"

    if [ -f "$fq" ]; then
        pass "face-quality: output produced"
        if jq empty "$fq" 2>/dev/null; then
            pass "face-quality: valid JSON"
        else
            fail "face-quality: invalid JSON"
        fi
    else
        fail "face-quality: output not produced"
    fi
    echo

    # ── body-pose (macOS 11+) ─────────────────────────────────────────────────

    echo "── face: body-pose ──────────────────────────────────────────────────────"
    $BINARY face --img "$img" --operation body-pose --output "$tmp"
    local bp="$tmp/fred-yass_body_pose.json"

    if [ -f "$bp" ]; then
        pass "body-pose: output produced"
        if jq empty "$bp" 2>/dev/null; then
            pass "body-pose: valid JSON"
        else
            fail "body-pose: invalid JSON"
        fi
        local body_count
        body_count=$(jq '.bodies | length' "$bp" 2>/dev/null || echo 0)
        pass "body-pose: ${body_count:-0} body/bodies detected (may be 0 for headshot images)"
    else
        fail "body-pose: output not produced"
    fi
    echo

    # ── human-rectangles (macOS 12+) ──────────────────────────────────────────

    echo "── face: human-rectangles ───────────────────────────────────────────────"
    $BINARY face --img "$img" --operation human-rectangles --output "$tmp"
    local hr="$tmp/fred-yass_human_rectangles.json"

    if [ -f "$hr" ]; then
        pass "human-rectangles: output produced"
        if jq empty "$hr" 2>/dev/null; then
            pass "human-rectangles: valid JSON"
        else
            fail "human-rectangles: invalid JSON"
        fi
    else
        fail "human-rectangles: output not produced"
    fi
    echo

    # ── error handling ────────────────────────────────────────────────────────

    echo "── face: error handling ─────────────────────────────────────────────────"
    local err_out
    err_out=$($BINARY face 2>&1 || true)
    if echo "$err_out" | grep -qi "img\|must be provided\|error"; then
        pass "face: missing input error shown"
    else
        fail "face: no error on missing input"
    fi

    local op_err
    op_err=$($BINARY face --img "$img" --operation bad-op 2>&1 || true)
    if echo "$op_err" | grep -qi "unknown\|supported\|error"; then
        pass "face: unknown operation error shown"
    else
        fail "face: unknown operation not rejected"
    fi
    echo
}
