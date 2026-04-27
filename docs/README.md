# Documentation

| Doc | Contents |
|-----|----------|
| [CLI Reference](cli-reference.md) | All subcommands, operations, and flags |
| [Streaming Support](streaming-support.md) | List of subcommands and operations that support streaming and piping |
| [Adding Subcommands](adding-subcommands/) | Guide for implementing new subcommands |

---

## Fun commands to try out

These commands require a video capture device (example: webcam) for input, and `ffplay` (from ffmpeg) to view results. `macos-vision` is assumed to be on your PATH.

### Face detection and body pose in a single pass

```sh
macos-vision streamcapture --operation video | macos-vision face --operation face-rectangles,body-pose | macos-vision overlay | ffplay -f mjpeg -fflags nobuffer -flags low_delay -framedrop -i pipe:0
```

### Image classification on the screen

```sh
macos-vision streamcapture --operation screenshot | macos-vision classify --operation classify | macos-vision overlay | ffplay -f mjpeg -i pipe:0
```

### Continuous OCR on live video

```sh
macos-vision streamcapture --operation video | macos-vision ocr | macos-vision overlay | ffplay -f mjpeg -fflags nobuffer -flags low_delay -framedrop -i pipe:0
```

### Live video foreground segmentation

```sh
macos-vision streamcapture --operation video | macos-vision segment --operation foreground-mask | ffplay -f mjpeg -fflags nobuffer -flags low_delay -framedrop -i pipe:0
```

### Sepia tone filter on the live video

```sh
macos-vision streamcapture --operation video | macos-vision coreimage --operation apply-filter --filter-name CISepiaTone | ffplay -f mjpeg -i pipe:0
```

### Transcribe live mic audio (speak, then Ctrl+C)

```sh
macos-vision streamcapture --operation audio | macos-vision speech --operation transcribe
```
