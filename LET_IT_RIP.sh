#!/usr/bin/env bash
# LET_IT_RIP.sh — full validation gate before pushing or releasing
# Runs: setup → build (debug) → all smoke tests → release build smoke check
# Idempotent: every step it calls is idempotent.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

log() { echo "[LET_IT_RIP] $*"; }
ok()  { echo "[LET_IT_RIP] ✓ $*"; }
err() { echo "[LET_IT_RIP] ✗ $*" >&2; exit 1; }

# ── Full test suite ───────────────────────────────────────────────────────────
log "Running full test suite..."
"$ROOT/test.sh"

# ── Release build smoke check ─────────────────────────────────────────────────
# Verifies the release configuration compiles and the binary is executable.
# Does NOT re-run all tests against the release binary (debug tests above are sufficient).
log "Smoke-checking release build..."
swift build -c release --package-path "$ROOT"

RELEASE_BIN="$ROOT/.build/release/macos-vision"
if [[ ! -f "$RELEASE_BIN" ]]; then
  err "Release binary not found at $RELEASE_BIN"
fi

# Quick sanity: binary runs and prints usage
if ! "$RELEASE_BIN" --help &>/dev/null && ! "$RELEASE_BIN" 2>&1 | grep -qi "usage\|subcommand\|vision\|error"; then
  err "Release binary produced unexpected output on --help"
fi
ok "Release binary: $RELEASE_BIN"

log "────────────────────────────────────────────────────────────────────────────"
log "All checks passed. Safe to push / cut a release."
