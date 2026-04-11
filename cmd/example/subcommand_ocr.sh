#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
IMG="$ROOT/sample_data/input/images"
OUTPUT="$ROOT/sample_data/output/ocr"

mkdir -p "$OUTPUT"

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
        "$BINARY" ocr --img "$img" --output "$OUTPUT"
}

# ── printed text ──────────────────────────────────────────────────────────────
run_ocr "ocr-printed" \
    "$IMG/text_printed.jpg" \
    "$OUTPUT/text_printed.json"

# ── handwritten text ──────────────────────────────────────────────────────────
run_ocr "ocr-handwritten" \
    "$IMG/handwriting.png" \
    "$OUTPUT/handwriting.json"
