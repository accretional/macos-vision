#!/usr/bin/env bash
# Build macos-vision if needed, then launch live hand-gesture control.
# Any extra args are forwarded to gesture.py (e.g. ./run.sh --dry-run).
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

BINARY="$ROOT/.build/debug/macos-vision"
if [ ! -x "$BINARY" ]; then
    echo "Building macos-vision..."
    swift build --package-path "$ROOT"
    codesign --force --sign - --entitlements "$ROOT/macos-vision.entitlements" "$BINARY" || true
fi

exec python3 "$SCRIPT_DIR/gesture.py" --binary "$BINARY" "$@"
