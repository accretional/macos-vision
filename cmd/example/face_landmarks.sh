#!/usr/bin/env bash
set -euo pipefail

usage() {
    echo "Usage: $0 [IMAGE]"
    echo "  IMAGE  Path to an image (default: data/images/fred-yass.png under repo root)"
    exit "${1:-0}"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    usage 0
fi

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"

DEFAULT_IMAGE="$ROOT/data/images/fred-yass.png"
IMAGE="${1:-$DEFAULT_IMAGE}"
OUTPUT="$SCRIPT_DIR/output"

if [[ ! -f "$IMAGE" ]]; then
    echo "error: image not found: $IMAGE" >&2
    usage 1
fi

IMAGE_BASENAME="$(basename "$IMAGE")"
STEM="${IMAGE_BASENAME%.*}"
JSON="$OUTPUT/${STEM}_face_landmarks.json"

# Build if needed
if [ ! -f "$BINARY" ]; then
    echo "Building..."
    swift build --package-path "$ROOT"
fi

mkdir -p "$OUTPUT"

echo "Running face landmarks on $(basename "$IMAGE")..."
"$BINARY" face \
    --img       "$IMAGE" \
    --output    "$OUTPUT" \
    --operation face-landmarks

echo
echo "Generating SVG overlay..."
"$BINARY" svg \
    --json   "$JSON" \
    --img    "$IMAGE" \
    --output "$OUTPUT"
