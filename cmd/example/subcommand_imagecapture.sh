#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}=\"{root}/{v}\"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/imagecapture"
mkdir -p "$OUTPUT"

# ── list-devices ──────────────────────────────────────────────────────────────
# Discovers all cameras and scanners via ICDeviceBrowser (local USB/FireWire,
# Bluetooth, and network/Bonjour). Returns an empty list if none are connected.

echo "  RUN   list-devices"
"$BINARY" imagecapture --operation list-devices \
          --output "$OUTPUT/devices.json"

echo "  RUN   list-devices --debug (with timing)"
"$BINARY" imagecapture --operation list-devices --debug \
          --output "$OUTPUT/devices_debug.json"

# ── camera operations ─────────────────────────────────────────────────────────
# All camera/* operations require a physical camera connected via USB,
# FireWire, or network. They are skipped when no camera is present.

CAM_COUNT=$(jq -r '.result.camera_count // 0' "$OUTPUT/devices.json" 2>/dev/null || echo 0)

if [ "$CAM_COUNT" -gt 0 ]; then
    echo "  RUN   camera/files (device 0)"
    "$BINARY" imagecapture --operation camera/files \
              --output "$OUTPUT/camera_files.json"

    echo "  RUN   camera/thumbnail --file-index 0 (device 0)"
    "$BINARY" imagecapture --operation camera/thumbnail \
              --file-index 0 \
              --output "$OUTPUT/thumb_0.jpg"

    echo "  RUN   camera/metadata --file-index 0 (device 0)"
    "$BINARY" imagecapture --operation camera/metadata \
              --file-index 0 \
              --output "$OUTPUT/metadata_0.json"

    echo "  RUN   camera/sync-clock (device 0)"
    "$BINARY" imagecapture --operation camera/sync-clock \
              --output "$OUTPUT/clock_sync.json"

    # camera/import — downloads file 0 to a local directory
    mkdir -p "$OUTPUT/imports"
    echo "  RUN   camera/import --file-index 0 (device 0)"
    "$BINARY" imagecapture --operation camera/import \
              --file-index 0 \
              --output "$OUTPUT/imports"

    # camera/capture — fires the shutter and reports the new file's metadata.
    # Only works on cameras with ICCameraDeviceCanTakePicture capability
    # (most DSLRs/mirrorless via USB data cable).
    echo "  RUN   camera/capture (device 0) — may error if camera lacks tether capability"
    "$BINARY" imagecapture --operation camera/capture \
              --output "$OUTPUT/capture.json" 2>/dev/null || true
else
    echo "  SKIP  camera/* — no camera devices found (connect a camera and rerun)"
fi

# ── scanner operations ────────────────────────────────────────────────────────
# scanner/* operations require a physical scanner connected via USB or network.

SCN_COUNT=$(jq -r '.result.scanner_count // 0' "$OUTPUT/devices.json" 2>/dev/null || echo 0)

if [ "$SCN_COUNT" -gt 0 ]; then
    mkdir -p "$OUTPUT/scans"

    echo "  RUN   scanner/preview (device 0)"
    "$BINARY" imagecapture --operation scanner/preview \
              --output "$OUTPUT/scans"

    echo "  RUN   scanner/scan --dpi 300 --format tiff (device 0)"
    "$BINARY" imagecapture --operation scanner/scan \
              --dpi 300 --format tiff \
              --output "$OUTPUT/scans"
else
    echo "  SKIP  scanner/* — no scanner devices found (connect a scanner and rerun)"
fi
