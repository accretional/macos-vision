run_track_tests() {
    local tmp="$TMPDIR_ROOT/track"
    mkdir -p "$tmp"

    # ── error handling ────────────────────────────────────────────────────────

    echo "── track: error handling ────────────────────────────────────────────────"
    local err_out
    err_out=$($BINARY track 2>&1 || true)
    if echo "$err_out" | grep -qi "video\|img-dir\|must be provided\|error"; then
        pass "track: missing input error shown"
    else
        fail "track: no error on missing input"
    fi

    local bad_video
    bad_video=$($BINARY track --video /nonexistent/video.mp4 2>&1 || true)
    if echo "$bad_video" | grep -qi "not found\|error\|failed"; then
        pass "track: missing video file error shown"
    else
        fail "track: missing video file not rejected"
    fi

    local op_err
    op_err=$($BINARY track --img-dir "$IMAGES" --operation bad-op 2>&1 || true)
    if echo "$op_err" | grep -qi "unknown\|supported\|error"; then
        pass "track: unknown operation error shown"
    else
        fail "track: unknown operation not rejected"
    fi
    echo

    # ── homographic (image sequence) ──────────────────────────────────────────

    echo "── track: homographic (image sequence) ──────────────────────────────────"
    $BINARY track --img-dir "$IMAGES" --operation homographic --output "$tmp"
    local hom="$tmp/track_homographic.json"

    if [ -f "$hom" ]; then
        pass "homographic: output produced"
        if jq empty "$hom" 2>/dev/null; then
            pass "homographic: valid JSON"
        else
            fail "homographic: invalid JSON"
        fi
        if jq -e '.frameCount' "$hom" > /dev/null 2>&1; then
            pass "homographic: frameCount field present"
        else
            fail "homographic: frameCount field missing"
        fi
        if jq -e '.frames' "$hom" > /dev/null 2>&1; then
            pass "homographic: frames field present"
        else
            fail "homographic: frames field missing"
        fi
    else
        fail "homographic: output not produced"
    fi
    echo

    # ── translational (image sequence) ────────────────────────────────────────

    echo "── track: translational (image sequence) ────────────────────────────────"
    $BINARY track --img-dir "$IMAGES" --operation translational --output "$tmp"
    local trl="$tmp/track_translational.json"

    if [ -f "$trl" ]; then
        pass "translational: output produced"
        if jq empty "$trl" 2>/dev/null; then
            pass "translational: valid JSON"
        else
            fail "translational: invalid JSON"
        fi
        if jq -e '.frames' "$trl" > /dev/null 2>&1; then
            pass "translational: frames field present"
        else
            fail "translational: frames field missing"
        fi
    else
        fail "translational: output not produced"
    fi
    echo

    # ── trajectories (image sequence) ─────────────────────────────────────────

    echo "── track: trajectories (image sequence) ─────────────────────────────────"
    $BINARY track --img-dir "$IMAGES" --operation trajectories --output "$tmp"
    local trj="$tmp/track_trajectories.json"

    if [ -f "$trj" ]; then
        pass "trajectories: output produced"
        if jq empty "$trj" 2>/dev/null; then
            pass "trajectories: valid JSON"
        else
            fail "trajectories: invalid JSON"
        fi
        if jq -e '.trajectories' "$trj" > /dev/null 2>&1; then
            pass "trajectories: trajectories field present"
        else
            fail "trajectories: trajectories field missing"
        fi
    else
        fail "trajectories: output not produced"
    fi
    echo
}
