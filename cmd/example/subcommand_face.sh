#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}="{root}/{v}"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/face"
mkdir -p "$OUTPUT"

# Write <stem>_<operation>.svg next to the JSON from `face --output "$OUTPUT"`.
overlay_face() {
    local img="$1" operation="$2"
    local stem op json
    stem=$(basename "$img"); stem="${stem%.*}"
    op="${operation//-/_}"
    json="$OUTPUT/${stem}_${op}.json"
    if [ ! -f "$json" ]; then
        echo "  SKIP  overlay (source json not found)"
        return
    fi
    if [ ! -f "$img" ]; then
        echo "  SKIP  overlay (source image missing)"
        return
    fi
    echo "  RUN   overlay ${stem}_${op}.svg"
    "$BINARY" overlay --json "$json" --input "$img" --output "$OUTPUT"
}

run() {
    local label="$1" img="$2"; shift 2
    if [ ! -f "$img" ]; then
        echo "  SKIP  $label ($(basename "$img") not found)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

# ── face-rectangles ───────────────────────────────────────────────────────────
run "face-rectangles" "$EXAMPLE_IMG_BOHEMIAN" \
    "$BINARY" face --input "$EXAMPLE_IMG_BOHEMIAN" \
                   --operation face-rectangles \
                   --output "$OUTPUT"
overlay_face "$EXAMPLE_IMG_BOHEMIAN" face-rectangles

# ── face-landmarks ────────────────────────────────────────────────────────────
run "face-landmarks" "$EXAMPLE_IMG_FRED_YASS" \
    "$BINARY" face --input "$EXAMPLE_IMG_FRED_YASS" \
                   --operation face-landmarks \
                   --output "$OUTPUT"
overlay_face "$EXAMPLE_IMG_FRED_YASS" face-landmarks

# ── face-quality ──────────────────────────────────────────────────────────────
run "face-quality" "$EXAMPLE_IMG_FRED_YASS" \
    "$BINARY" face --input "$EXAMPLE_IMG_FRED_YASS" \
                   --operation face-quality \
                   --output "$OUTPUT"
overlay_face "$EXAMPLE_IMG_FRED_YASS" face-quality

# ── human-rectangles ──────────────────────────────────────────────────────────
run "human-rectangles" "$EXAMPLE_IMG_SPIDERMAN" \
    "$BINARY" face --input "$EXAMPLE_IMG_SPIDERMAN" \
                   --operation human-rectangles \
                   --output "$OUTPUT"
overlay_face "$EXAMPLE_IMG_SPIDERMAN" human-rectangles

# ── body-pose ─────────────────────────────────────────────────────────────────
run "body-pose" "$EXAMPLE_IMG_SAD_PABLO" \
    "$BINARY" face --input "$EXAMPLE_IMG_SAD_PABLO" \
                   --operation body-pose \
                   --output "$OUTPUT"
overlay_face "$EXAMPLE_IMG_SAD_PABLO" body-pose

# ── hand-pose ─────────────────────────────────────────────────────────────────
run "hand-pose" "$EXAMPLE_IMG_SPIDERMAN" \
    "$BINARY" face --input "$EXAMPLE_IMG_SPIDERMAN" \
                   --operation hand-pose \
                   --output "$OUTPUT"
overlay_face "$EXAMPLE_IMG_SPIDERMAN" hand-pose

# ── animal-pose (cat_side_eye → cat_side_eye_animal_pose.json for field journal)
run "animal-pose" "$EXAMPLE_IMG_RACCOON_COTTON_CANDY" \
    "$BINARY" face --input "$EXAMPLE_IMG_RACCOON_COTTON_CANDY" \
                   --operation animal-pose \
                   --output "$OUTPUT"
overlay_face "$EXAMPLE_IMG_RACCOON_COTTON_CANDY" animal-pose
