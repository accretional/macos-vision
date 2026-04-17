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

## `shazam` (ShazamKit)

**Flags:** `--input` (audio file or directory for `build`), `--output` / `--json-output`, `--artifacts-dir`, `--operation`, `--catalog` (`.shazamcatalog` path for `match-custom`; output dir for `build`), `--debug`

> Note: All operations require macOS 12.0+.

| Operation | Description |
|-----------|-------------|
| `match` *(default)* | Song / audio identification against the Shazam catalog (`SHSession`) |
| `match-custom` | Match against a custom `.shazamcatalog` file (`--catalog`) |
| `build` | Build a `.shazamcatalog` from a directory of audio files (`--input` = directory) |

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

**Flags:** `--input`, `--output`, `--artifacts-dir`, `--operation`, `--preset`, `--time`, `--times`, `--time-range`, `--key`, `--videos`, `--text`, `--voice`, `--pitch-hop`

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
| `noise` | RMS / noise level over 100 ms windows; works on audio and video files |
| `pitch` | Fundamental frequency per hop (`--pitch-hop` frames, default 512); works on audio and video files |
| `isolate` | Voice isolation via 150 Hz high-pass filter; `--output` sets the output audio path |
| `tts` | Text-to-speech (`--text` or `--input`, optional `--voice`); writes AAC (`.m4a`, `.aac`, `.mp4`, …) by default — extensionless `--output` becomes `.m4a`; `.wav`/`.aif`/`.aiff` selects 16-bit PCM |

**Presets** (subset): `low`, `medium`, `high`, `hevc-1080p`, `hevc-4k`, `prores-422`, `prores-4444`, `m4a`, `passthrough`

---

## `sna` (SoundAnalysis)

**Flags:** `--input` (audio file), `--output` / `--json-output`, `--operation`, `--topk` (default 5), `--classify-window` (window duration in seconds, macOS 12+), `--classify-overlap` (overlap factor [0,1)), `--model` (CoreML model path for `classify-custom` / `list-labels`), `--debug`

> Note: `classify` and `list-labels` require macOS 12.0+ (`SNClassifierIdentifierVersion1`). `classify-custom` works on macOS 10.15+. The built-in classifier default window is **3 seconds** — audio files shorter than 3 s produce no windows.

| Operation | Description |
|-----------|-------------|
| `classify` *(default)* | Sound classification using Apple's built-in classifier (`SNClassifierIdentifierVersion1`, macOS 12+); returns per-window top-K labels with confidence, window duration, and overlap factor |
| `classify-custom` | Classification using a custom CoreML audio model (`--model`); same output shape as `classify` |
| `detect` | Event detection filtered to target keywords (crying, scream, alarm, siren, dog, cat, baby, glass); returns only matching windows (macOS 12+) |
| `list-labels` | All 303 known sound labels from the built-in classifier (or a custom model with `--model`); no audio input required |

---

## `speech`

**Flags:** `--input` (audio file), `--output` / `--json-output`, `--operation`, `--audio-lang` (default `en-US`), `--offline`, `--debug`

> Note: `transcribe` and `voice-analytics` require Speech Recognition permission granted in System Settings → Privacy & Security → Speech Recognition. On macOS 26, the binary must be signed with a Developer ID certificate to trigger the permission prompt. `list-locales` has no authorization requirement.

| Operation | Description |
|-----------|-------------|
| `transcribe` *(default)* | Speech-to-text from audio file; returns transcript, per-segment timestamps, confidence, and alternative word hypotheses (`SFSpeechRecognizer`) |
| `voice-analytics` | Speaking rate, pause duration, and vocal quality metrics — pitch (ln normalized), jitter (%), shimmer (dB), voicing probability (`SFSpeechRecognitionMetadata`, macOS 11.3+; requires `--offline` / on-device recognition) |
| `list-locales` | All locales supported by `SFSpeechRecognizer.supportedLocales` |

---

## `debug`

**Flags:** `--input`, `--output` / `--json-output`

| Operation | Description |
|-----------|-------------|
| *(none)* | JSON: filename, path, width, height, file size |
