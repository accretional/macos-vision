#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "Building..."
swift build --package-path "$ROOT" 2>&1 | tail -1
echo

rm -rf "$ROOT/sample_data/output"
mkdir -p "$ROOT/sample_data/output"

for script in \
    "$SCRIPT_DIR/subcommand_face.sh" \
    "$SCRIPT_DIR/subcommand_classify.sh" \
    "$SCRIPT_DIR/subcommand_segment.sh" \
    "$SCRIPT_DIR/subcommand_ocr.sh" \
    "$SCRIPT_DIR/subcommand_track.sh" 
do
    subcommand="$(basename "$script" .sh | sed 's/subcommand_//')"
    echo "── $subcommand ──────────────────────────────────────────────────────────────"
    bash "$script"
    echo
done

echo "Done."
