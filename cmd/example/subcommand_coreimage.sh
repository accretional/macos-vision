#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}=\"{root}/{v}\"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/coreimage"
mkdir -p "$OUTPUT"

run_img() {
    local label="$1" img="$2"; shift 2
    if [ ! -f "$img" ]; then
        echo "  SKIP  $label ($img not found)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

# ── list-filters ──────────────────────────────────────────────────────────────
echo "  RUN   list-filters"
"$BINARY" coreimage --operation list-filters \
          --output "$OUTPUT/list_filters.json"

echo "  RUN   list-filters --category-only"
"$BINARY" coreimage --operation list-filters --category-only \
          --output "$OUTPUT/list_categories.json"

# ── auto-adjust ───────────────────────────────────────────────────────────────
run_img "auto-adjust" "$COREIMAGE_AUTO_ADJUST_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_AUTO_ADJUST_INPUT" \
              --operation auto-adjust \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/gorilla_auto_adjust.json"

run_img "auto-adjust --format jpg" "$COREIMAGE_AUTO_ADJUST_RACCOON_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_AUTO_ADJUST_RACCOON_INPUT" \
              --operation auto-adjust \
              --format jpg \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/raccoon_auto_adjust.json"

# ── apply-filter: color effects ───────────────────────────────────────────────
run_img "CISepiaTone" "$COREIMAGE_APPLY_FILTER_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_APPLY_FILTER_INPUT" \
              --operation apply-filter --filter-name CISepiaTone \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/gorilla_sepia.json"

run_img "CISepiaTone (intensity=0.8)" "$COREIMAGE_APPLY_FILTER_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_APPLY_FILTER_INPUT" \
              --operation apply-filter --filter-name CISepiaTone \
              --filter-params '{"inputIntensity": 0.4}' \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/gorilla_sepia_light.json"

run_img "CIPhotoEffectNoir" "$COREIMAGE_APPLY_FILTER_RACCOON_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_APPLY_FILTER_RACCOON_INPUT" \
              --operation apply-filter --filter-name CIPhotoEffectNoir \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/raccoon_noir.json"

run_img "CIVignette" "$COREIMAGE_APPLY_FILTER_SPIDERMAN_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_APPLY_FILTER_SPIDERMAN_INPUT" \
              --operation apply-filter --filter-name CIVignette \
              --filter-params '{"inputIntensity": 1.5, "inputRadius": 2.0}' \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/spiderman_vignette.json"

# ── apply-filter: blur ────────────────────────────────────────────────────────
run_img "CIGaussianBlur" "$COREIMAGE_APPLY_FILTER_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_APPLY_FILTER_INPUT" \
              --operation apply-filter --filter-name CIGaussianBlur \
              --filter-params '{"inputRadius": 10}' \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/gorilla_blur.json"

# ── apply-filter: color adjustment ───────────────────────────────────────────
run_img "CIExposureAdjust" "$COREIMAGE_APPLY_FILTER_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_APPLY_FILTER_INPUT" \
              --operation apply-filter --filter-name CIExposureAdjust \
              --filter-params '{"inputEV": 1.5}' \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/gorilla_exposure.json"

run_img "CIColorControls (saturation boost)" "$COREIMAGE_APPLY_FILTER_RACCOON_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_APPLY_FILTER_RACCOON_INPUT" \
              --operation apply-filter --filter-name CIColorControls \
              --filter-params '{"inputSaturation": 2.0, "inputBrightness": 0.1, "inputContrast": 1.1}' \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/raccoon_colorcontrols.json"

# ── apply-filter: stylize ─────────────────────────────────────────────────────
run_img "CIPixellate" "$COREIMAGE_APPLY_FILTER_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_APPLY_FILTER_INPUT" \
              --operation apply-filter --filter-name CIPixellate \
              --filter-params '{"inputScale": 12}' \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/gorilla_pixellate.json"

run_img "CIColorInvert" "$COREIMAGE_APPLY_FILTER_SADPABLO_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_APPLY_FILTER_SADPABLO_INPUT" \
              --operation apply-filter --filter-name CIColorInvert \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/sadpablo_invert.json"

# ── apply-filter: alternate formats ──────────────────────────────────────────
run_img "CISepiaTone --format jpg" "$COREIMAGE_APPLY_FILTER_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_APPLY_FILTER_INPUT" \
              --operation apply-filter --filter-name CISepiaTone \
              --format jpg \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/gorilla_sepia_jpg.json"

run_img "CIGaussianBlur --format heif" "$COREIMAGE_APPLY_FILTER_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_APPLY_FILTER_INPUT" \
              --operation apply-filter --filter-name CIGaussianBlur \
              --filter-params '{"inputRadius": 10}' \
              --format heif \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/gorilla_blur_heif.json"

# ── apply-filter with --debug ─────────────────────────────────────────────────
run_img "CIUnsharpMask --debug" "$COREIMAGE_APPLY_FILTER_INPUT" \
    "$BINARY" coreimage --input "$COREIMAGE_APPLY_FILTER_INPUT" \
              --operation apply-filter --filter-name CIUnsharpMask \
              --filter-params '{"inputRadius": 2.5, "inputIntensity": 0.5}' \
              --debug \
              --artifacts-dir "$OUTPUT" \
              --json-output "$OUTPUT/gorilla_sharpen_debug.json"
