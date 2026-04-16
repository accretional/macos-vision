# macos-vision CLI reference

Run `macos-vision --help` for the executable’s usage text. JSON results use a small **envelope** (`cliVersion`, `subcommand`, `operation`, optional `input`, `result`); human/progress lines go to **stderr**; the envelope goes to **stdout** unless a JSON file path is set.

## Common options

| Flag | Description |
|------|-------------|
| `--input <path>` | Primary input (image, video, audio, text file, or directory where supported) |
| `--output <path>` | Depends on subcommand: JSON file path, media path, `.svg` path, or an existing **directory** (JSON + artifacts are derived inside it) |
| `--json-output <path>` | Explicit path for the JSON envelope (optional; overrides envelope destination implied by `--output`) |
| `--artifacts-dir <dir>` | PNG masks, debug overlays, optical-flow frames, isolate audio, capture default folder, etc. |
| `--debug` | Debug drawing or timing where supported |
| `--boxes-format <fmt>` | Debug image format: png (default), jpg, tiff, bmp, gif |
| `--json <path>` | Vision JSON file (`overlay` / `svg` subcommand) |

---

## `ocr`

**Flags:** `--input`, `--output` / `--json-output`, `--artifacts-dir`, `--rec-langs`, `--debug`, `--boxes-format`, `--lang`

| Operation | Description |
|-----------|-------------|
| *(default)* | Text recognition; JSON with strings, confidence, corner quads (`VNRecognizeTextRequest`) |

---

## `face`

**Flags:** `--input`, `--output` / `--json-output`, `--artifacts-dir`, `--operation`, `--debug`, `--show-labels`, `--boxes-format`

| Operation | Description |
|-----------|-------------|
| `face-rectangles` *(default)* | Face bounding boxes (`VNDetectFaceRectanglesRequest`) |
| `face-landmarks` | Face mesh regions / points (`VNDetectFaceLandmarksRequest`) |
| `face-quality` | Per-face capture quality (`VNDetectFaceCaptureQualityRequest`) |
| `human-rectangles` | Person bounding boxes (`VNDetectHumanRectanglesRequest`) |
| `body-pose` | 2D body joints (`VNDetectHumanBodyPoseRequest`) |
| `hand-pose` | Hand joints (`VNDetectHumanHandPoseRequest`) |
| `animal-pose` | Animal keypoints (`VNDetectAnimalBodyPoseRequest`, macOS 14+) |

---

## `classify`

**Flags:** `--input`, `--output` / `--json-output`, `--artifacts-dir`, `--operation`, `--debug`, `--show-labels`, `--boxes-format`

| Operation | Description |
|-----------|-------------|
| `classify` *(default)* | Scene / object classification (`VNClassifyImageRequest`) |
| `animals` | Recognized animals (`VNRecognizeAnimalsRequest`) |
| `rectangles` | Axis-aligned regions (`VNDetectRectanglesRequest`) |
| `horizon` | Horizon line (`VNDetectHorizonRequest`) |
| `contours` | Contour geometry (macOS 11+, `VNDetectContoursRequest`) |
| `aesthetics` | Aesthetic scores (macOS 15+, `VNCalculateImageAestheticsScoresRequest`) |
| `feature-print` | Image embedding (`VNGenerateImageFeaturePrintRequest`) |

---

## `segment`

**Flags:** `--input`, `--output` / `--json-output`, `--artifacts-dir`, `--operation`

| Operation | Description |
|-----------|-------------|
| `foreground-mask` *(default)* | Foreground alpha mask (macOS 14+, `VNGenerateForegroundInstanceMaskRequest`) |
| `person-mask` | Instance-colored person masks (macOS 14+, `VNGeneratePersonInstanceMaskRequest`) |
| `person-segment` | Person vs background (macOS 12+, `VNGeneratePersonSegmentationRequest`) |
| `attention-saliency` | Attention saliency (`VNGenerateAttentionBasedSaliencyImageRequest`) |
| `objectness-saliency` | Objectness saliency (`VNGenerateObjectnessBasedSaliencyImageRequest`) |

---

## `track`

**Flags:** `--input` (video file or frame directory), `--output` / `--json-output`, `--artifacts-dir` (required for `optical-flow`), `--operation`

| Operation | Description |
|-----------|-------------|
| `homographic` *(default)* | 3×3 homography between frames (`VNTrackHomographicImageRegistrationRequest`; video often needs macOS 14+) |
| `translational` | Translation between frames (`VNTrackTranslationalImageRegistrationRequest`) |
| `optical-flow` | Dense optical flow (`VNTrackOpticalFlowRequest`) |
| `trajectories` | Moving-object trajectories (`VNDetectTrajectoriesRequest`, macOS 11+) |

