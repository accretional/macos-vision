BINARY=".build/debug/macos-vision"
IMAGES="data/images"
BASELINE="tests/tmp/baseline"

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

# check_structure: validates an OCR output JSON (info, observations, texts)
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

# check_metadata: validates info.filename/width/height in an OCR output JSON
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

# check_baseline: compares texts, observation count, and per-observation texts
# against a stored baseline JSON file
check_baseline() {
    local label="$1" got="$2" exp="$3"
    local got_texts exp_texts got_n exp_n

    got_texts=$(jq -r '.texts' "$got")
    exp_texts=$(jq -r '.texts' "$exp")
    if [ "$got_texts" = "$exp_texts" ]; then
        pass "$label: texts match baseline"
    else
        fail "$label: texts differ from baseline"
        diff <(echo "$exp_texts") <(echo "$got_texts") || true
    fi

    got_n=$(jq '.observations | length' "$got")
    exp_n=$(jq '.observations | length' "$exp")
    if [ "$got_n" = "$exp_n" ]; then
        pass "$label: observation count matches baseline ($got_n)"
    else
        fail "$label: observation count (got $got_n, baseline $exp_n)"
    fi

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
