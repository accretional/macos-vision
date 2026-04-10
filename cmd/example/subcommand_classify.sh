#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
IMG="$ROOT/sample_data/input/images"
OUTPUT="$ROOT/sample_data/output/classify"

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

# ── classify (no SVG — image-level labels only, no spatial data) ──────────────
run "classify" "$IMG/gorilla.jpg" \
    "$BINARY" classify --img "$IMG/gorilla.jpg" \
                       --operation classify \
                       --output "$OUTPUT"

# ── animals ───────────────────────────────────────────────────────────────────
run "animals" "$IMG/cat_side_eye.jpg" \
    "$BINARY" classify --img "$IMG/cat_side_eye.jpg" \
                       --operation animals \
                       --output "$OUTPUT" \
                       --svg

# ── rectangles ────────────────────────────────────────────────────────────────
run "rectangles" "$IMG/document.jpg" \
    "$BINARY" classify --img "$IMG/document.jpg" \
                       --operation rectangles \
                       --output "$OUTPUT" \
                       --svg

# ── horizon ───────────────────────────────────────────────────────────────────
run "horizon" "$IMG/sad_pablo.png" \
    "$BINARY" classify --img "$IMG/sad_pablo.png" \
                       --operation horizon \
                       --output "$OUTPUT" \
                       --svg

# ── contours (no SVG — count + aspect ratios only, no coordinates) ────────────
run "contours" "$IMG/gorilla.jpg" \
    "$BINARY" classify --img "$IMG/gorilla.jpg" \
                       --operation contours \
                       --output "$OUTPUT"

# ── aesthetics (no SVG — score only) ─────────────────────────────────────────
run "aesthetics" "$IMG/gorilla.jpg" \
    "$BINARY" classify --img "$IMG/gorilla.jpg" \
                       --operation aesthetics \
                       --output "$OUTPUT"

# ── feature-print (no SVG — embedding vector only) ────────────────────────────
run "feature-print" "$IMG/gorilla.jpg" \
    "$BINARY" classify --img "$IMG/gorilla.jpg" \
                       --operation feature-print \
                       --output "$OUTPUT"
