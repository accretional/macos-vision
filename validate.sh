#!/usr/bin/env bash
# Usage:
#   ./validate.sh           — run all checks
#   ./validate.sh --reset   — delete baseline and regenerate it
set -euo pipefail

BINARY=".build/debug/macos-vision"
IMAGES="images"
BASELINE="tests/baseline"
TMPDIR_ROOT=$(mktemp -d)
trap 'rm -rf "$TMPDIR_ROOT"' EXIT

PASS=0
FAIL=0

# ── helpers ───────────────────────────────────────────────────────────────────

pass() { echo "  PASS  $1"; PASS=$((PASS + 1)); }
fail() { echo "  FAIL  $1"; FAIL=$((FAIL + 1)); }

require_field() {
    local label="$1" file="$2" field="$3"
    local val
    val=$(jq -r "$field // empty" "$file" 2>/dev/null)
    if [ -n "$val" ]; then
        pass "$label: $field present"
    else
        fail "$label: $field missing or null"
    fi
}

check_structure() {
    local label="$1" file="$2"
    if ! jq empty "$file" 2>/dev/null; then
        fail "$label: invalid JSON"
        return
    fi
    pass "$label: valid JSON"
    require_field "$label" "$file" '.info.filename'
    require_field "$label" "$file" '.info.width'
    require_field "$label" "$file" '.info.height'
    require_field "$label" "$file" '.texts'

    local obs_count
    obs_count=$(jq '.observations | length' "$file")
    if [ "$obs_count" -gt 0 ]; then
        pass "$label: $obs_count observations"
    else
        fail "$label: no observations"
    fi

    local texts_len
    texts_len=$(jq -r '.texts' "$file" | wc -c | tr -d ' ')
    if [ "$texts_len" -gt 1 ]; then
        pass "$label: texts non-empty"
    else
        fail "$label: texts is empty"
    fi
}

check_metadata() {
    local label="$1" file="$2" expected_filename="$3" expected_w="$4" expected_h="$5"
    local got_fn got_w got_h
    got_fn=$(jq -r '.info.filename' "$file")
    got_w=$(jq -r '.info.width'    "$file")
    got_h=$(jq -r '.info.height'   "$file")
    [ "$got_fn" = "$expected_filename" ] && pass "$label: filename ($got_fn)"   || fail "$label: filename (got $got_fn, expected $expected_filename)"
    [ "$got_w"  = "$expected_w"        ] && pass "$label: width ($got_w)"       || fail "$label: width (got $got_w, expected $expected_w)"
    [ "$got_h"  = "$expected_h"        ] && pass "$label: height ($got_h)"      || fail "$label: height (got $got_h, expected $expected_h)"
}

check_baseline() {
    local label="$1" got="$2" exp="$3"
    local got_texts exp_texts got_n exp_n
    got_texts=$(jq -r '.texts' "$got")
    exp_texts=$(jq -r '.texts' "$exp")
    got_n=$(jq '.observations | length' "$got")
    exp_n=$(jq '.observations | length' "$exp")

    if [ "$got_texts" = "$exp_texts" ]; then
        pass "$label: texts match baseline"
    else
        fail "$label: texts differ from baseline"
        diff <(echo "$exp_texts") <(echo "$got_texts") || true
    fi

    if [ "$got_n" = "$exp_n" ]; then
        pass "$label: observation count matches baseline ($got_n)"
    else
        fail "$label: observation count (got $got_n, baseline $exp_n)"
    fi

    # Per-observation text comparison
    local got_obs exp_obs
    got_obs=$(jq -r '[.observations[].text] | join("\n")' "$got")
    exp_obs=$(jq -r '[.observations[].text] | join("\n")' "$exp")
    if [ "$got_obs" = "$exp_obs" ]; then
        pass "$label: per-observation texts match baseline"
    else
        fail "$label: per-observation texts differ from baseline"
        diff <(echo "$exp_obs") <(echo "$got_obs") || true
    fi
}

# ── build ─────────────────────────────────────────────────────────────────────

echo "Building..."
swift build 2>&1 | tail -1
echo

# ── optional reset ─────────────────────────────────────────────────────────────

if [ "${1:-}" = "--reset" ]; then
    echo "Resetting baseline..."
    rm -rf "$BASELINE"
fi

