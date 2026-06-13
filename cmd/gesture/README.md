# gesture — camera-aided live hand-gesture control

A `cmd/` orchestration tool that turns webcam hand gestures into macOS window
and input actions. It does **not** add a new Vision API — it composes existing
`macos-vision` subcommands:

```
streamcapture video ──MJPEG──▶ face --operation hand-pose ──MJPEG+headers──▶ gesture.py
                                                                                  │
                                          temporal gesture classifier            │
                                                                                  ▼
                                        window / input subcommands ◀── recognised gestures
```

`face` runs `VNDetectHumanHandPoseRequest` per frame and forwards the 21-joint
result as a per-frame `X-MV-face-hand-pose` header on the MJPEG stream. The tool
reads that stream, classifies gestures over time, and drives the `window` and
`input` subcommands (both added alongside this tool).

## Gestures

Each gesture owns a distinct hand pose, so they never collide:

| Pose                         | Gesture        | Action                                   |
|------------------------------|----------------|------------------------------------------|
| Two open palms, held ~1s     | **Clutch**     | Arm / disarm the controller              |
| Fist → fling → open          | **Grab & throw** | Left/right: move focused window to that display; up: maximize; down: minimize |
| One open palm, swipe         | **Spaces**     | Left/right: switch desktop; up: Mission Control; down: App Exposé |
| Index point                  | **Air-mouse**  | Move the cursor                          |
| Thumb + index pinch          | **Click / drag** | Click, or drag while held              |

While **disarmed**, only the clutch is active — stray hand motion does nothing.
Show two open palms for ~1 second to arm, again to disarm.

## Requirements

- Built `macos-vision` binary (`swift build` at the repo root). The tool
  auto-detects `.build/{debug,release}/macos-vision`, or pass `--binary`.
- **Camera** permission (for `streamcapture`).
- **Accessibility** permission for the terminal/app running this, so the
  `window` and `input` subcommands can move windows and post events
  (System Settings ▸ Privacy & Security ▸ Accessibility). The first action
  prompts for it.

## Usage

```bash
# Live control (default)
./run.sh
# or
python3 gesture.py

# See what gestures fire without performing any action
python3 gesture.py --dry-run

# Map the air-mouse onto a specific display
python3 gesture.py --pointer-display 1

# Raw (un-mirrored) horizontal direction
python3 gesture.py --no-mirror
```

### Tuning / testing without a camera

Record a session once, then replay it (instant, deterministic) to tune
thresholds or debug — `--source` skips the camera and reads a saved stream:

```bash
# Record
macos-vision streamcapture video --fps 15 --no-audio \
  | macos-vision face --operation hand-pose > session.mjpeg

# Replay through the classifier
python3 gesture.py --source session.mjpeg --fps 15 --dry-run
```

Run the classifier unit tests (synthetic frames, no camera, no binary):

```bash
python3 gesture.py --self-test
```

## Key options

| Flag                  | Default | Meaning                                            |
|-----------------------|---------|----------------------------------------------------|
| `--fps`               | 15      | Camera frame rate (also the replay clock for `--source`) |
| `--device`            | 0       | Camera device index                                |
| `--pointer-display`   | 0       | Display the air-mouse maps onto                    |
| `--no-mirror`         | off     | Don't mirror horizontal direction                  |
| `--dry-run`           | off     | Print gestures + commands, perform no action       |
| `--source <path>`     | —       | Replay an MJPEG recording (`-` for stdin)          |
| `--throw-dist` etc.   | —       | Gesture thresholds (normalized image units / sec)  |

## Notes

- Spaces / Mission Control use the default macOS keyboard shortcuts
  (Ctrl+←/→/↑/↓); enable "Mission Control" shortcuts in System Settings if they
  don't respond.
- The air-mouse is throttled to ~25 Hz and maps the index tip across one
  display; expect coarse control — it's a demo of the actuation path, not a
  precision pointer.
