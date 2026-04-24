#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}=\"{root}/{v}\"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/shazam"
mkdir -p "$OUTPUT"

run_file() {
    local label="$1" audio_file="$2"; shift 2
    if [ ! -f "$audio_file" ]; then
        echo "  SKIP  $label ($audio_file not found)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

filename_base() { basename "$1" | sed 's/\.[^.]*$//'; }

music_audio="$SHAZAM_MATCH_INPUT"
MUSIC_BASE="$(filename_base "$music_audio")"

# ── match (default operation, requires network) ───────────────────────────────
run_file "match" "$music_audio" \
    "$BINARY" shazam --input "$music_audio" \
                     --operation match \
                     --output "$OUTPUT/${MUSIC_BASE}_match.json"

# ── build (catalog from input audio directory) ────────────────────────────────
if [ -d "$AUDIO_DIR" ]; then
    echo "  RUN   build"
    "$BINARY" shazam --input "$AUDIO_DIR" \
                     --operation build \
                     --artifacts-dir "$OUTPUT" \
                     --output "$OUTPUT/audios_catalog_build.json"
else
    echo "  SKIP  build ($AUDIO_DIR not found)"
fi

# ── match-custom (against the catalog we just built) ─────────────────────────
CATALOG="$OUTPUT/audios.shazamcatalog"
if [ -f "$CATALOG" ]; then
    run_file "match-custom" "$music_audio" \
        "$BINARY" shazam --input "$music_audio" \
                          --operation match-custom \
                          --catalog "$CATALOG" \
                          --output "$OUTPUT/${MUSIC_BASE}_match_custom.json"
else
    echo "  SKIP  match-custom (catalog not found at $CATALOG)"
fi
