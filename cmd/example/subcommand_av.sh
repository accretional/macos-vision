#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}="{root}/{v}"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/av"
mkdir -p "$OUTPUT"

VID="$AV_LIST_PRESETS_INPUT"

run() {
    local label="$1"; shift
    echo "  RUN   $label"
    "$@"
}

run_file() {
    local label="$1" file="$2"; shift 2
    if [ ! -f "$file" ]; then
        echo "  SKIP  $label ($(basename "$file") not found)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

filename_base() {
    local file="$1"; shift
    basename "$file" | sed 's/\.[^.]*$//'
}

VID_BASE="$(filename_base "$VID")"

# ── list-presets ──────────────────────────────────────────────────────────────
run_file "list-presets" "$VID" \
    "$BINARY" av --operation list-presets \
                 --input "$VID" \
                 --output "$OUTPUT/${VID_BASE}_list_presets.json"

# ── inspect ───────────────────────────────────────────────────────────────────
run_file "inspect" "$VID" \
    "$BINARY" av --operation inspect \
                 --input "$VID" \
                 --output "$OUTPUT/${VID_BASE}_inspect.json"

# ── tracks ────────────────────────────────────────────────────────────────────
run_file "tracks" "$VID" \
    "$BINARY" av --operation tracks \
                 --input "$VID" \
                 --output "$OUTPUT/${VID_BASE}_tracks.json"

# ── metadata ──────────────────────────────────────────────────────────────────
run_file "metadata" "$VID" \
    "$BINARY" av --operation metadata \
                 --input "$VID" \
                 --output "$OUTPUT/${VID_BASE}_metadata.json"

# ── thumbnail (single frame) ──────────────────────────────────────────────────
run_file "thumbnail (single)" "$VID" \
    "$BINARY" av --operation thumbnail \
                 --input "$VID" \
                 --time 1.0 \
                 --artifacts-dir "$OUTPUT/thumbnails"

# ── thumbnail (multiple frames) ───────────────────────────────────────────────
run_file "thumbnail (multi)" "$VID" \
    "$BINARY" av --operation thumbnail \
                 --input "$VID" \
                 --times "0,2,5,8" \
                 --artifacts-dir "$OUTPUT/thumbnails"

# ── export (medium quality) ───────────────────────────────────────────────────
run_file "export (medium)" "$VID" \
    "$BINARY" av --operation export \
                 --input "$VID" \
                 --preset medium \
                 --output "$OUTPUT/${VID_BASE}_medium.mov"

# ── export-audio (m4a) ────────────────────────────────────────────────────────
run_file "export-audio" "$VID" \
    "$BINARY" av --operation export-audio \
                 --input "$VID" \
                 --output "$OUTPUT/${VID_BASE}.m4a"

# ── export (trimmed clip) ─────────────────────────────────────────────────────
run_file "export (trimmed)" "$VID" \
    "$BINARY" av --operation export \
                 --input "$VID" \
                 --preset medium \
                 --time-range "0, 3" \
                 --output "$OUTPUT/${VID_BASE}_trimmed.mov"

# ── compose (concatenate two clips) ──────────────────────────────────────────
run_file "compose" "$VID" \
    "$BINARY" av --operation compose \
                 --videos "$VID,$VID" \
                 --preset medium \
                 --output "$OUTPUT/${VID_BASE}_composed.mov"

# ── waveform ──────────────────────────────────────────────────────────────────
run_file "waveform" "$VID" \
    "$BINARY" av --operation waveform \
                 --input "$VID" \
                 --output "$OUTPUT/${VID_BASE}_waveform.json"

# ── tts (text-to-speech) ──────────────────────────────────────────────────────

run "tts (from file)" \
    "$BINARY" av --operation tts \
                 --input "$AV_TTS_INPUT" \
                 --output "$OUTPUT/tts_joker.m4a"
