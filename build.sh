#!/usr/bin/env bash
# build.sh — build macos-vision debug binary (calls setup.sh first)
# Idempotent: setup.sh is idempotent; swift build skips unchanged targets.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

log() { echo "[build] $*"; }
ok()  { echo "[build] ✓ $*"; }
err() { echo "[build] ✗ $*" >&2; exit 1; }

# ── Dependencies ──────────────────────────────────────────────────────────────
log "Checking setup..."
"$ROOT/setup.sh"

# ── Compile ───────────────────────────────────────────────────────────────────
log "Building (debug)..."
swift build --package-path "$ROOT"

BINARY="$ROOT/.build/debug/macos-vision"
if [[ ! -f "$BINARY" ]]; then
  err "Build finished but binary not found at $BINARY"
fi
ok "Binary: $BINARY"

log "Build complete."
