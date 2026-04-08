#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
IMG="$ROOT/sample_data/input/images"
OUTPUT="$ROOT/sample_data/output/segment"

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

# ── foreground-mask ───────────────────────────────────────────────────────────
run "foreground-mask" "$IMG/sad_pablo.png" \
    "$BINARY" segment --img "$IMG/sad_pablo.png" \
                      --operation foreground-mask \
                      --output "$OUTPUT"

# ── person-segment ────────────────────────────────────────────────────────────
run "person-segment" "$IMG/gorilla.jpg" \
    "$BINARY" segment --img "$IMG/gorilla.jpg" \
                      --operation person-segment \
                      --output "$OUTPUT"

# ── person-mask ───────────────────────────────────────────────────────────────
run "person-mask" "$IMG/gorilla.jpg" \
    "$BINARY" segment --img "$IMG/gorilla.jpg" \
                      --operation person-mask \
                      --output "$OUTPUT"

# ── attention-saliency ────────────────────────────────────────────────────────
run "attention-saliency" "$IMG/gorilla.jpg" \
    "$BINARY" segment --img "$IMG/gorilla.jpg" \
                      --operation attention-saliency \
                      --output "$OUTPUT"

# ── objectness-saliency ───────────────────────────────────────────────────────
run "objectness-saliency" "$IMG/gorilla.jpg" \
    "$BINARY" segment --img "$IMG/gorilla.jpg" \
                      --operation objectness-saliency \
                      --output "$OUTPUT"
