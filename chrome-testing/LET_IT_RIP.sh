#!/usr/bin/env bash
# LET_IT_RIP.sh — full-ratchet UI validation: build + unit tests + all
# automations + screenshot validation.
#
# Manages the chromerpc server lifecycle automatically:
#   - If a server is already listening on CHROMERPC_ADDR, uses it.
#   - Otherwise, launches one from CHROMERPC_DIR, waits for readiness,
#     and stops it on exit.
#
# Environment overrides:
#   CHROMERPC_ADDR   gRPC server address (default: localhost:50051)
#   CHROMERPC_DIR    path to chromerpc checkout (default: ../chromerpc)
#   CHROME_APP       path to Chrome binary (auto-detected by setup.sh)

set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$ROOT"

log()  { printf '\033[1;34m[LET_IT_RIP]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[LET_IT_RIP]\033[0m %s\n' "$*" >&2; }

"$ROOT/test.sh"

CHROMERPC_ADDR="${CHROMERPC_ADDR:-localhost:50051}"
CHROMERPC_PORT="${CHROMERPC_ADDR##*:}"
CHROMERPC_DIR="${CHROMERPC_DIR:-$ROOT/../chromerpc}"
CHROMERPC_BIN="$CHROMERPC_DIR/bin/chromerpc"
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

# ── Ensure chromerpc server is running ────────────────────────────────────────
if port_open "$CHROMERPC_PORT"; then
  log "chromerpc already running on :$CHROMERPC_PORT"
else
  if [ ! -x "$CHROMERPC_BIN" ]; then
    log "building chromerpc at $CHROMERPC_DIR"
    (cd "$CHROMERPC_DIR" && go build -o bin/chromerpc ./cmd/chromerpc)
  fi
  CHROME_APP="${CHROME_APP:-/Applications/Google Chrome.app/Contents/MacOS/Google Chrome}"
  log "starting chromerpc on :$CHROMERPC_PORT (headless)"
  "$CHROMERPC_BIN" -headless -addr ":$CHROMERPC_PORT" -chrome "$CHROME_APP" \
    >/tmp/chrome-testing-lir.log 2>&1 &
  CHROMERPC_PID=$!
  for _ in $(seq 1 30); do
    if port_open "$CHROMERPC_PORT"; then break; fi
    sleep 0.5
  done
  if ! port_open "$CHROMERPC_PORT"; then
    warn "chromerpc didn't start within 15s — see /tmp/chrome-testing-lir.log"
    exit 1
  fi
  log "chromerpc started (pid $CHROMERPC_PID)"
fi

# ── Run all automations ───────────────────────────────────────────────────────
run_automation() {
  local name="$1" proto="$2" out="$3"
  log "automation: $name → $out"
  (cd "$ROOT" && go run ./cmd/run_automation \
    -addr "$CHROMERPC_ADDR" \
    -automation "$proto" \
    -out "$out")
}

mkdir -p "$ROOT/screenshots"

run_automation "smoke_test"       automations/smoke_test.textproto       screenshots/smoke_test.png
run_automation "viewport_mobile"  automations/viewport_mobile.textproto  screenshots/viewport_mobile.png
run_automation "multi_step"       automations/multi_step.textproto       screenshots/multi_step.png

# ── Validate all screenshots ──────────────────────────────────────────────────
log "validating screenshots"
FAILED=0
for png in screenshots/smoke_test.png screenshots/viewport_mobile.png screenshots/multi_step.png; do
  if "$ROOT/validate.sh" "$png"; then
    log "  ok: $png"
  else
    warn "  FAIL: $png"
    FAILED=1
  fi
done

if [ "$FAILED" -eq 1 ]; then
  warn "one or more screenshot validations failed"
  exit 1
fi

log "all systems go"
