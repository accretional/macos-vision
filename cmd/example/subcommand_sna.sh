#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}=\"{root}/{v}\"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/sna"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUTPUT"

# ── generate synthetic audio long enough for the ~3 s classifier window ───────
SYNTH="$TMP/synth.aiff"
if ! say -o "$SYNTH" \
    "Testing sound analysis. The quick brown fox jumps over the lazy dog. This audio is used for sound classification." \
    2>/dev/null || [ ! -f "$SYNTH" ]; then
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

sounds_audio="$EXAMPLE_AUDIO_SOUNDS"
speech_audio="$EXAMPLE_AUDIO_SPEECH"
[ -f "$speech_audio" ] || speech_audio="$SYNTH"

SPEECH_BASE="$(filename_base "$speech_audio")"
SOUNDS_BASE="$(filename_base "$sounds_audio")"

# ── list-labels (no audio, no auth) ──────────────────────────────────────────
echo "  RUN   list-labels"
"$BINARY" sna --operation list-labels --output "$OUTPUT/list_labels.json"

# ── classify (built-in) on speech audio ──────────────────────────────────────
run_file "classify (speech)" "$speech_audio" \
    "$BINARY" sna --input "$speech_audio" \
                  --operation classify \
                  --topk 5 \
                  --output "$OUTPUT/${SPEECH_BASE}_classify.json"

# ── classify (built-in) on sounds audio ──────────────────────────────────────
run_file "classify (sounds)" "$sounds_audio" \
    "$BINARY" sna --input "$sounds_audio" \
                  --operation classify \
                  --topk 5 \
                  --output "$OUTPUT/${SOUNDS_BASE}_classify.json"

# ── classify with custom window and overlap ───────────────────────────────────
run_file "classify (window=1.5s overlap=0.25)" "$speech_audio" \
    "$BINARY" sna --input "$speech_audio" \
                  --operation classify \
                  --classify-window 1.5 \
                  --classify-overlap 0.25 \
                  --topk 3 \
                  --output "$OUTPUT/${SPEECH_BASE}_classify_windowed.json"

# ── classify with debug timing ────────────────────────────────────────────────
echo "  RUN   classify --debug (synth)"
"$BINARY" sna --input "$SYNTH" \
              --operation classify \
              --debug \
              --output "$OUTPUT/synth_classify_debug.json"
