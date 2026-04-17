#!/usr/bin/env bash
# setup.sh — bootstrap chrome-testing: verify deps, fetch chromerpc, build binary.
# Idempotent: safe to re-run. All other scripts call this first.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CHROMERPC_DIR="${CHROMERPC_DIR:-$ROOT/../chromerpc}"
CHROMERPC_REPO="${CHROMERPC_REPO:-https://github.com/accretional/chromerpc.git}"

log()  { printf '\033[1;34m[setup]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[setup]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[setup]\033[0m %s\n' "$*" >&2; exit 1; }

# ── Go ────────────────────────────────────────────────────────────────────────
if ! command -v go >/dev/null 2>&1; then
  die "go not found — install from https://go.dev/dl/ (1.21+)"
fi
GO_MINOR=$(go version | grep -oE 'go[0-9]+\.[0-9]+' | head -1 | tr -d 'go' | cut -d. -f2)
if [ "${GO_MINOR:-0}" -lt 21 ]; then
  warn "go 1.21+ recommended; found $(go version)"
fi
log "go: $(go version)"

# ── Chrome ───────────────────────────────────────────────────────────────────
# Detect Chrome binary across macOS and Linux. Exported so LET_IT_RIP.sh
# can pass it to chromerpc.
if [ -z "${CHROME_APP:-}" ]; then
  for candidate in \
    "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome" \
    "/Applications/Chromium.app/Contents/MacOS/Chromium" \
    "/usr/bin/google-chrome" \
    "/usr/bin/google-chrome-stable" \
    "/usr/bin/chromium-browser" \
    "/usr/bin/chromium"; do
    if [ -x "$candidate" ]; then
      CHROME_APP="$candidate"
      break
    fi
  done
fi
if [ -z "${CHROME_APP:-}" ]; then
  warn "Chrome not found in common locations. Set CHROME_APP=/path/to/chrome before running."
else
  log "chrome: $CHROME_APP"
fi
export CHROME_APP

# ── chromerpc source ─────────────────────────────────────────────────────────
if [ ! -d "$CHROMERPC_DIR" ]; then
  log "cloning chromerpc into $CHROMERPC_DIR"
  git clone "$CHROMERPC_REPO" "$CHROMERPC_DIR"
else
  log "chromerpc source: $CHROMERPC_DIR"
fi

# ── Build chromerpc binary ───────────────────────────────────────────────────
CHROMERPC_BIN="$CHROMERPC_DIR/bin/chromerpc"
if [ ! -x "$CHROMERPC_BIN" ] || [ "$CHROMERPC_DIR/go.mod" -nt "$CHROMERPC_BIN" ]; then
  log "building chromerpc binary"
  (cd "$CHROMERPC_DIR" && mkdir -p bin && go build -o bin/chromerpc ./cmd/chromerpc)
  log "binary: $CHROMERPC_BIN"
else
  log "chromerpc binary up-to-date: $CHROMERPC_BIN"
fi
export CHROMERPC_BIN

# ── run_automation Go module ──────────────────────────────────────────────────
TOOL_DIR="$ROOT/cmd/run_automation"
if [ ! -f "$ROOT/go.sum" ]; then
  log "resolving Go module dependencies (go get + go mod tidy)"
  (cd "$ROOT" && go get github.com/accretional/chromerpc@main && go mod tidy)
fi

# ── Screenshot output dir ────────────────────────────────────────────────────
mkdir -p "$ROOT/screenshots"

log "setup complete"
