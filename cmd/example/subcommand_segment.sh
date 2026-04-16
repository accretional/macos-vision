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
run "foreground-mask" "$EXAMPLE_IMG_SAD_PABLO" \
    "$BINARY" segment --input "$EXAMPLE_IMG_SAD_PABLO" \
                      --operation foreground-mask \
                      --output "$OUTPUT"

# ── person-segment ────────────────────────────────────────────────────────────
run "person-segment" "$EXAMPLE_IMG_GORILLA" \
    "$BINARY" segment --input "$EXAMPLE_IMG_GORILLA" \
                      --operation person-segment \
                      --output "$OUTPUT"

# ── person-mask ───────────────────────────────────────────────────────────────
run "person-mask" "$EXAMPLE_IMG_GORILLA" \
    "$BINARY" segment --input "$EXAMPLE_IMG_GORILLA" \
                      --operation person-mask \
                      --output "$OUTPUT"

# ── attention-saliency ────────────────────────────────────────────────────────
run "attention-saliency" "$EXAMPLE_IMG_GORILLA" \
    "$BINARY" segment --input "$EXAMPLE_IMG_GORILLA" \
                      --operation attention-saliency \
                      --output "$OUTPUT"

# ── objectness-saliency ───────────────────────────────────────────────────────
run "objectness-saliency" "$EXAMPLE_IMG_GORILLA" \
    "$BINARY" segment --input "$EXAMPLE_IMG_GORILLA" \
                      --operation objectness-saliency \
                      --output "$OUTPUT"
