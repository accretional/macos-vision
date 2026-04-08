# macos-vision

A macOS CLI tool wrapping Apple's Vision framework, written in Objective-C.

## Subcommands

| Subcommand | Description |
|------------|-------------|
| `ocr`      | Text recognition |
| `face`     | Face, body, and pose analysis |
| `classify` | Scene/object classification and image analysis |
| `segment`  | Background removal, person segmentation, and saliency |
| `track`    | Video tracking and image registration |
| `svg`      | Overlay Vision JSON on the source image as SVG |
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

# Face / classify
macos-vision face --img image.png --operation face-landmarks
macos-vision classify --img image.png --operation classify

# Track (video)
macos-vision track --video clip.mp4

# Svg (JSON from `face`, `classify`, or `track` with a supported `operation`)
macos-vision svg --json result.json --img image.png

# Debug
macos-vision debug --img image.png
```

### `ocr`

Flags: `--img`, `--img-dir`, `--output`, `--output-dir`, `--rec-langs`, `--merge`, `--debug`, `--boxes-format`, `--lang`

| Operation | Description |
|-----------|-------------|
| *(none: fixed pipeline)* | Recognize text; JSON with strings, confidence, and corner quads (`VNRecognizeTextRequest`) |

### `face`

Flags: `--img`, `--img-dir`, `--output`, `--output-dir`, `--operation`, `--debug`, `--svg`, `--show-labels`, `--boxes-format`

| Operation | Description |
|-----------|-------------|
| `face-rectangles` *(default)* | Face bounding boxes (`VNDetectFaceRectanglesRequest`) |
| `face-landmarks` | Face mesh regions / points (`VNDetectFaceLandmarksRequest`) |
| `face-quality` | Per-face capture-quality score (`VNDetectFaceCaptureQualityRequest`) |
| `human-rectangles` | Person bounding boxes (`VNDetectHumanRectanglesRequest`) |
| `body-pose` | 2D body joints (`VNDetectHumanBodyPoseRequest`) |
| `hand-pose` | Hand joints (`VNDetectHumanHandPoseRequest`) |
| `animal-pose` | Animal body keypoints (`VNDetectAnimalBodyPoseRequest`) |

### `classify`

Flags: `--img`, `--img-dir`, `--output`, `--output-dir`, `--operation`, `--debug`, `--svg`, `--show-labels`, `--boxes-format`

| Operation | Description |
|-----------|-------------|
| `classify` *(default)* | Scene / object classification (`VNClassifyImageRequest`) |
| `animals` | Recognized animals (`VNRecognizeAnimalsRequest`) |
| `rectangles` | Axis-aligned regions (`VNDetectRectanglesRequest`) |
| `horizon` | Horizon line (`VNDetectHorizonRequest`) |
| `contours` | Contour geometry (macOS 11+, `VNDetectContoursRequest`) |
| `aesthetics` | Aesthetic scores (macOS 15+, `VNCalculateImageAestheticsScoresRequest`) |
| `feature-print` | Image embedding for similarity (`VNGenerateImageFeaturePrintRequest`) |

### `segment`

Flags: `--img`, `--img-dir`, `--output`, `--output-dir`, `--operation`

| Operation | Description |
|-----------|-------------|
| `foreground-mask` *(default)* | Subject / foreground alpha mask (macOS 14+, `VNGenerateForegroundInstanceMaskRequest`) |
| `person-mask` | Instance-colored person masks (macOS 14+, `VNGeneratePersonInstanceMaskRequest`) |
| `person-segment` | Person vs background mask (macOS 12+, `VNGeneratePersonSegmentationRequest`) |
| `attention-saliency` | Saliency heatmap (`VNGenerateAttentionBasedSaliencyImageRequest`) |
| `objectness-saliency` | Objectness saliency (`VNGenerateObjectnessBasedSaliencyImageRequest`) |

### `track`

Flags: `--video` *or* `--img-dir`, `--output`, `--output-dir`, `--operation`

| Operation | Description |
|-----------|-------------|
| `homographic` *(default)* | 3×3 homography between consecutive frames (`VNTrackHomographicImageRegistrationRequest`; video path needs macOS 14+) |
| `translational` | Translation between frames (`VNTrackTranslationalImageRegistrationRequest`; video: macOS 14+) |
| `optical-flow` | Dense optical flow (`VNTrackOpticalFlowRequest`; video: macOS 14+) |
| `trajectories` | Moving-object trajectories (`VNDetectTrajectoriesRequest`; macOS 11+) |

### `svg`

Reads the `operation` field inside the JSON (from `face`, `classify`, or `track`). Other JSON shapes are not overlaid.

Flags: `--json`, `--img`, `--output`, `--show-labels`

| JSON `operation` | Description |
|--------------------|----------------|
| `face-rectangles` | Boxes for each face |
| `face-landmarks` | Face box + landmark regions / points |
| `face-quality` | Face box + quality label |
| `human-rectangles` | Person boxes |
| `body-pose` | Body skeleton |
| `hand-pose` | Hand skeleton |
| `animal-pose` | Animal pose |
| `classify` | Top classification labels |
| `animals` | Animal regions |
| `rectangles` | Detected rectangles |
| `horizon` | Horizon line |
| `trajectories` | Trajectory paths |
| `aesthetics` | Score labels |

### `debug`

Flags: `--img`, `--img-dir`, `--output`, `--output-dir`

| Operation | Description |
|-----------|-------------|
| *(none)* | Print JSON: filename, path, width, height, file size |

## Tests

```bash
bash tests/run.sh           # run all tests
bash tests/run.sh --reset   # regenerate baselines
```