# ── generate baseline if missing ──────────────────────────────────────────────

if [ ! -d "$BASELINE" ]; then
    echo "No baseline found — generating $BASELINE/..."
    mkdir -p "$BASELINE/single" "$BASELINE/batch" "$BASELINE/merge"

    $BINARY ocr --img "$IMAGES/handwriting.webp"    --output "$BASELINE/single"
    $BINARY ocr --img "$IMAGES/macos-vision-ocr.jpg" --output "$BASELINE/single"
    $BINARY ocr --img-dir "$IMAGES" --output-dir "$BASELINE/batch"
    $BINARY ocr --img-dir "$IMAGES" --output-dir "$BASELINE/merge" --merge

    echo "Baseline saved. Re-run without --reset to validate."
    echo
fi

# ── test 1: single image ──────────────────────────────────────────────────────

echo "── Single image ─────────────────────────────────────────────────────────"
TMP1="$TMPDIR_ROOT/single"
mkdir -p "$TMP1"

$BINARY ocr --img "$IMAGES/handwriting.webp"     --output "$TMP1"
$BINARY ocr --img "$IMAGES/macos-vision-ocr.jpg" --output "$TMP1"

# Single mode strips full extension: handwriting.webp→handwriting.json, macos-vision-ocr.jpg→macos-vision-ocr.json
for img_base in handwriting macos-vision-ocr; do
    got="$TMP1/${img_base}.json"
    exp="$BASELINE/single/${img_base}.json"
    check_structure "$img_base" "$got"
    check_baseline  "$img_base" "$got" "$exp"
done

check_metadata "handwriting"      "$TMP1/handwriting.json"      "handwriting.webp"    1600 720
check_metadata "macos-vision-ocr" "$TMP1/macos-vision-ocr.json" "macos-vision-ocr.jpg" 1782 970
echo

# ── test 2: batch mode ────────────────────────────────────────────────────────

echo "── Batch mode ───────────────────────────────────────────────────────────"
TMP2="$TMPDIR_ROOT/batch"
mkdir -p "$TMP2"
$BINARY ocr --img-dir "$IMAGES" --output-dir "$TMP2"

for base in handwriting.webp.json macos-vision-ocr.jpg.json; do
    got="$TMP2/$base"
    exp="$BASELINE/batch/$base"
    if [ -f "$got" ]; then
        check_structure "batch/$base" "$got"
        check_baseline  "batch/$base" "$got" "$exp"
    else
        fail "batch/$base: not produced"
    fi
done
echo

# ── test 3: batch + merge ─────────────────────────────────────────────────────

echo "── Batch + merge ────────────────────────────────────────────────────────"
TMP3="$TMPDIR_ROOT/merge"
mkdir -p "$TMP3"
$BINARY ocr --img-dir "$IMAGES" --output-dir "$TMP3" --merge

got_merged="$TMP3/merged_output.txt"
exp_merged="$BASELINE/merge/merged_output.txt"

if [ -f "$got_merged" ]; then
    pass "merge: merged_output.txt produced"
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

# ── test 4: --lang flag ───────────────────────────────────────────────────────

echo "── --lang flag ──────────────────────────────────────────────────────────"
lang_out=$($BINARY ocr --lang 2>&1)
if echo "$lang_out" | grep -q "^Supported recognition languages:"; then
    pass "--lang: prints header"
else
    fail "--lang: missing header"
fi
if echo "$lang_out" | grep -q "^- "; then
    lang_count=$(echo "$lang_out" | grep -c "^- " || true)
    pass "--lang: $lang_count languages listed"
else
    fail "--lang: no language entries"
fi
echo

# ── test 5: error on missing input ────────────────────────────────────────────

echo "── Error handling ───────────────────────────────────────────────────────"
err_out=$($BINARY ocr 2>&1 || true)
if echo "$err_out" | grep -qi "img\|must be provided\|error"; then
    pass "missing input: error message shown"
else
    fail "missing input: no error message"
fi
echo

# ── summary ───────────────────────────────────────────────────────────────────

TOTAL=$((PASS + FAIL))
echo "────────────────────────────────────────────────────────────────────────"
echo "Results: $PASS/$TOTAL passed"
[ $FAIL -eq 0 ] && echo "All checks passed." || { echo "$FAIL check(s) failed."; exit 1; }
