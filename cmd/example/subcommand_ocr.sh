#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}="{root}/{v}"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/ocr"
mkdir -p "$OUTPUT"

# OCR JSON is <stem>.json in the output dir (no operation suffix).
overlay_ocr() {
    local img="$1"
    local stem json
    stem=$(basename "$img"); stem="${stem%.*}"
    json="$OUTPUT/${stem}.json"
    if [ ! -f "$json" ]; then
        echo "  SKIP  overlay ($json not found)"
        return
    fi
    if [ ! -f "$img" ]; then
        echo "  SKIP  overlay (source image missing)"
        return
    fi
    echo "  RUN   overlay ${stem}.svg"
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

run_ocr() {
    local label="$1" img="$2"
    run "$label" "$img" \
        "$BINARY" ocr --input "$img" --output "$OUTPUT"
    overlay_ocr "$img"
}

# ── printed text ──────────────────────────────────────────────────────────────
run_ocr "ocr-printed" "$EXAMPLE_IMG_TEXT_PRINTED"

# ── handwritten text ──────────────────────────────────────────────────────────
run_ocr "ocr-handwritten" "$EXAMPLE_IMG_HANDWRITING"
