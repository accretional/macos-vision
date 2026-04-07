# macos-vision

A macOS CLI tool wrapping Apple's Vision framework, implemented in Objective-C.

## Architecture

- `Sources/main.m` — entry point, manual arg parsing, dispatches to subcommand processors
- `Sources/<subcommand>/main.h` + `main.m` — each subcommand's processor class
- `Sources/<subcommand>/test.sh` — each subcommand's tests (auto-discovered by `tests/run.sh`)
- `tests/run.sh` — test runner; sources all `Sources/*/test.sh` files
- `tests/common.sh` — shared test helpers (`pass`, `fail`, `check_structure`, etc.)
- `tests/tmp/` — gitignored; all test output and baselines go here

## Building

```bash
swift build
```

## Running tests

```bash
bash tests/run.sh
```

## Plan and current state

### Done
- `ocr` subcommand — full implementation with Vision framework (ObjC), tests, baseline validation
  - Single image, batch, merge, `--lang`, `--debug`, `--boxes-format`, `--rec-langs`
  - Vision APIs: `VNRecognizeTextRequest`, `VNDetectTextRectanglesRequest`, `VNDetectDocumentSegmentationRequest`, `VNDetectBarcodesRequest`
- `debug` subcommand — scaffold proving the multi-subcommand architecture scales; outputs image metadata JSON (filename, filepath, width, height, filesize)
- Test infrastructure: `tests/run.sh` auto-discovers `Sources/*/test.sh`, all output in gitignored `tests/tmp/`

### Not yet implemented
Three subcommands remain, each following the same pattern (`Sources/<name>/main.h`, `main.m`, `test.sh`, wired into `Sources/main.m`):

- **`face`** — human/animal body and face analysis
  - `VNDetectFaceRectanglesRequest`, `VNDetectFaceLandmarksRequest`, `VNDetectFaceCaptureQualityRequest`
  - `VNDetectHumanRectanglesRequest`, `VNDetectHumanBodyPoseRequest`, `VNDetectHumanBodyPose3DRequest`
  - `VNDetectHumanHandPoseRequest`, `VNDetectAnimalBodyPoseRequest`

- **`classify`** — scene/object classification and image analysis
  - `VNClassifyImageRequest`, `VNRecognizeAnimalsRequest`, `VNDetectRectanglesRequest`
  - `VNDetectHorizonRequest`, `VNDetectContoursRequest`
  - `VNCalculateImageAestheticsScoresRequest` (macOS 15+), `VNGenerateImageFeaturePrintRequest`

- **`segment`** — image segmentation and saliency
  - `VNGeneratePersonSegmentationRequest`, `VNGeneratePersonInstanceMaskRequest`, `VNGenerateForegroundInstanceMaskRequest`
  - `VNGenerateAttentionBasedSaliencyImageRequest`, `VNGenerateObjectnessBasedSaliencyImageRequest`

- **`track`** — video tracking and image registration (multi-frame/video input)
  - `VNDetectTrajectoriesRequest`, `VNTrackObjectRequest`, `VNTrackRectangleRequest`
  - `VNTrackOpticalFlowRequest`
  - `VNTrackHomographicImageRegistrationRequest`, `VNTrackTranslationalImageRegistrationRequest`
  - Uses `VNVideoProcessor` + `VNStatefulRequest` for frame-by-frame video processing

## Apple Vision API reference

Documentation links for many Apple Vision framework APIs are in `apple-vision-docs.txt` at the project root.
