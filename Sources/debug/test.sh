run_debug_tests() {
    # ── single image ──────────────────────────────────────────────────────────

    echo "── Debug: single image ──────────────────────────────────────────────────"
    local tmp_single="$TMPDIR_ROOT/debug_single"
    mkdir -p "$tmp_single"
    $BINARY debug --img "$IMAGES/handwriting.webp" --output "$tmp_single"

    local dbg_file="$tmp_single/handwriting.json"
    if jq empty "$dbg_file" 2>/dev/null; then
        pass "debug/single: valid JSON"
    else
        fail "debug/single: invalid JSON"
    fi
    for field in filename filepath width height filesize; do
        local val
        val=$(jq -r ".$field // empty" "$dbg_file")
        if [ -n "$val" ]; then
            pass "debug/single: $field present ($val)"
        else
            fail "debug/single: $field missing"
        fi
    done
    local w h fn fs
    w=$(jq '.width'    "$dbg_file"); [ "$w" = "1600" ]          && pass "debug/single: width=1600"        || fail "debug/single: width (got $w)"
    h=$(jq '.height'   "$dbg_file"); [ "$h" = "720"  ]          && pass "debug/single: height=720"        || fail "debug/single: height (got $h)"
    fn=$(jq -r '.filename' "$dbg_file"); [ "$fn" = "handwriting.webp" ] && pass "debug/single: filename" || fail "debug/single: filename (got $fn)"
    fs=$(jq '.filesize' "$dbg_file"); [ "$fs" -gt 0 ]           && pass "debug/single: filesize ($fs bytes)" || fail "debug/single: filesize not positive"
    echo

    # ── batch mode ────────────────────────────────────────────────────────────

    echo "── Debug: batch ─────────────────────────────────────────────────────────"
    local tmp_batch="$TMPDIR_ROOT/debug_batch"
    mkdir -p "$tmp_batch"
    $BINARY debug --img-dir "$IMAGES" --output-dir "$tmp_batch"

    for base in handwriting.webp macos-vision-ocr.jpg; do
        local f="$tmp_batch/${base}.json"
        if [ -f "$f" ]; then
            pass "debug/batch: ${base}.json produced"
            jq empty "$f" 2>/dev/null && pass "debug/batch: ${base}.json valid JSON" || fail "debug/batch: ${base}.json invalid JSON"
        else
            fail "debug/batch: ${base}.json not produced"
        fi
    done
    w=$(jq '.width'  "$tmp_batch/macos-vision-ocr.jpg.json"); [ "$w" = "1782" ] && pass "debug/batch: macos-vision-ocr.jpg width=1782"  || fail "debug/batch: macos-vision-ocr.jpg width (got $w)"
    h=$(jq '.height' "$tmp_batch/macos-vision-ocr.jpg.json"); [ "$h" = "970"  ] && pass "debug/batch: macos-vision-ocr.jpg height=970"   || fail "debug/batch: macos-vision-ocr.jpg height (got $h)"
    echo

    # ── error handling ────────────────────────────────────────────────────────

    echo "── Debug: error handling ────────────────────────────────────────────────"
    local dbg_err
    dbg_err=$($BINARY debug 2>&1 || true)
    if echo "$dbg_err" | grep -qi "img\|must be provided\|error"; then
        pass "debug: missing input error shown"
    else
        fail "debug: no error on missing input"
    fi
    echo
}
