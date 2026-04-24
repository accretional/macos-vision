# macos-vision

macOS CLI around Apple's **Vision** framework (Objective‑C), with related subcommands for audio, NaturalLanguage, AVFoundation, capture, and overlays.

Full flag and operation tables: **[docs/cli-reference.md](docs/cli-reference.md)**.

## Subcommands

| Subcommand | Description | Key operations |
|------------|-------------|----------------|
| `ocr` | Extract text from images | _(single operation, use flags)_ |
| `face` | Face, body, and pose detection | `face-rectangles`, `face-landmarks`, `face-quality`, `body-pose`, `hand-pose`, `human-rectangles`, `animal-pose` |
| `classify` | Scene and object analysis | `classify`, `animals`, `rectangles`, `horizon`, `contours`, `aesthetics`, `feature-print` |
| `segment` | Masks and saliency | `foreground-mask`, `person-segment`, `person-mask`, `attention-saliency`, `objectness-saliency` |
| `track` | Video / sequence registration and motion | `homographic`, `translational`, `optical-flow`, `trajectories` |
| `av` | Inspect, export, compose, and process media | `probe`, `tracks`, `meta`, `frames`, `encode`, `waveform`, `tts`, `noise`, `pitch`, `stems`, `split`, `mix`, `burn`, `concat`, `fetch`, `retime`, `presets` |
| `sna` | Sound classification and analysis | `classify`, `list-labels` |
| `speech` | Speech transcription and analytics | `transcribe`, `voice-analytics`, `list-locales` |
| `shazam` | Song identification and catalog | `match`, `match-custom`, `build` |
| `nl` | Natural language processing | `detect-language`, `tokenize`, `tag`, `embed`, `distance`, `contextual-embed`, `classify` |
| `coreimage` | Image filtering and adjustment | `apply-filter`, `suggest-filters`, `list-filters`, `auto-adjust` |
| `streamcapture` | Screen, camera, mic, and barcode capture | `screenshot`, `photo`, `audio`, `video`, `screen-record`, `barcode`, `list-devices` |
| `imagetransfer` | Camera and scanner device control | `list-devices`, `camera/files`, `camera/import`, `camera/capture`, `scanner/preview`, `scanner/scan` |
| `overlay` | Render subcommand JSON as SVG overlay | _(no operations)_ |
| `debug` | Inspect image file properties (dimensions, DPI, EXIF) | _(no operations)_ |

> **Note — `shazam match`:** The `match` operation require an Apple Developer account and entitlements (`com.apple.developer.shazam-api`). This has not been tested end-to-end yet.

## Build and install

```bash
make
make release
make install
```

## Quick examples

```bash
macos-vision ocr --input image.png
macos-vision face --input image.png --operation body-pose --output ./results.json
macos-vision classify --input image.png --operation animals
macos-vision segment --input image.png --operation person-segment --output ./out --artifacts-dir ./out
macos-vision track --input clip.mp4
macos-vision av --input clip.mp4 --operation probe
macos-vision sna --input clip.m4a --operation classify --topk 5 --output ./out.json
macos-vision speech --input recording.wav --operation transcribe
macos-vision nl --input notes.txt --operation tag
macos-vision streamcapture --operation screenshot --output ./screen.png
macos-vision overlay --json result.json --input image.png
```

## Examples and tests

```bash
bash cmd/example/all_subcommands.sh   # populate sample_data/output/
bash tests/smoke-test.sh              # build + subcommand smoke tests
```
