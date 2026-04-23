# Chrome Testing — Onboarding & Integration Guide

This document covers how `chrome-testing/` is structured, how to onboard a new
machine, and how to extend the suite with new automations.

The setup mirrors the pattern used by
[proto-docx](https://github.com/accretional/proto-docx): a layered set of
shell scripts (`setup → build → test → LET_IT_RIP`) that manage dependencies,
run the [chromerpc](https://github.com/accretional/chromerpc) gRPC server, execute
headless-browser automation sequences, and validate screenshot outputs.

---

## Overview

```
chrome-testing/
├── setup.sh              # Install deps, clone & build chromerpc
├── build.sh              # Vet & build the run_automation Go tool
├── test.sh               # Run unit tests + smoke automation
├── LET_IT_RIP.sh         # Full harness: all automations + validation
├── validate.sh           # Assert a PNG is real (magic bytes + size)
├── go.mod                # Separate Go module for chrome-testing tooling
├── cmd/
│   └── run_automation/
│       └── main.go       # CLI: parse textproto → call RunAutomation RPC
├── automations/
│   ├── smoke_test.textproto       # Basic navigation + screenshot
│   ├── viewport_mobile.textproto  # Mobile-sized viewport test
│   └── multi_step.textproto       # Multi-page navigation sequence
└── screenshots/          # Output PNGs written here (gitignored)
```

---

## Prerequisites

| Tool | Version | Notes |
|------|---------|-------|
| Go | 1.21+ | `brew install go` or https://go.dev/dl/ |
| Google Chrome | any recent | Auto-detected; set `CHROME_APP` to override |
| Git | any | For cloning chromerpc |

No other tools are required. `grpcurl`, `protoc`, etc. are **not** needed.

---

## Quickstart

```bash
cd chrome-testing/

# 1. One-time setup (clones chromerpc, builds binary, resolves Go deps)
./setup.sh

# 2. Build & vet the run_automation tool
./build.sh

# 3. Smoke test (starts a temporary chromerpc server, runs one automation)
./test.sh

# 4. Full validation suite (all automations + screenshot assertions)
./LET_IT_RIP.sh
```

All scripts are **idempotent** — safe to re-run.

---

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `CHROMERPC_ADDR` | `localhost:50051` | gRPC server address |
| `CHROMERPC_DIR` | `../chromerpc` | Path to chromerpc source checkout |
| `CHROMERPC_REPO` | `https://github.com/accretional/chromerpc.git` | Clone URL (override for forks) |
| `CHROME_APP` | auto-detected | Path to Chrome/Chromium binary |

Example — run against an already-running remote server:

```bash
CHROMERPC_ADDR=192.168.1.10:50051 ./LET_IT_RIP.sh
```

---

## How It Works

### 1. chromerpc server

[chromerpc](https://github.com/accretional/chromerpc) is a gRPC adapter for
the Chrome DevTools Protocol (CDP). It exposes `HeadlessBrowserService` on
`:50051` and translates gRPC calls into CDP commands sent to a headless Chrome
instance.

`setup.sh` clones the repo into `../chromerpc` (sibling of `chrome-testing/`)
and builds the binary to `../chromerpc/bin/chromerpc`. `LET_IT_RIP.sh` starts
the server if nothing is already listening on the configured port, and stops it
on exit via a `trap`.

To start the server manually:

```bash
../chromerpc/bin/chromerpc \
  -headless \
  -addr :50051 \
  -chrome "/Applications/Google Chrome.app/Contents/MacOS/Google Chrome"
```

Or using Docker (no local Chrome required):

```bash
cd ../chromerpc && docker compose up
```

### 2. Automation files (`.textproto`)

Each file in `automations/` is a textproto encoding of chromerpc's
`AutomationSequence` proto message. Steps are executed in order:

```textproto
name: "example"

steps: {
  label: "set_viewport"
  set_viewport: { width: 1280  height: 800  device_scale_factor: 2 }
}
steps: {
  label: "navigate"
  navigate: { url: "https://example.com" }
}
steps: {
  label: "wait_for_render"
  wait: { milliseconds: 500 }
}
steps: {
  label: "screenshot"
  screenshot: { format: "png" }
}
```

Supported step types: `set_viewport`, `navigate`, `wait`, `screenshot`.

### 3. `run_automation` tool

`cmd/run_automation/main.go` is a minimal Go CLI that:

1. Parses a textproto file into `*hbpb.AutomationSequence`
2. Dials the chromerpc gRPC server
3. Calls `HeadlessBrowserService.RunAutomation`
4. Writes the screenshot step's `ScreenshotData` bytes to the output path

```bash
go run ./cmd/run_automation \
  -addr     localhost:50051 \
  -automation automations/smoke_test.textproto \
  -out        screenshots/smoke_test.png \
  -label      screenshot     # which step's data to save (default: "screenshot")
```

### 4. Screenshot validation

`validate.sh` checks every PNG output:

- **Exists** — the file was written
- **Size > 1 KB** — rules out empty or trivial writes
- **PNG magic bytes** — first 4 bytes are `89 50 4E 47`

A real Chrome screenshot of `example.com` at 2× DPR is typically 40–200 KB,
so the 1 KB threshold is deliberately conservative.

---

## Go Module Dependencies

`chrome-testing/` is its own Go module (`module chrome-testing`) separate from
the outer Swift/Objective-C project. On first run, `setup.sh` executes:

```bash
go get github.com/accretional/chromerpc@main
go mod tidy
```

This pins chromerpc (and transitively grpc + protobuf) into `go.mod`/`go.sum`.
Commit both files after running setup on a clean machine.

Key direct imports in `cmd/run_automation/`:

```go
hbpb "github.com/accretional/chromerpc/proto/cdp/headlessbrowser"
"google.golang.org/grpc"
"google.golang.org/grpc/credentials/insecure"
"google.golang.org/protobuf/encoding/prototext"
```

---

## Adding a New Automation

1. Create `automations/<name>.textproto` with the desired steps.
2. Add a `run_automation` call for it in `LET_IT_RIP.sh`:

   ```bash
   run_automation "<name>" automations/<name>.textproto screenshots/<name>.png
   ```

3. Add the output PNG to the validation loop in `LET_IT_RIP.sh`:

   ```bash
   for png in ... screenshots/<name>.png; do
   ```

4. Run `./LET_IT_RIP.sh` to validate end-to-end.

---

## Integration with proto-docx

[proto-docx](https://github.com/accretional/proto-docx)'s `LET_IT_RIP.sh`
auto-starts this same chromerpc server to regenerate its documentation
screenshots. The two repos share the same server binary; running either
suite's `LET_IT_RIP.sh` is sufficient to start the server for both.

If you want the proto-docx screenshot generation to use the same already-running
server:

```bash
# In one terminal — start chrome-testing's server
CHROMERPC_ADDR=localhost:50051 ./chrome-testing/LET_IT_RIP.sh &

# In another terminal — run proto-docx, reusing the server
cd ../proto-docx && CHROMERPC_ADDR=localhost:50051 ./LET_IT_RIP.sh
```

---

## Troubleshooting

**`chromerpc didn't start within 15s`**
Check `/tmp/chrome-testing-lir.log`. Common causes: Chrome not found (set
`CHROME_APP`), port already in use, or Chrome requires `--no-sandbox` on Linux.

**`no screenshot_data in step results`**
The server ran the automation but the screenshot step produced no data. Verify
the URL is reachable from the machine running Chrome, and increase `wait`
milliseconds if the page renders slowly.

**IDE import errors in `main.go`**
Expected until `setup.sh` runs `go get`/`go mod tidy` and populates `go.sum`.
Run `./setup.sh` once to resolve.

**Port 50051 already in use**
Set `CHROMERPC_ADDR=localhost:50052` (or any free port) — all scripts respect
this variable.
