#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
VIDEO_DIR="$ROOT/sample_data/input/videos"
OUTPUT="$ROOT/sample_data/output/av"

mkdir -p "$OUTPUT"

VID="$VIDEO_DIR/kazoo_kid_who_are_you.mp4"

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
                 --video "$VID" \
                 --output "$OUTPUT/${VID_BASE}_list_presets.json"

# ── inspect ───────────────────────────────────────────────────────────────────
run_file "inspect" "$VID" \
    "$BINARY" av --operation inspect \
                 --video "$VID" \
                 --output "$OUTPUT/${VID_BASE}_inspect.json"

# ── tracks ────────────────────────────────────────────────────────────────────
run_file "tracks" "$VID" \
    "$BINARY" av --operation tracks \
                 --video "$VID" \
                 --output "$OUTPUT/${VID_BASE}_tracks.json"

# ── metadata ──────────────────────────────────────────────────────────────────
run_file "metadata" "$VID" \
    "$BINARY" av --operation metadata \
                 --video "$VID" \
                 --output "$OUTPUT/${VID_BASE}_metadata.json"

# ── thumbnail (single frame) ──────────────────────────────────────────────────
run_file "thumbnail (single)" "$VID" \
    "$BINARY" av --operation thumbnail \
                 --video "$VID" \
                 --time 1.0 \
                 --output-dir "$OUTPUT/thumbnails"

# ── thumbnail (multiple frames) ───────────────────────────────────────────────
run_file "thumbnail (multi)" "$VID" \
    "$BINARY" av --operation thumbnail \
                 --video "$VID" \
                 --times "0,2,5,8" \
                 --output-dir "$OUTPUT/thumbnails"

# ── export (medium quality) ───────────────────────────────────────────────────
run_file "export (medium)" "$VID" \
    "$BINARY" av --operation export \
                 --video "$VID" \
                 --preset medium \
                 --output "$OUTPUT/${VID_BASE}_medium.mov"

# ── export-audio (m4a) ────────────────────────────────────────────────────────
run_file "export-audio" "$VID" \
    "$BINARY" av --operation export-audio \
                 --video "$VID" \
                 --output "$OUTPUT/${VID_BASE}.m4a"

# ── export (trimmed clip) ─────────────────────────────────────────────────────
run_file "export (trimmed)" "$VID" \
    "$BINARY" av --operation export \
                 --video "$VID" \
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
                 --video "$VID" \
                 --output "$OUTPUT/${VID_BASE}_waveform.json"

# ── tts (text-to-speech) ──────────────────────────────────────────────────────
run "tts (inline)" \
    "$BINARY" av --operation tts \
                 --text "The quick brown fox jumps over the lazy dog." \
                 --output "$OUTPUT/tts_inline.caf"

run "tts (from file)" \
    "$BINARY" av --operation tts \
                 --input "$ROOT/sample_data/input/text/joker.txt" \
                 --output "$OUTPUT/tts_joker.caf"