---

## `overlay`

Reads the `operation` field in the JSON and writes an SVG overlay. Operations with no spatial data (`classify`, `contours`, `aesthetics`, `feature-print`) produce no overlay.

**Flags:** `--json`, `--input`, `--output` (SVG path or directory), `--json-output`, `--show-labels`. Subcommand name `svg` is accepted as an alias for `overlay`.

| JSON `operation` | Overlay |
|------------------|---------|
| `face-rectangles` | Face boxes |
| `face-landmarks` | Face box + landmarks |
| `face-quality` | Face box + quality |
| `human-rectangles` | Person boxes |
| `body-pose` | Body skeleton |
| `hand-pose` | Hand skeleton |
| `animal-pose` | Animal keypoints |
| `animals` | Animal boxes |
| `rectangles` | Detected quads |
| `horizon` | Horizon line |
| `trajectories` | Trajectory paths |
| `ocr` | Text observation quads |

---

## `audio`

**Flags:** `--input`, `--json-output`, `--artifacts-dir`, `--operation`, `--audio-lang`, `--offline`, `--topk`, `--catalog`, `--debug`, `--mic`, windowing flags as in `--help`

| Operation | Description |
|-----------|-------------|
| `classify` *(default)* | Sound classification top-K (macOS 12+, `SNClassifySoundRequest`) |
| `transcribe` | Speech-to-text (`SFSpeechRecognizer`) |
| `shazam` | Song ID (ShazamKit, macOS 12+) |
| `shazam-custom` | Match against `.shazamcatalog` (`--catalog`) |
| `shazam-build` | Build `.shazamcatalog` from audio |
| `detect` | Sound event detection with timestamps |
| `noise` | Noise / RMS over time |
| `pitch` | Pitch (fundamental frequency) over time |
| `isolate` | Voice isolation (outputs processed audio path) |

## `capture`

**Flags:** `--operation`, `--output` (media file path or directory), `--json-output`, `--artifacts-dir`, `--display-index`

| Operation | Description |
|-----------|-------------|
| `screenshot` *(default)* | Capture display |
| `camera` | Capture from camera |
| `mic` | Capture from microphone |
| `list-devices` | List capture devices |

---

## `nl` (NaturalLanguage)

**Flags:** `--text`, `--input` (text file), `--json-output`, `--output` (envelope path when no `--json-output`), `--operation`, `--language`, `--scheme`, `--unit`, `--word`, `--similar`, `--word-a`, `--word-b`, `--model`, `--topk`

| Operation | Description |
|-----------|-------------|
| `detect-language` | Language hypotheses |
| `tokenize` | Tokens (`--unit`: word, sentence, paragraph) |
| `tag` | Tagging (`--scheme`: pos, ner, lemma, language, script) |
| `embed` | Word vector; `--similar` for neighbors |
| `distance` | Cosine distance between `--word-a` and `--word-b` |
| `contextual-embed` | Contextual embedding |
| `classify` | Text classification (may require `--model`) |

---

## `av` (AVFoundation)

**Flags:** `--input`, `--output`, `--artifacts-dir`, `--operation`, `--preset`, `--time`, `--times`, `--time-range`, `--key`, `--videos`, `--text`, `--voice`

| Operation | Description |
|-----------|-------------|
| `inspect` | Container / stream summary |
| `tracks` | Track listing |
| `metadata` | Metadata items (`--key` optional filter) |
| `thumbnail` | Frame image (`--time` / `--times`) |
| `export` | Transcode segment (`--preset`, `--time-range`) |
| `export-audio` | Extract audio |
| `list-presets` | List export presets |
| `compose` | Concatenate `--videos` |
| `waveform` | Waveform samples (JSON) |
| `tts` | Text-to-speech (`--text` or `--input`, optional `--voice`); writes AAC (`.m4a`, `.aac`, `.mp4`, …) by default — extensionless `--output` becomes `.m4a`; `.wav`/`.aif`/`.aiff` selects 16-bit PCM |

**Presets** (subset): `low`, `medium`, `high`, `hevc-1080p`, `hevc-4k`, `prores-422`, `prores-4444`, `m4a`, `passthrough`

---

## `debug`

**Flags:** `--input`, `--output` / `--json-output`

| Operation | Description |
|-----------|-------------|
| *(none)* | JSON: filename, path, width, height, file size |
