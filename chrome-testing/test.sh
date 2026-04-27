#!/usr/bin/env bash
# test.sh — build + run Go unit tests + smoke-test automation against a live
# chromerpc server. Runs build.sh first (idempotent).
#
# If CHROMERPC_ADDR is set and a server is already listening there, the
# smoke automation runs against it. Otherwise, this script launches a
# temporary server, runs the smoke test, then shuts it down.

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

log()  { printf '\033[1;34m[test]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[test]\033[0m %s\n' "$*" >&2; }

"$ROOT/build.sh"

CHROMERPC_ADDR="${CHROMERPC_ADDR:-localhost:50051}"
CHROMERPC_PORT="${CHROMERPC_ADDR##*:}"
CHROMERPC_BIN="${CHROMERPC_BIN:-$ROOT/../chromerpc/bin/chromerpc}"

log "go test ./..."
(cd "$ROOT" && go test -v -count=1 ./...)

# ── Smoke automation ──────────────────────────────────────────────────────────
CHROMERPC_PID=""

stop_chromerpc() {
  if [ -n "$CHROMERPC_PID" ] && kill -0 "$CHROMERPC_PID" 2>/dev/null; then
    log "stopping chromerpc (pid $CHROMERPC_PID)"
    kill "$CHROMERPC_PID" 2>/dev/null || true
    wait "$CHROMERPC_PID" 2>/dev/null || true
  fi
}
trap stop_chromerpc EXIT

port_open() {
  if command -v lsof >/dev/null 2>&1; then
    lsof -iTCP:"$1" -sTCP:LISTEN >/dev/null 2>&1
  else
    (exec 3<>/dev/tcp/127.0.0.1/"$1") 2>/dev/null && exec 3<&- 3>&-
  fi
}

if port_open "$CHROMERPC_PORT"; then
  log "chromerpc already running on :$CHROMERPC_PORT"
else
  if [ ! -x "$CHROMERPC_BIN" ]; then
    warn "chromerpc binary not found at $CHROMERPC_BIN — skipping smoke automation"
    log "tests complete (without live smoke test)"
    exit 0
  fi
  CHROME_APP="${CHROME_APP:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
  log "starting temporary chromerpc on :$CHROMERPC_PORT"
  "$CHROMERPC_BIN" -headless -addr ":$CHROMERPC_PORT" -chrome "$CHROME_APP" \
    >/tmp/chrome-testing-smoke.log 2>&1 &
  CHROMERPC_PID=$!
  for _ in $(seq 1 20); do
    if port_open "$CHROMERPC_PORT"; then break; fi
    sleep 0.5
  done
  if ! port_open "$CHROMERPC_PORT"; then
    warn "chromerpc didn't start within 10s — see /tmp/chrome-testing-smoke.log"
    log "tests complete (server unavailable)"
    exit 0
  fi
fi

SMOKE_OUT="$ROOT/screenshots/smoke_test.png"
log "running smoke automation → $SMOKE_OUT"
(cd "$ROOT" && go run ./cmd/run_automation \
  -addr "$CHROMERPC_ADDR" \
  -automation automations/smoke_test.textproto \
  -out "$SMOKE_OUT")

"$ROOT/validate.sh" "$SMOKE_OUT"

log "tests complete"
