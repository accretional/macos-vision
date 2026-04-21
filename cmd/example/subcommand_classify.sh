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
run "classify" "$CLASSIFY_CLASSIFY_INPUT" \
    "$BINARY" classify --input "$CLASSIFY_CLASSIFY_INPUT" \
                       --operation classify \
                       --output "$OUTPUT"

# ── animals ───────────────────────────────────────────────────────────────────
run "animals" "$CLASSIFY_ANIMALS_INPUT" \
    "$BINARY" classify --input "$CLASSIFY_ANIMALS_INPUT" \
                       --operation animals \
                       --output "$OUTPUT"
overlay_classify "$CLASSIFY_ANIMALS_INPUT" animals

# ── rectangles ────────────────────────────────────────────────────────────────
run "rectangles" "$CLASSIFY_RECTANGLES_INPUT" \
    "$BINARY" classify --input "$CLASSIFY_RECTANGLES_INPUT" \
                       --operation rectangles \
                       --output "$OUTPUT"
overlay_classify "$CLASSIFY_RECTANGLES_INPUT" rectangles

# ── horizon ───────────────────────────────────────────────────────────────────
run "horizon" "$CLASSIFY_HORIZON_INPUT" \
    "$BINARY" classify --input "$CLASSIFY_HORIZON_INPUT" \
                       --operation horizon \
                       --output "$OUTPUT"

# ── contours (no SVG — count + aspect ratios only, no coordinates) ────────────
run "contours" "$CLASSIFY_CONTOURS_INPUT" \
    "$BINARY" classify --input "$CLASSIFY_CONTOURS_INPUT" \
                       --operation contours \
                       --output "$OUTPUT"

# ── aesthetics (no SVG — score only) ─────────────────────────────────────────
run "aesthetics" "$CLASSIFY_AESTHETICS_INPUT" \
    "$BINARY" classify --input "$CLASSIFY_AESTHETICS_INPUT" \
                       --operation aesthetics \
                       --output "$OUTPUT"

# ── feature-print (no SVG — embedding vector only) ────────────────────────────
run "feature-print" "$CLASSIFY_FEATURE_PRINT_INPUT" \
    "$BINARY" classify --input "$CLASSIFY_FEATURE_PRINT_INPUT" \
                       --operation feature-print \
                       --output "$OUTPUT"
