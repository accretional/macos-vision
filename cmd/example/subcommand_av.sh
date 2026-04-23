#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}="{root}/{v}"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/av"
mkdir -p "$OUTPUT"

VID="$AV_VIDEO_INPUT"
AUD="$AV_AUDIO_INPUT"

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
AUD_BASE="$(filename_base "$AUD")"

# ── presets ───────────────────────────────────────────────────────────────────
run_file "presets" "$VID" \
    "$BINARY" av --operation presets \
                 --input "$VID" \
                 --json-output "$OUTPUT/${VID_BASE}_presets.json"

# ── probe ─────────────────────────────────────────────────────────────────────
run_file "probe" "$VID" \
    "$BINARY" av --operation probe \
                 --input "$VID" \
                 --json-output "$OUTPUT/${VID_BASE}_probe.json"

# ── tracks ────────────────────────────────────────────────────────────────────
run_file "tracks" "$VID" \
    "$BINARY" av --operation tracks \
                 --input "$VID" \
                 --json-output "$OUTPUT/${VID_BASE}_tracks.json"

# ── meta ──────────────────────────────────────────────────────────────────────
run_file "meta" "$VID" \
    "$BINARY" av --operation meta \
                 --input "$VID" \
                 --json-output "$OUTPUT/${VID_BASE}_meta.json"

# ── frames (single) ───────────────────────────────────────────────────────────
run_file "frames (single)" "$VID" \
    "$BINARY" av --operation frames \
                 --input "$VID" \
                 --time 1.0 \
                 --artifacts-dir "$OUTPUT/frames"

# ── frames (multiple) ─────────────────────────────────────────────────────────
run_file "frames (multi)" "$VID" \
    "$BINARY" av --operation frames \
                 --input "$VID" \
                 --times "0,2,5,8" \
                 --artifacts-dir "$OUTPUT/frames"

# ── encode (medium quality) ───────────────────────────────────────────────────
run_file "encode (medium)" "$VID" \
    "$BINARY" av --operation encode \
                 --input "$VID" \
                 --preset medium \
                 --output "$OUTPUT/${VID_BASE}_medium.mov"

# ── encode (audio-only) ───────────────────────────────────────────────────────
run_file "encode (audio-only)" "$VID" \
    "$BINARY" av --operation encode \
                 --input "$VID" \
                 --audio-only \
                 --output "$OUTPUT/${VID_BASE}.m4a"

# ── encode (trimmed clip) ─────────────────────────────────────────────────────
run_file "encode (trimmed)" "$VID" \
    "$BINARY" av --operation encode \
                 --input "$VID" \
                 --preset medium \
                 --time-range "0,3" \
                 --output "$OUTPUT/${VID_BASE}_trimmed.mov"

# ── concat (join two clips) ───────────────────────────────────────────────────
run_file "concat" "$VID" \
    "$BINARY" av --operation concat \
                 --videos "$VID,$VID" \
                 --preset medium \
                 --output "$OUTPUT/${VID_BASE}_concat.mov"

# ── split (at timestamps) ─────────────────────────────────────────────────────
run_file "split" "$VID" \
    "$BINARY" av --operation split \
                 --input "$VID" \
                 --times "3,6" \
                 --output "$OUTPUT/split"

# ── waveform ──────────────────────────────────────────────────────────────────
run_file "waveform" "$VID" \
    "$BINARY" av --operation waveform \
                 --input "$VID" \
                 --json-output "$OUTPUT/${VID_BASE}_waveform.json"

# ── noise ─────────────────────────────────────────────────────────────────────
run_file "noise" "$AUD" \
    "$BINARY" av --operation noise \
                 --input "$AUD" \
                 --json-output "$OUTPUT/${AUD_BASE}_noise.json"

# ── pitch ─────────────────────────────────────────────────────────────────────
run_file "pitch" "$AUD" \
    "$BINARY" av --operation pitch \
                 --input "$AUD" \
                 --json-output "$OUTPUT/${AUD_BASE}_pitch.json"

# ── stems (voice isolation) ───────────────────────────────────────────────────
run_file "stems" "$AUD" \
    "$BINARY" av --operation stems \
                 --input "$AUD" \
                 --output "$OUTPUT/${AUD_BASE}_stems.m4a"

# ── mix (overlay two audio files) ────────────────────────────────────────────
run_file "mix" "$AUD" \
    "$BINARY" av --operation mix \
                 --inputs "$AUD,$AV_MIX_INPUT_2" \
                 --output "$OUTPUT/mix_output.m4a"

# ── burn (text watermark) ────────────────────────────────────────────────────
run_file "burn (text)" "$VID" \
    "$BINARY" av --operation burn \
                 --input "$VID" \
                 --text "macos-vision" \
                 --output "$OUTPUT/${VID_BASE}_burn_text.mp4"

# ── burn (image watermark) ───────────────────────────────────────────────────
run_file "burn (image)" "$VID" \
    "$BINARY" av --operation burn \
                 --input "$VID" \
                 --overlay "$AV_BURN_OVERLAY" \
                 --output "$OUTPUT/${VID_BASE}_burn_image.mp4"

# ── retime (2x speed) ────────────────────────────────────────────────────────
run_file "retime (2x)" "$VID" \
    "$BINARY" av --operation retime \
                 --input "$VID" \
                 --factor 2.0 \
                 --output "$OUTPUT/${VID_BASE}_2x.mp4"

# ── retime (0.5x slow motion) ────────────────────────────────────────────────
run_file "retime (0.5x)" "$VID" \
    "$BINARY" av --operation retime \
                 --input "$VID" \
                 --factor 0.5 \
                 --output "$OUTPUT/${VID_BASE}_half.mp4"

# ── tts (text-to-speech) ─────────────────────────────────────────────────────
run "tts (from file)" \
    "$BINARY" av --operation tts \
                 --input "$AV_TTS_INPUT" \
                 --output "$OUTPUT/tts_joker.m4a"
