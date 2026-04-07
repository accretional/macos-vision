# macos-vision

A macOS CLI tool wrapping Apple's Vision framework, written in Objective-C.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ocr`      | Text recognition and barcode detection |
| `segment`  | Background removal, person segmentation, and saliency |
| `debug`    | Print image metadata (dimensions, file size) |

## Build and Install

```bash
swift build -c release
cp .build/release/macos-vision /usr/local/bin/
```

## Usage

```bash
# OCR
macos-vision ocr --img image.png
macos-vision ocr --img-dir ./images --output-dir ./out --merge
macos-vision ocr --lang

# Segment
macos-vision segment --img image.png --operation foreground-mask --output ./out
macos-vision segment --img image.png --operation person-segment
macos-vision segment --img image.png --operation attention-saliency

# Debug
macos-vision debug --img image.png
```

### OCR options
| Flag | Description |
|------|-------------|
| `--img <path>` | Single image |
| `--img-dir <path>` | Batch mode |
| `--output / --output-dir <path>` | Output directory |
| `--rec-langs <langs>` | Comma-separated recognition languages (e.g. `en-US,zh-Hans`) |
| `--merge` | Merge all text into `merged_output.txt` (batch mode) |
| `--debug` | Draw bounding boxes on the image |
| `--boxes-format <fmt>` | Box image format: `png` (default), `jpg`, `tiff`, `bmp`, `gif` |
| `--lang` | List supported recognition languages |

### Segment operations
| Operation | API | macOS |
|-----------|-----|-------|
| `foreground-mask` | `VNGenerateForegroundInstanceMaskRequest` | 14.0+ |
| `person-mask` | `VNGeneratePersonInstanceMaskRequest` | 14.0+ |
| `person-segment` | `VNGeneratePersonSegmentationRequest` | 12.0+ |
| `attention-saliency` | `VNGenerateAttentionBasedSaliencyImageRequest` | 10.15+ |
| `objectness-saliency` | `VNGenerateObjectnessBasedSaliencyImageRequest` | 10.15+ |

## Output

OCR outputs JSON per image:
```json
{
  "info": { "filename": "image.png", "width": 936, "height": 936 },
  "texts": "recognized text...",
  "observations": [{ "text": "...", "confidence": 0.99, "quad": { ... } }]
}
```

Segment outputs PNG files with alpha channel (e.g. `image_foreground.png`).

## Tests

```bash
bash tests/run.sh           # run all tests
bash tests/run.sh --reset   # regenerate baselines
```
