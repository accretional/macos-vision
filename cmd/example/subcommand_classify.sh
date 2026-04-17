#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}="{root}/{v}"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/classify"
mkdir -p "$OUTPUT"

# Spatial classify ops → <stem>_<operation>.svg (same layout as `classify --output "$OUTPUT"`).
overlay_classify() {
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

# ── classify (no SVG — image-level labels only, no spatial data) ──────────────
run "classify" "$EXAMPLE_IMG_GORILLA" \
    "$BINARY" classify --input "$EXAMPLE_IMG_GORILLA" \
                       --operation classify \
                       --output "$OUTPUT"

# ── animals ───────────────────────────────────────────────────────────────────
run "animals" "$EXAMPLE_IMG_CAT_SIDE_EYE" \
    "$BINARY" classify --input "$EXAMPLE_IMG_CAT_SIDE_EYE" \
                       --operation animals \
                       --output "$OUTPUT"
overlay_classify "$EXAMPLE_IMG_CAT_SIDE_EYE" animals

# ── rectangles ────────────────────────────────────────────────────────────────
run "rectangles" "$EXAMPLE_IMG_DOCUMENT" \
    "$BINARY" classify --input "$EXAMPLE_IMG_DOCUMENT" \
                       --operation rectangles \
                       --output "$OUTPUT"
overlay_classify "$EXAMPLE_IMG_DOCUMENT" rectangles

# ── horizon ───────────────────────────────────────────────────────────────────
run "horizon" "$EXAMPLE_IMG_SAD_PABLO" \
    "$BINARY" classify --input "$EXAMPLE_IMG_SAD_PABLO" \
                       --operation horizon \
                       --output "$OUTPUT"

# ── contours (no SVG — count + aspect ratios only, no coordinates) ────────────
run "contours" "$EXAMPLE_IMG_GORILLA" \
    "$BINARY" classify --input "$EXAMPLE_IMG_GORILLA" \
                       --operation contours \
                       --output "$OUTPUT"

# ── aesthetics (no SVG — score only) ─────────────────────────────────────────
run "aesthetics" "$EXAMPLE_IMG_GORILLA" \
    "$BINARY" classify --input "$EXAMPLE_IMG_GORILLA" \
                       --operation aesthetics \
                       --output "$OUTPUT"

# ── feature-print (no SVG — embedding vector only) ────────────────────────────
run "feature-print" "$EXAMPLE_IMG_GORILLA" \
    "$BINARY" classify --input "$EXAMPLE_IMG_GORILLA" \
                       --operation feature-print \
                       --output "$OUTPUT"
