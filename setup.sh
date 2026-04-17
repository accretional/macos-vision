#!/usr/bin/env bash
# setup.sh — verify and install dependencies for macos-vision-test
# Idempotent: safe to run multiple times; skips anything already satisfied.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")" && pwd)"

log() { echo "[setup] $*"; }
ok()  { echo "[setup] ✓ $*"; }
err() { echo "[setup] ✗ $*" >&2; exit 1; }

# ── macOS required ────────────────────────────────────────────────────────────
if [[ "$(uname)" != "Darwin" ]]; then
  err "This project requires macOS — it uses Apple Vision, Cocoa, and AVFoundation frameworks."
fi
ok "macOS $(sw_vers -productVersion)"

# ── Xcode command-line tools ──────────────────────────────────────────────────
if ! xcode-select -p &>/dev/null 2>&1; then
  log "Xcode CLI tools not found — launching installer..."
  xcode-select --install
  err "Re-run setup.sh once Xcode CLI tools installation completes."
fi
ok "Xcode CLT: $(xcode-select -p)"

# ── Swift ─────────────────────────────────────────────────────────────────────
if ! command -v swift &>/dev/null; then
  err "swift not found. Install Xcode from the App Store or run: xcode-select --install"
fi
ok "Swift: $(swift --version 2>&1 | head -1)"

# ── jq (used by individual test.sh scripts for JSON validation) ───────────────
if ! command -v jq &>/dev/null; then
  log "jq not found — attempting install via Homebrew..."
  if command -v brew &>/dev/null; then
    brew install jq
    ok "jq installed: $(jq --version)"
  else
    err "jq is required but not found, and Homebrew is unavailable.\n  Install jq: https://stedolan.github.io/jq/download/\n  Or install Homebrew first: https://brew.sh"
  fi
else
  ok "jq: $(jq --version)"
fi

# ── Package.swift present ─────────────────────────────────────────────────────
if [[ ! -f "$ROOT/Package.swift" ]]; then
  err "Package.swift not found in $ROOT"
fi
ok "Package.swift present"

# ── Sample data / test fixtures ───────────────────────────────────────────────
if [[ ! -d "$ROOT/sample_data/input/images" ]]; then
  err "sample_data/input/images/ missing — test fixtures required for unit tests"
fi
img_count=$(find "$ROOT/sample_data/input/images" \( -name "*.jpg" -o -name "*.png" \) | wc -l | tr -d ' ')
ok "Sample images: $img_count file(s)"

if [[ ! -d "$ROOT/sample_data/input/videos" ]]; then
  log "WARNING: sample_data/input/videos/ not found — track/video tests may fail"
else
  ok "Sample videos dir present"
fi

log "Setup complete."
