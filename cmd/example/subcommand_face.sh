#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
IMG="$ROOT/sample_data/input/images"
OUTPUT="$ROOT/sample_data/output/face"

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

# ── face-rectangles ───────────────────────────────────────────────────────────
run "face-rectangles" "$IMG/bohemian_rhapsody.jpg" \
    "$BINARY" face --img "$IMG/bohemian_rhapsody.jpg" \
                   --operation face-rectangles \
                   --output "$OUTPUT" \
                   --svg

# ── face-landmarks ────────────────────────────────────────────────────────────
run "face-landmarks" "$IMG/fred_yass.png" \
    "$BINARY" face --img "$IMG/fred_yass.png" \
                   --operation face-landmarks \
                   --output "$OUTPUT" \
                   --svg

# ── face-quality ──────────────────────────────────────────────────────────────
run "face-quality" "$IMG/fred_yass.png" \
    "$BINARY" face --img "$IMG/fred_yass.png" \
                   --operation face-quality \
                   --output "$OUTPUT" \
                   --svg

# ── human-rectangles ──────────────────────────────────────────────────────────
run "human-rectangles" "$IMG/spiderman.jpg" \
    "$BINARY" face --img "$IMG/spiderman.jpg" \
                   --operation human-rectangles \
                   --output "$OUTPUT" \
                   --svg

# ── body-pose ─────────────────────────────────────────────────────────────────
run "body-pose" "$IMG/sad_pablo.png" \
    "$BINARY" face --img "$IMG/sad_pablo.png" \
                   --operation body-pose \
                   --output "$OUTPUT" \
                   --svg

# ── hand-pose ─────────────────────────────────────────────────────────────────
run "hand-pose" "$IMG/spiderman.jpg" \
    "$BINARY" face --img "$IMG/spiderman.jpg" \
                   --operation hand-pose \
                   --output "$OUTPUT" \
                   --svg

# ── animal-pose ───────────────────────────────────────────────────────────────
run "animal-pose" "$IMG/raccoon_cotton_candy.jpg" \
    "$BINARY" face --img "$IMG/raccoon_cotton_candy.jpg" \
                   --operation animal-pose \
                   --output "$OUTPUT" \
                   --svg
