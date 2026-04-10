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
| `svg`      | Overlay Vision JSON output as SVG shapes on the source image |
| `audio`    | Audio inference: transcription, classification, Shazam, pitch, noise |
| `debug`    | Print image metadata (dimensions, file size) |

## Build and Install

```bash
make          # debug build + sign
make release  # release build + sign
make install  # release build + sign + copy to /usr/local/bin
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

# Audio
macos-vision audio --audio clip.m4a --operation transcribe
macos-vision audio --audio clip.m4a --operation classify --topk 5

# Debug
macos-vision debug --img image.png
```

### `ocr`

Flags: `--img`, `--img-dir`, `--output`, `--output-dir`, `--rec-langs`, `--merge`, `--debug`, `--boxes-format`, `--lang`

| Operation | Description |
|-----------|-------------|
| ocr *(default)* | Recognize text; JSON with strings, confidence, and corner quads (`VNRecognizeTextRequest`) |

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

Reads the `operation` field inside the JSON and overlays the appropriate shapes. Operations with no spatial data (`classify`, `contours`, `aesthetics`, `feature-print`) produce no overlay.

Flags: `--json`, `--img`, `--output`, `--show-labels`

| JSON `operation` | Overlay |
|--------------------|----------------|
| `face-rectangles` | Face bounding boxes |
| `face-landmarks` | Face box + landmark points |
| `face-quality` | Face box + quality score |
| `human-rectangles` | Person bounding boxes |
| `body-pose` | Body skeleton |
| `hand-pose` | Hand skeleton |
| `animal-pose` | Animal keypoints |
| `animals` | Animal bounding boxes |
| `rectangles` | Detected quads |
| `horizon` | Horizon line |
| `trajectories` | Trajectory paths |
| `ocr` | Text observation quads |

### `audio`

Flags: `--audio`, `--audio-dir`, `--output`, `--output-dir`, `--operation`, `--audio-lang`, `--offline`, `--topk`, `--merge`, `--catalog`, `--debug`, `--mic`, `--screenshot`, `--camera`, `--record`, `--camera-index`, `--display-index`

| Operation | Description |
|-----------|-------------|
| `classify` *(default)* | Sound classification with top-K labels (macOS 12+, `SNClassifySoundRequest`) |
| `transcribe` | Speech-to-text via `SFSpeechRecognizer` (`SpeechAnalyzer` is Swift exclusive) |
| `shazam` | Song identification via ShazamKit (macOS 12+) |
| `shazam-custom` | Match audio against a custom `.shazamcatalog` (use `--catalog`) |
| `shazam-build` | Build a `.shazamcatalog` from an audio file |
| `detect` | Sound event detection — all classes with timestamps |
| `noise` | Measure noise / RMS level over time |
| `pitch` | Pitch (fundamental frequency) analysis over time |
| `isolate` | Voice isolation (returns processed audio path) |

**Capture / streaming modes** (replaces `--audio` / `--audio-dir`):

| Flag | Description |
|------|-------------|
| `--mic` | Stream from microphone; press Enter to stop |
| `--screenshot` | Capture a screenshot; press Enter to capture (`--display-index` selects display) |
| `--camera` | Capture a photo from camera; press Enter to capture (`--camera-index` selects device) |
| `--record` | Record camera + microphone video; Enter to start, Enter to stop |

### `debug`

Flags: `--img`, `--img-dir`, `--output`, `--output-dir`

| Operation | Description |
|-----------|-------------|
| *(none)* | Print JSON: filename, path, width, height, file size |

## Running examples

```bash
bash cmd/example/all_subcommands.sh        # run all subcommands, output to sample_data/output/
bash cmd/example/subcommand_face.sh        # face only
```

## Tests

```bash
bash tests/smoke-test.sh    # build and run all subcommand unit tests
```
