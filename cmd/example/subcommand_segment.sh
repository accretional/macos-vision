#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}="{root}/{v}"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/segment"
mkdir -p "$OUTPUT"

run() {
    local label="$1" img="$2"; shift 2
    if [ ! -f "$img" ]; then
        echo "  SKIP  $label ($(basename "$img") not found)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

# ── foreground-mask ───────────────────────────────────────────────────────────
run "foreground-mask" "$SEGMENT_FOREGROUND_MASK_INPUT" \
    "$BINARY" segment --input "$SEGMENT_FOREGROUND_MASK_INPUT" \
                      --operation foreground-mask \
                      --output "$OUTPUT"

# ── person-segment ────────────────────────────────────────────────────────────
run "person-segment" "$SEGMENT_PERSON_SEGMENT_INPUT" \
    "$BINARY" segment --input "$SEGMENT_PERSON_SEGMENT_INPUT" \
                      --operation person-segment \
                      --output "$OUTPUT"

# ── person-mask ───────────────────────────────────────────────────────────────
run "person-mask" "$SEGMENT_PERSON_MASK_INPUT" \
    "$BINARY" segment --input "$SEGMENT_PERSON_MASK_INPUT" \
                      --operation person-mask \
                      --output "$OUTPUT"

# ── attention-saliency ────────────────────────────────────────────────────────
run "attention-saliency" "$SEGMENT_ATTENTION_SALIENCY_INPUT" \
    "$BINARY" segment --input "$SEGMENT_ATTENTION_SALIENCY_INPUT" \
                      --operation attention-saliency \
                      --output "$OUTPUT"

# ── objectness-saliency ───────────────────────────────────────────────────────
run "objectness-saliency" "$SEGMENT_OBJECTNESS_SALIENCY_INPUT" \
    "$BINARY" segment --input "$SEGMENT_OBJECTNESS_SALIENCY_INPUT" \
                      --operation objectness-saliency \
                      --output "$OUTPUT"
