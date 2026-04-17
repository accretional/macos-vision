#!/usr/bin/env bash
# test.sh — build then run the full test suite (calls build.sh first)
# Idempotent: build.sh (and setup.sh) are called and skip already-done work.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

log() { echo "[test] $*"; }
ok()  { echo "[test] ✓ $*"; }
err() { echo "[test] ✗ $*" >&2; exit 1; }

# ── Build ─────────────────────────────────────────────────────────────────────
log "Building..."
"$ROOT/build.sh"

# ── Smoke tests ───────────────────────────────────────────────────────────────
log "Running smoke tests..."
# SKIP_BUILD=1: build.sh above already compiled; skip redundant swift build inside smoke-test.sh
SKIP_BUILD=1 "$ROOT/tests/smoke-test.sh"

ok "All tests passed."
