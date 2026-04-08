#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
VID="$ROOT/sample_data/input/videos"
FRAMES="$VID/selective_attention_test_frames"
VIDEO="$VID/selective_attention_test.mp4"
OUTPUT="$ROOT/sample_data/output/track"

mkdir -p "$OUTPUT"

run_seq() {
    local label="$1" dir="$2"; shift 2
    if [ ! -d "$dir" ] || [ -z "$(ls "$dir"/*.jpg "$dir"/*.png 2>/dev/null)" ]; then
        echo "  SKIP  $label ($(basename "$dir")/ not found or empty)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

run_vid() {
    local label="$1" vid="$2"; shift 2
    if [ ! -f "$vid" ]; then
        echo "  SKIP  $label ($(basename "$vid") not found)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

# ── homographic ───────────────────────────────────────────────────────────────
run_seq "homographic" "$FRAMES" \
    "$BINARY" track --img-dir "$FRAMES" \
                    --operation homographic \
                    --output "$OUTPUT"

# ── translational ─────────────────────────────────────────────────────────────
run_seq "translational" "$FRAMES" \
    "$BINARY" track --img-dir "$FRAMES" \
                    --operation translational \
                    --output "$OUTPUT"

# ── optical-flow ──────────────────────────────────────────────────────────────
run_seq "optical-flow" "$FRAMES" \
    "$BINARY" track --img-dir "$FRAMES" \
                    --operation optical-flow \
                    --output "$OUTPUT/optical-flow"

# ── trajectories (video) ──────────────────────────────────────────────────────
run_vid "trajectories-video" "$VIDEO" \
    "$BINARY" track --video "$VIDEO" \
                    --operation trajectories \
                    --output "$OUTPUT"
