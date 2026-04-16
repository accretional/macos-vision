# Build & Test Onboarding

## Script Hierarchy

```
LET_IT_RIP.sh          ← pre-push / pre-release gate
  └─ test.sh           ← full test suite
       └─ build.sh     ← compile debug binary
            └─ setup.sh  ← dependency checks (idempotent)
```

Each script calls the one below it, so you can always just run the top-level script you need:

| Goal | Script |
|------|--------|
| Check / install dependencies only | `./setup.sh` |
| Build the binary | `./build.sh` |
| Build + run all tests | `./test.sh` |
| Build + test + release smoke check | `./LET_IT_RIP.sh` |

All scripts are **idempotent**: re-running them is safe and skips already-completed work.

---

## Quick Start

```bash
# Clone and enter the repo
git clone https://github.com/accretional/macos-vision-test
cd macos-vision-test

# First-time setup (checks deps, installs jq via Homebrew if needed)
./setup.sh

# Build
./build.sh

# Test
./test.sh

# Full gate before pushing
./LET_IT_RIP.sh
```

---

## Prerequisites

| Tool | Minimum | How to install |
|------|---------|---------------|
| macOS | 10.15 Catalina | Required (Vision/AVFoundation/Cocoa are macOS-only) |
| Xcode CLI tools | any | `xcode-select --install` |
| Swift | 5.9 | Bundled with Xcode |
| jq | any | `brew install jq` — setup.sh does this automatically |

`setup.sh` validates all of the above and exits with a descriptive error if anything is missing.

---

## Test Structure

### Individual unit tests (`Sources/*/test.sh`)

Each Vision subcommand has its own `test.sh` alongside its source code:

```
Sources/
├── audio/test.sh       ← audio analysis (classify, noise, pitch, detect, shazam, isolate, transcribe)
├── classify/test.sh    ← image classification, horizon, contours, feature-print
├── debug/test.sh       ← image metadata
├── face/test.sh        ← face detection, landmarks, quality, body-pose, human-rectangles
├── ocr/test.sh         ← text recognition
├── overlay/test.sh     ← SVG overlay generation (renamed from svg)
├── segment/test.sh     ← foreground mask segmentation
└── track/test.sh       ← video tracking (skips gracefully if frames absent)
```

Subcommands without tests yet (no `test.sh`): `av`, `capture`, `nl`, `common`.

Each script:
- Uses a `mktemp -d` temp directory (cleaned up via `trap ... EXIT`)
- Runs the compiled debug binary against sample images/video
- Validates JSON output with `jq` (field presence, observation counts)
- Tests error handling for missing/invalid inputs
- Tracks `PASS`/`FAIL` counts and exits 1 on any failure

### Smoke test orchestrator (`tests/smoke-test.sh`)

Discovers and runs every `Sources/*/test.sh`, aggregates results, and reports a final pass/fail summary. Supports `SKIP_BUILD=1` env var to skip the redundant `swift build` when called from `test.sh` (which already built via `build.sh`).

### Sample data

All tests use fixtures from `sample_data/input/`:
- `images/` — 12 images (JPG/PNG) covering faces, text, animals, graphics
- `videos/` — 1 MP4 + 20 extracted JPEG frames for tracking tests
- Audio tests use a video file from `videos/` as the audio source

---

## Adding a New Subcommand

1. Create `Sources/<name>/test.sh` following the pattern in any existing subcommand (e.g. `Sources/ocr/test.sh`)
2. The smoke test orchestrator auto-discovers it — no changes to other scripts needed
3. Run `./test.sh` to verify

---

## TODOs & Concerns

### Build

- [ ] **`swift build` output verbosity**: `build.sh` currently streams the full compiler output. For large builds this is noisy. Consider redirecting to a log file and only printing on error (like proto-font's pattern).
- [ ] **Release binary not tested**: `LET_IT_RIP.sh` only smoke-checks that the release binary runs; it does not re-execute the full test suite against `.build/release/`. This is intentional (debug tests are the source of truth) but means release-specific linker issues could slip through.
- [ ] **No incremental build indicator**: `build.sh` always runs `swift build` even when nothing changed. Swift handles this efficiently internally, but there's no "already up to date" message shown to the user.

### Tests

- [ ] **`track` tests skip gracefully without video frames**: `Sources/track/test.sh` skips the homographic/translational/trajectories tests if `sample_data/input/videos/selective_attention_test_frames/` is absent rather than failing hard. This is intentional but means those paths are effectively untested on most machines.
- [ ] **`av`, `capture`, `nl`, `common` have no tests**: These subcommands were added in the audio-nl-av branch but have no `test.sh` files yet.
- [ ] **No test isolation for binary**: All tests share the single `.build/debug/macos-vision` binary. Concurrent test runs (e.g., parallel CI jobs on the same machine) would conflict. Not currently an issue but worth noting.
- [ ] **`jq` version sensitivity**: Tests use `jq -e` which exits non-zero on `false`/`null`. This is the intended behavior but could be surprising if JSON output fields change type in the future.
- [ ] **No CI configuration for the new scripts**: `.github/workflows/release.yml` builds for release only and does not run `test.sh`. Consider adding a CI job that runs `./test.sh` on each PR.

### Platform

- [ ] **macOS-only**: The Vision framework is macOS/iOS only. There is no Linux/Windows path. If this ever needs cross-platform support, the entire Vision layer would need to be replaced.
- [ ] **Minimum macOS version**: `Package.swift` targets macOS 10.15 but the newer Vision APIs (e.g., animal body pose in `face/`) require macOS 12+. Tests may silently return zero observations on older OS versions rather than failing clearly.
- [ ] **Apple Silicon vs Intel**: Binary path (`.build/debug/`) is the same for both architectures. The CI workflow in `release.yml` builds arm64 and x86_64 separately; the local scripts build for the current architecture only.

### Setup

- [ ] **Homebrew not required but assumed for jq install**: `setup.sh` only auto-installs `jq` if Homebrew is present. On machines without Homebrew (e.g., fresh CI runners), the user gets an error message with a manual download link. Consider bundling a static `jq` binary or using a different install path.
- [ ] **No lockfile / pinned dependency versions**: The project has no external Swift dependencies beyond Apple frameworks, so there is no `Package.resolved` to worry about. If third-party SPM packages are added later, ensure `Package.resolved` is committed.

---

## Notes on Migration from `tests/smoke-test.sh`

Previously, `tests/smoke-test.sh` was the only entry point and it ran `swift build` internally. The new `test.sh` / `build.sh` / `setup.sh` structure:

1. Extracts the build step into `build.sh` (so build and test are separate concerns)
2. Extracts dependency checking into `setup.sh` (idempotent, run on every build)
3. Keeps `tests/smoke-test.sh` as the test orchestrator (unchanged in behavior)
4. Adds `SKIP_BUILD=1` support to `tests/smoke-test.sh` to avoid the redundant `swift build` call when `test.sh` invokes it (since `build.sh` already ran)

`tests/smoke-test.sh` still works standalone (`./tests/smoke-test.sh`) for backwards compatibility.
