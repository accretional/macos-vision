#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"
BINARY="$ROOT/.build/debug/macos-vision"
AUDIO_DIR="$ROOT/sample_data/input/audio"
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

# run only when a real sample file exists
run_file() {
    local label="$1" audio_file="$2"; shift 2
    if [ ! -f "$audio_file" ]; then
        echo "  SKIP  $label ($(basename "$audio_file") not found in sample_data/input/audio)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

# ── resolve per-operation audio sources ───────────────────────────────────────
# Use sample_data files when present; fall back to synthetic voice
speech_audio="${AUDIO_DIR}/kazoo_kid_who_are_you.wav"
[ -f "$speech_audio" ] || speech_audio="$SYNTH"

tone_audio="${AUDIO_DIR}/tone.aiff"
[ -f "$tone_audio" ] || tone_audio="$SYNTH"

music_audio="${AUDIO_DIR}/music.m4a"    # preferred for shazam (needs a real song)
sounds_audio="${AUDIO_DIR}/sounds.wav"  # preferred for detect (event sounds)

# ── classify (default operation) ────────────────────────────────────────────
run_file "classify" "$SYNTH" \
    "$BINARY" audio --audio "$SYNTH" \
                    --operation classify \
                    --output "$OUTPUT/example_classify.json"

# ── noise ─────────────────────────────────────────────────────────────────────
run_file "noise" "$SYNTH" \
    "$BINARY" audio --audio "$SYNTH" \
                    --operation noise \
                    --output "$OUTPUT/example_noise.json"

# ── pitch ───────────────────────────────────────────────────────────────────
run_file "pitch" "$tone_audio" \
    "$BINARY" audio --audio "$tone_audio" \
                    --operation pitch \
                    --output "$OUTPUT/example_pitch.json"

# ── shazam ──────────────────────────────────────────────────────────────────
# Requires a real music file; synth voice cannot produce a Shazam match
run_file "shazam" "$music_audio" \
    "$BINARY" audio --audio "$music_audio" \
                    --operation shazam \
                    --output "$OUTPUT/example_shazam.json"

# ── detect ────────────────────────────────────────────────────────────────────
# Filters for: alarm, siren, dog, cat, baby, crying, scream, glass.
# Requires sounds.wav with real event audio; synth voice yields empty results.
run_file "detect" "$sounds_audio" \
    "$BINARY" audio --audio "$sounds_audio" \
                    --operation detect \
                    --output "$OUTPUT/example_detect.json"

# ── isolate ───────────────────────────────────────────────────────────────────
run_file "isolate" "$speech_audio" \
    "$BINARY" audio --audio "$speech_audio" \
                    --operation isolate \
                    --output "$OUTPUT/example_isolate.json"

# ── transcribe ────────────────────────────────────────────────────────────────
# Requires Speech Recognition permission; falls back gracefully if not granted.
if [ -f "$speech_audio" ]; then
    echo "  RUN   transcribe"
    set +e
    "$BINARY" audio --audio "$speech_audio" \
                    --operation transcribe \
                    --output "$OUTPUT/example_transcribe.json" 2>/dev/null
    transcribe_ec=$?
    set -e
    [ "$transcribe_ec" -eq 0 ] \
        || echo "  NOTE  transcribe: exit $transcribe_ec — grant Speech Recognition in System Settings > Privacy"
else
    echo "  SKIP  transcribe ($(basename "$speech_audio") not found)"
fi

# ── shazam-build ─────────────────────────────────────────────────────────────
# shazam-build expects --audio pointing at a directory of reference tracks.
# Uses sample_data/input/audio/catalog/ when it exists; otherwise a temp dir.
# Writes a .shazamcatalog file next to the --output JSON (same base name).
catalog_dir="${AUDIO_DIR}/catalog"
if [ ! -d "$catalog_dir" ]; then
    catalog_dir="$TMP/catalog"
    mkdir -p "$catalog_dir"
    cp "$SYNTH" "$catalog_dir/reference.aiff"
fi
run "shazam-build" \
    "$BINARY" audio --audio "$catalog_dir" \
                    --operation shazam-build \
                    --output "$OUTPUT/example_shazam_build.json"

# ── shazam-custom ─────────────────────────────────────────────────────────────
# If shazam-build wrote a catalog, use it; otherwise falls back to default Shazam.
built_catalog="$OUTPUT/example_shazam_build.shazamcatalog"
if [ -f "$SYNTH" ]; then
    if [ -f "$built_catalog" ]; then
        run "shazam-custom (with catalog)" \
            "$BINARY" audio --audio "$SYNTH" \
                            --operation shazam-custom \
                            --catalog "$built_catalog" \
                            --output "$OUTPUT/example_shazam_custom.json"
    else
        run "shazam-custom (no catalog)" \
            "$BINARY" audio --audio "$SYNTH" \
                            --operation shazam-custom \
                            --output "$OUTPUT/example_shazam_custom.json"
    fi
else
    echo "  SKIP  shazam-custom (music.m4a not found in sample_data/input/audio)"
fi

# ── batch + merge ─────────────────────────────────────────────────────────────
run "batch noise --merge" \
    bash -c "mkdir -p '$TMP/batch' && cp '$SYNTH' '$TMP/batch/clip.aiff' && \
             '$BINARY' audio --audio-dir '$TMP/batch' --operation noise \
                             --output-dir '$OUTPUT/batch' --merge \
                             --output '$OUTPUT/example_batch_noise_merged.json'"
