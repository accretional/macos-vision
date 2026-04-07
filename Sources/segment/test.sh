run_segment_tests() {
    local img1="$IMAGES/fred-yass.png"
    local img2="$IMAGES/fred-yass-nobackground.png"

    # ── a. verify the two input images are different ───────────────────────────

    echo "── segment: input images differ ─────────────────────────────────────────"
    if [ ! -f "$img1" ]; then
        fail "input images differ: $img1 not found"
        echo; return
    fi
    if [ ! -f "$img2" ]; then
        fail "input images differ: $img2 not found"
        echo; return
    fi

    if cmp -s "$img1" "$img2"; then
        fail "input images differ: $img1 and $img2 are identical"
    else
        pass "input images differ: fred-yass.png ≠ fred-yass-nobackground.png"
    fi
    echo

    # ── b. remove background of image1 using foreground-mask ──────────────────

    echo "── segment: foreground-mask (background removal) ────────────────────────"
    local tmp_seg="$TMPDIR_ROOT/segment"
    mkdir -p "$tmp_seg"

    $BINARY segment --img "$img1" --operation foreground-mask --output "$tmp_seg"
    local got="$tmp_seg/fred-yass_foreground.png"

    if [ ! -f "$got" ]; then
        fail "foreground-mask: output file not produced"
        echo; return
    fi
    pass "foreground-mask: output file produced"

    # verify output dimensions match input
    local got_w got_h ref_w ref_h
    got_w=$(sips -g pixelWidth  "$got" | awk '/pixelWidth/  {print $2}')
    got_h=$(sips -g pixelHeight "$got" | awk '/pixelHeight/ {print $2}')
    ref_w=$(sips -g pixelWidth  "$img1" | awk '/pixelWidth/  {print $2}')
    ref_h=$(sips -g pixelHeight "$img1" | awk '/pixelHeight/ {print $2}')

    [ "$got_w" = "$ref_w" ] && [ "$got_h" = "$ref_h" ] \
        && pass "foreground-mask: dimensions match input (${got_w}x${got_h})" \
        || fail "foreground-mask: dimension mismatch (got ${got_w}x${got_h}, expected ${ref_w}x${ref_h})"

    # verify output has an alpha channel
    local has_alpha
    has_alpha=$(sips -g hasAlpha "$got" | awk '/hasAlpha/ {print $2}')
    [ "$has_alpha" = "yes" ] \
        && pass "foreground-mask: output has alpha channel" \
        || fail "foreground-mask: output has no alpha channel"

    # verify output is not empty (non-zero file size)
    local fsize
    fsize=$(wc -c < "$got" | tr -d ' ')
    [ "$fsize" -gt 0 ] \
        && pass "foreground-mask: output is non-empty ($fsize bytes)" \
        || fail "foreground-mask: output is empty"
    echo

    # # ── c. compare background-removed output with image2 ──────────────────────

    # echo "── segment: compare output with reference ───────────────────────────────"

    # # c1. compare against the Vision-generated baseline (regression test)
    # local baseline_img="$BASELINE/segment/fred-yass_foreground.png"
    # if [ -f "$baseline_img" ]; then
    #     if cmp -s "$got" "$baseline_img"; then
    #         pass "compare: output matches Vision baseline (byte-exact)"
    #     else
    #         fail "compare: output differs from Vision baseline"
    #     fi
    # else
    #     fail "compare: Vision baseline not found at $baseline_img"
    # fi

    # # c2. compare against the pre-existing reference image (fred-yass-nobackground.png)
    # if cmp -s "$got" "$img2"; then
    #     pass "compare: output matches fred-yass-nobackground.png (byte-exact)"
    # else
    #     # images differ — check if at least dimensions and alpha channel match
    #     local ref2_w ref2_h ref2_alpha
    #     ref2_w=$(sips -g pixelWidth  "$img2" | awk '/pixelWidth/  {print $2}')
    #     ref2_h=$(sips -g pixelHeight "$img2" | awk '/pixelHeight/ {print $2}')
    #     ref2_alpha=$(sips -g hasAlpha "$img2" | awk '/hasAlpha/ {print $2}')

    #     if [ "$got_w" = "$ref2_w" ] && [ "$got_h" = "$ref2_h" ] && [ "$has_alpha" = "$ref2_alpha" ]; then
    #         pass "compare: output and fred-yass-nobackground.png have matching dimensions and alpha (${got_w}x${got_h}, alpha=${has_alpha})"
    #         fail "compare: pixel content differs from fred-yass-nobackground.png (reference was made by a different tool)"
    #     else
    #         fail "compare: output and fred-yass-nobackground.png differ in dimensions or alpha"
    #     fi
    # fi
    # echo
}
