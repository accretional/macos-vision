#!/usr/bin/env bash
# build.sh — vet and build the run_automation tool. Runs setup.sh first.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log() { printf '\033[1;34m[build]\033[0m %s\n' "$*"; }

"$ROOT/setup.sh"

log "go vet ./..."
(cd "$ROOT" && go vet ./...)

log "go build ./..."
(cd "$ROOT" && go build ./...)

log "build complete"
