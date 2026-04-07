run_ocr_tests() {
    # ── single image ──────────────────────────────────────────────────────────

    echo "── OCR: single image ────────────────────────────────────────────────────"
    local tmp_single="$TMPDIR_ROOT/ocr_single"
    mkdir -p "$tmp_single"

    $BINARY ocr --img "$IMAGES/handwriting.webp"     --output "$tmp_single"
    $BINARY ocr --img "$IMAGES/macos-vision-ocr.jpg" --output "$tmp_single"

    # single mode strips the full extension: handwriting.webp → handwriting.json
    for img_base in handwriting macos-vision-ocr; do
        local got="$tmp_single/${img_base}.json"
        local exp="$BASELINE/single/${img_base}.json"
        check_structure "$img_base" "$got"
        check_baseline  "$img_base" "$got" "$exp"
    done

    check_metadata "handwriting"      "$tmp_single/handwriting.json"      "handwriting.webp"     1600 720
    check_metadata "macos-vision-ocr" "$tmp_single/macos-vision-ocr.json" "macos-vision-ocr.jpg" 1782 970
    echo

    # ── batch mode ────────────────────────────────────────────────────────────

    echo "── OCR: batch ───────────────────────────────────────────────────────────"
    local tmp_batch="$TMPDIR_ROOT/ocr_batch"
    mkdir -p "$tmp_batch"
    $BINARY ocr --img-dir "$IMAGES" --output-dir "$tmp_batch"

    for base in handwriting.webp.json macos-vision-ocr.jpg.json; do
        local got="$tmp_batch/$base"
        local exp="$BASELINE/batch/$base"
        if [ -f "$got" ]; then
            check_structure "batch/$base" "$got"
            check_baseline  "batch/$base" "$got" "$exp"
        else
            fail "batch/$base: not produced"
        fi
    done
    echo

    # ── batch + merge ─────────────────────────────────────────────────────────

    echo "── OCR: batch + merge ───────────────────────────────────────────────────"
    local tmp_merge="$TMPDIR_ROOT/ocr_merge"
    mkdir -p "$tmp_merge"
    $BINARY ocr --img-dir "$IMAGES" --output-dir "$tmp_merge" --merge

    local got_merged="$tmp_merge/merged_output.txt"
    local exp_merged="$BASELINE/merge/merged_output.txt"
    if [ -f "$got_merged" ]; then
        pass "merge: merged_output.txt produced"
        local merged_len
        merged_len=$(wc -c < "$got_merged" | tr -d ' ')
        if [ "$merged_len" -gt 0 ]; then
            pass "merge: merged_output.txt non-empty ($merged_len bytes)"
        else
            fail "merge: merged_output.txt is empty"
        fi
        if diff -q "$got_merged" "$exp_merged" > /dev/null 2>&1; then
            pass "merge: merged_output.txt matches baseline"
        else
            fail "merge: merged_output.txt differs from baseline"
            diff "$exp_merged" "$got_merged" || true
        fi
    else
        fail "merge: merged_output.txt not produced"
    fi
    echo

    # ── --lang flag ───────────────────────────────────────────────────────────

    echo "── OCR: --lang ──────────────────────────────────────────────────────────"
    local lang_out
    lang_out=$($BINARY ocr --lang 2>&1)
    if echo "$lang_out" | grep -q "^Supported recognition languages:"; then
        pass "--lang: prints header"
    else
        fail "--lang: missing header"
    fi
    if echo "$lang_out" | grep -q "^- "; then
        local lang_count
        lang_count=$(echo "$lang_out" | grep -c "^- " || true)
        pass "--lang: $lang_count languages listed"
    else
        fail "--lang: no language entries"
    fi
    echo

    # ── --boxes-format ────────────────────────────────────────────────────────

    echo "── OCR: --boxes-format ──────────────────────────────────────────────────"
    local tmp_fmt="$TMPDIR_ROOT/ocr_fmt"
    mkdir -p "$tmp_fmt"
    cp "$IMAGES/handwriting.webp" "$tmp_fmt/"

    # default (no flag) → png
    $BINARY ocr --img "$tmp_fmt/handwriting.webp" --debug > /dev/null
    [ -f "$tmp_fmt/handwriting_boxes.png" ] && pass "boxes-format: default produces .png" || fail "boxes-format: default .png not found"
    rm -f "$tmp_fmt/handwriting_boxes.png"

    for fmt in jpg tiff bmp gif; do
        $BINARY ocr --img "$tmp_fmt/handwriting.webp" --debug --boxes-format "$fmt" > /dev/null
        local ext="$fmt"
        [ "$fmt" = "jpg" ] && ext="jpg"
        [ -f "$tmp_fmt/handwriting_boxes.${ext}" ] \
            && pass "boxes-format: --boxes-format $fmt produces .$ext" \
            || fail "boxes-format: --boxes-format $fmt — .$ext not found"
        rm -f "$tmp_fmt/handwriting_boxes.${ext}"
    done

    # jpeg alias → .jpg
    $BINARY ocr --img "$tmp_fmt/handwriting.webp" --debug --boxes-format jpeg > /dev/null
    [ -f "$tmp_fmt/handwriting_boxes.jpg" ] && pass "boxes-format: jpeg alias produces .jpg" || fail "boxes-format: jpeg alias — .jpg not found"
    rm -f "$tmp_fmt/handwriting_boxes.jpg"

    # invalid format → error
    local fmt_err
    fmt_err=$($BINARY ocr --img "$tmp_fmt/handwriting.webp" --boxes-format xyz 2>&1 || true)
    if echo "$fmt_err" | grep -qi "unsupported\|error"; then
        pass "boxes-format: invalid format rejected"
    else
        fail "boxes-format: invalid format not rejected"
    fi
    echo

    # ── error handling ────────────────────────────────────────────────────────

    echo "── OCR: error handling ──────────────────────────────────────────────────"
    local err_out
    err_out=$($BINARY ocr 2>&1 || true)
    if echo "$err_out" | grep -qi "img\|must be provided\|error"; then
        pass "ocr: missing input error shown"
    else
        fail "ocr: no error on missing input"
    fi
    echo
}
