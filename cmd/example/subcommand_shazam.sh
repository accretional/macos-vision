#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}=\"{root}/{v}\"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/shazam"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUTPUT"

SYNTH="$TMP/synth.aiff"
if ! say -o "$SYNTH" "Example audio for Shazam catalog building." 2>/dev/null || [ ! -f "$SYNTH" ]; then
    echo "  SKIP  all (say could not create sample audio)"
    exit 0
fi

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

music_audio="$EXAMPLE_AUDIO_MUSIC"
MUSIC_BASE="$(filename_base "$music_audio")"

# ── match (default operation, requires network) ───────────────────────────────
run_file "match" "$music_audio" \
    "$BINARY" shazam --input "$music_audio" \
                     --operation match \
                     --output "$OUTPUT/${MUSIC_BASE}_match.json"

# ── build (catalog from a directory of audio files) ───────────────────────────
echo "  RUN   build"
AUDIO_DIR="$TMP/songs"
mkdir -p "$AUDIO_DIR"
cp "$SYNTH" "$AUDIO_DIR/track1.aiff"
say -o "$AUDIO_DIR/track2.aiff" "Second track for catalog." 2>/dev/null || true

"$BINARY" shazam --input "$AUDIO_DIR" \
                  --operation build \
                  --artifacts-dir "$OUTPUT" \
                  --output "$OUTPUT/catalog_build.json"

# ── match-custom (against the catalog we just built) ─────────────────────────
CATALOG="$OUTPUT/songs.shazamcatalog"
if [ -f "$CATALOG" ]; then
    run_file "match-custom" "$SYNTH" \
        "$BINARY" shazam --input "$SYNTH" \
                          --operation match-custom \
                          --catalog "$CATALOG" \
                          --output "$OUTPUT/synth_match_custom.json"
else
    echo "  SKIP  match-custom (catalog not found at $CATALOG)"
fi
