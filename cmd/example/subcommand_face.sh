#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}="{root}/{v}"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/face"
mkdir -p "$OUTPUT"

# Write <stem>_<operation>.svg next to the JSON from `face --output "$OUTPUT"`.
overlay_face() {
    local img="$1" operation="$2"
    local stem op json
    stem=$(basename "$img"); stem="${stem%.*}"
    op="${operation//-/_}"
    json="$OUTPUT/${stem}_${op}.json"
    if [ ! -f "$json" ]; then
        echo "  SKIP  overlay (source json not found)"
        return
    fi
    if [ ! -f "$img" ]; then
        echo "  SKIP  overlay (source image missing)"
        return
    fi
    echo "  RUN   overlay ${stem}_${op}.svg"
    "$BINARY" overlay --json "$json" --input "$img" --output "$OUTPUT"
}

run() {
    local label="$1" img="$2"; shift 2
    if [ ! -f "$img" ]; then
        echo "  SKIP  $label ($(basename "$img") not found)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

# ── face-rectangles ───────────────────────────────────────────────────────────
run "face-rectangles" "$FACE_FACE_RECTANGLES_INPUT" \
    "$BINARY" face --input "$FACE_FACE_RECTANGLES_INPUT" \
                   --operation face-rectangles \
                   --output "$OUTPUT"
overlay_face "$FACE_FACE_RECTANGLES_INPUT" face-rectangles

# ── face-landmarks ────────────────────────────────────────────────────────────
run "face-landmarks" "$FACE_FACE_LANDMARKS_INPUT" \
    "$BINARY" face --input "$FACE_FACE_LANDMARKS_INPUT" \
                   --operation face-landmarks \
                   --output "$OUTPUT"
overlay_face "$FACE_FACE_LANDMARKS_INPUT" face-landmarks

# ── face-quality ──────────────────────────────────────────────────────────────
run "face-quality" "$FACE_FACE_QUALITY_INPUT" \
    "$BINARY" face --input "$FACE_FACE_QUALITY_INPUT" \
                   --operation face-quality \
                   --output "$OUTPUT"
overlay_face "$FACE_FACE_QUALITY_INPUT" face-quality

# ── human-rectangles ──────────────────────────────────────────────────────────
run "human-rectangles" "$FACE_HUMAN_RECTANGLES_INPUT" \
    "$BINARY" face --input "$FACE_HUMAN_RECTANGLES_INPUT" \
                   --operation human-rectangles \
                   --output "$OUTPUT"
overlay_face "$FACE_HUMAN_RECTANGLES_INPUT" human-rectangles

# ── body-pose ─────────────────────────────────────────────────────────────────
run "body-pose" "$FACE_BODY_POSE_INPUT" \
    "$BINARY" face --input "$FACE_BODY_POSE_INPUT" \
                   --operation body-pose \
                   --output "$OUTPUT"
overlay_face "$FACE_BODY_POSE_INPUT" body-pose

# ── hand-pose ─────────────────────────────────────────────────────────────────
run "hand-pose" "$FACE_HAND_POSE_INPUT" \
    "$BINARY" face --input "$FACE_HAND_POSE_INPUT" \
                   --operation hand-pose \
                   --output "$OUTPUT"
overlay_face "$FACE_HAND_POSE_INPUT" hand-pose

# ── animal-pose (cat_side_eye → cat_side_eye_animal_pose.json for field journal)
run "animal-pose" "$FACE_ANIMAL_POSE_INPUT" \
    "$BINARY" face --input "$FACE_ANIMAL_POSE_INPUT" \
                   --operation animal-pose \
                   --output "$OUTPUT"
overlay_face "$FACE_ANIMAL_POSE_INPUT" animal-pose
