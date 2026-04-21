#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}=\"{root}/{v}\"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

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
    "$SCRIPT_DIR/subcommand_track.sh" \
    "$SCRIPT_DIR/subcommand_nl.sh" \
    "$SCRIPT_DIR/subcommand_av.sh" \
    "$SCRIPT_DIR/subcommand_coreimage.sh" \
    "$SCRIPT_DIR/subcommand_imagecapture.sh" \
    "$SCRIPT_DIR/subcommand_sna.sh" \
    "$SCRIPT_DIR/subcommand_speech.sh" \
    "$SCRIPT_DIR/subcommand_shazam.sh" 
do
    subcommand="$(basename "$script" .sh | sed 's/subcommand_//')"
    echo "── $subcommand ──────────────────────────────────────────────────────────────"
    bash "$script"
    echo
done

echo "Done."
