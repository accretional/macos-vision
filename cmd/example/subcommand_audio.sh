#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}="{root}/{v}"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/audio"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUTPUT"

# ── generate synthetic fallback audio (macOS say) ─────────────────────────────
SYNTH="$TMP/synth.aiff"
if ! say -o "$SYNTH" "Example audio for classification, pitch, noise, and transcription." 2>/dev/null || [ ! -f "$SYNTH" ]; then
    echo "  SKIP  all (say could not create sample audio)"
    exit 0
fi

run() {
    local label="$1"; shift
    echo "  RUN   $label"
    "$@"
}

run_file() {
    local label="$1" audio_file="$2"; shift 2
    if [ ! -f "$audio_file" ]; then
        echo "  SKIP  $label ($audio_file not found)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

filename_base() {
    local file="$1"; shift
    basename "$file" | sed 's/\.[^.]*$//'
}

# ── resolve per-operation audio sources ───────────────────────────────────────
speech_audio="$EXAMPLE_AUDIO_SPEECH"
[ -f "$speech_audio" ] || speech_audio="$SYNTH"

music_audio="$EXAMPLE_AUDIO_MUSIC"
sounds_audio="$EXAMPLE_AUDIO_SOUNDS"

SYNTH_BASE="$(filename_base "$SYNTH")"
MUSIC_BASE="$(filename_base "$music_audio")"
SOUNDS_BASE="$(filename_base "$sounds_audio")"
SPEECH_BASE="$(filename_base "$speech_audio")"

# ── classify (default operation) ────────────────────────────────────────────
run_file "classify" "$speech_audio" \
    "$BINARY" audio --input "$speech_audio" \
                    --operation classify \
                    --output "$OUTPUT/${SPEECH_BASE}_classify.json"

# ── noise ─────────────────────────────────────────────────────────────────────
run_file "noise" "$speech_audio" \
    "$BINARY" audio --input "$speech_audio" \
                    --operation noise \
                    --output "$OUTPUT/${SPEECH_BASE}_noise.json"

# ── pitch ───────────────────────────────────────────────────────────────────
run_file "pitch" "$speech_audio" \
    "$BINARY" audio --input "$speech_audio" \
                    --operation pitch \
                    --pitch-hop 8192 \
                    --output "$OUTPUT/${SPEECH_BASE}_pitch.json"

# ── shazam ──────────────────────────────────────────────────────────────────
run_file "shazam" "$music_audio" \
    "$BINARY" audio --input "$music_audio" \
                    --operation shazam \
                    --output "$OUTPUT/${MUSIC_BASE}_shazam.json"

# ── detect ────────────────────────────────────────────────────────────────────
run_file "detect" "$sounds_audio" \
    "$BINARY" audio --input "$sounds_audio" \
                    --operation detect \
                    --output "$OUTPUT/${SOUNDS_BASE}_detect.json"

# ── isolate ───────────────────────────────────────────────────────────────────
run_file "isolate" "$speech_audio" \
    "$BINARY" audio --input "$speech_audio" \
                    --operation isolate \
                    --output "$OUTPUT/${SPEECH_BASE}_isolate.json"

# ── transcribe ────────────────────────────────────────────────────────────────
if [ -f "$speech_audio" ]; then
    echo "  RUN   transcribe"
    set +e
    "$BINARY" audio --input "$speech_audio" \
                    --operation transcribe \
                    --output "$OUTPUT/${SPEECH_BASE}_transcribe.json" 2>/dev/null
    transcribe_ec=$?
    set -e
    [ "$transcribe_ec" -eq 0 ] \
        || echo "  NOTE  transcribe: exit $transcribe_ec — grant Speech Recognition in System Settings > Privacy"
else
    echo "  SKIP  transcribe ($(basename "$speech_audio") not found)"
fi

# ── second clip (batch from shell: one input per macos-vision invocation) ─────
mkdir -p "$TMP/extra"
cp "$SYNTH" "$TMP/extra/example_clip.aiff"
EXTRA_CLIP="$TMP/extra/example_clip.aiff"
run_file "noise (extra clip)" "$EXTRA_CLIP" \
    "$BINARY" audio --input "$EXTRA_CLIP" \
                    --operation noise \
                    --output "$OUTPUT/example_clip_noise.json"
