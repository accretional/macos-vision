# macos-vision

macOS CLI around Apple’s **Vision** framework (Objective‑C), with related subcommands for audio, NaturalLanguage, AVFoundation, capture, and overlays.

Full flag and operation tables: **[docs/cli-reference.md](docs/cli-reference.md)**.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ocr` | Text recognition |
| `face` | Face, body, and pose |
| `classify` | Scene/object analysis |
| `segment` | Masks and saliency |
| `track` | Video / sequence registration and motion |
| `overlay` | Vision JSON to SVG overlay |
| `audio` | Transcribe, classify, Shazam, pitch, noise, etc. |
| `capture` | Screen, camera, mic, list devices |
| `nl` | Language ID, tokenize, tag, embeddings |
| `av` | Inspect, export, waveform, TTS, compose |
| `debug` | Image metadata |

## Build and install

```bash
make
make release
make install
```

## Quick examples

```bash
macos-vision ocr --input image.png
macos-vision segment --input image.png --operation person-segment --output ./out --artifacts-dir ./out
macos-vision face --input image.png --operation body-pose --output ./results.json
macos-vision track --input clip.mp4
macos-vision overlay --json result.json --input image.png
macos-vision audio --input clip.m4a --operation classify --topk 5 --output ./out.json
```

`--img`, `--video`, and `--audio` still work as aliases for `--input`. See [docs/cli-reference.md](docs/cli-reference.md) for the envelope shape and per-subcommand flags.

## Examples and tests

```bash
bash cmd/example/all_subcommands.sh   # populate sample_data/output/
bash tests/smoke-test.sh              # build + subcommand smoke tests
```
