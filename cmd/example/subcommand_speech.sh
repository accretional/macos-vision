#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}=\"{root}/{v}\"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/speech"
TMP="$(mktemp -d)"; trap 'rm -rf "$TMP"' EXIT

mkdir -p "$OUTPUT"

# ── generate synthetic fallback audio (macOS say) ─────────────────────────────
SYNTH="$TMP/synth.aiff"
if ! say -o "$SYNTH" "The quick brown fox jumps over the lazy dog. Speech recognition converts spoken words into text." 2>/dev/null || [ ! -f "$SYNTH" ]; then
    echo "  SKIP  all (say could not create sample audio)"
    exit 0
fi

speech_audio="$EXAMPLE_AUDIO_SPEECH"
[ -f "$speech_audio" ] || speech_audio="$SYNTH"

filename_base() { basename "$1" | sed 's/\.[^.]*$//'; }
SPEECH_BASE="$(filename_base "$speech_audio")"

# ── list-locales (no auth required) ──────────────────────────────────────────
echo "  RUN   list-locales"
"$BINARY" speech --operation list-locales --output "$OUTPUT/list_locales.json"

# ── transcribe ────────────────────────────────────────────────────────────────
echo "  RUN   transcribe"
set +e
"$BINARY" speech --input "$speech_audio" \
                 --operation transcribe \
                 --output "$OUTPUT/${SPEECH_BASE}_transcribe.json" 2>/dev/null
transcribe_ec=$?
set -e
[ "$transcribe_ec" -eq 0 ] \
    || echo "  NOTE  transcribe: exit $transcribe_ec — grant Speech Recognition in System Settings > Privacy & Security"

# ── voice-analytics ───────────────────────────────────────────────────────────
echo "  RUN   voice-analytics"
set +e
"$BINARY" speech --input "$speech_audio" \
                 --operation voice-analytics \
                 --output "$OUTPUT/${SPEECH_BASE}_voice_analytics.json" 2>/dev/null
va_ec=$?
set -e
[ "$va_ec" -eq 0 ] \
    || echo "  NOTE  voice-analytics: exit $va_ec — requires Speech Recognition permission and on-device recognition support"

# ── transcribe with debug timing ──────────────────────────────────────────────
echo "  RUN   transcribe --debug"
set +e
"$BINARY" speech --input "$SYNTH" \
                 --operation transcribe \
                 --debug \
                 --output "$OUTPUT/synth_transcribe_debug.json" 2>/dev/null
set -e
