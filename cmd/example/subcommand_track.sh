#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"; export ROOT
eval "$(python3 -c "import json,sys;root,f=sys.argv[1],sys.argv[2];[print(f'export {k}="{root}/{v}"') for k,v in json.load(open(f)).items()]" "$ROOT" "$SCRIPT_DIR/data_files.json")"

OUTPUT="$ROOT/sample_data/output/track"
mkdir -p "$OUTPUT"

run_seq() {
    local label="$1" dir="$2"; shift 2
    if [ ! -d "$dir" ] || [ -z "$(ls "$dir"/*.jpg "$dir"/*.png 2>/dev/null)" ]; then
        echo "  SKIP  $label ($(basename "$dir")/ not found or empty)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

run_vid() {
    local label="$1" vid="$2"; shift 2
    if [ ! -f "$vid" ]; then
        echo "  SKIP  $label ($(basename "$vid") not found)"
        return
    fi
    echo "  RUN   $label"
    "$@"
}

# ── homographic ───────────────────────────────────────────────────────────────
run_seq "homographic" "$TRACK_HOMOGRAPHIC_DIR" \
    "$BINARY" track --input "$TRACK_HOMOGRAPHIC_DIR" \
                    --operation homographic \
                    --output "$OUTPUT"

# ── translational ─────────────────────────────────────────────────────────────
run_seq "translational" "$TRACK_TRANSLATIONAL_DIR" \
    "$BINARY" track --input "$TRACK_TRANSLATIONAL_DIR" \
                    --operation translational \
                    --output "$OUTPUT"

# ── optical-flow ──────────────────────────────────────────────────────────────
run_seq "optical-flow" "$TRACK_OPTICAL_FLOW_DIR" \
    "$BINARY" track --input "$TRACK_OPTICAL_FLOW_DIR" \
                    --operation optical-flow \
                    --artifacts-dir "$OUTPUT/optical-flow" \
                    --output "$OUTPUT"

# ── trajectories (video) ──────────────────────────────────────────────────────
run_vid "trajectories-video" "$TRACK_TRAJECTORIES_INPUT" \
    "$BINARY" track --input "$TRACK_TRAJECTORIES_INPUT" \
                    --operation trajectories \
                    --output "$OUTPUT"

# ── browser-friendly trajectory preview (full JSON can be tens of MB) ─────────
if [ -f "$OUTPUT/track_trajectories.json" ]; then
    python3 - "$OUTPUT/track_trajectories.json" "$OUTPUT/track_trajectories_preview.json" <<'PY'
import json, sys
src, dst = sys.argv[1], sys.argv[2]
with open(src) as f:
    doc = json.load(f)
inner = doc.get("result") if isinstance(doc.get("result"), dict) else doc
tr = inner.get("trajectories") or []
inner["trajectories"] = tr[:25]
with open(dst, "w") as o:
    json.dump(inner, o)
PY
fi
