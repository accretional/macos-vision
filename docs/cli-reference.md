# CLI Reference

`macos-vision` is a command-line tool that exposes macOS vision, audio, and media APIs.

**Usage:** `macos-vision <subcommand> --operation <operation> [-FLAGS]`

Run `macos-vision <subcommand> --help` for full details on any subcommand.

---

## ocr

Extract text from images. Stream mode is detected automatically when stdin is piped.

| Operation | Description |
|-----------|-------------|
| *(only one)* | Recognise text in an image |

| Flag | Description |
|------|-------------|
| `--input <path>` | Image file to process (required unless `--lang` or streaming) |
| `--output <path>` | Directory or `.json` file for output |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--artifacts-dir <dir>` | Write debug overlay image here (requires `--debug`) |
| `--rec-langs <langs>` | Recognition languages, comma-separated (e.g. `en-US,fr-FR`) |
| `--boxes-format <fmt>` | Overlay image format: `png` (default), `jpg`, `tiff`, `bmp`, `gif` |
| `--lang` | List supported recognition languages instead of processing |
| `--debug` | Draw bounding boxes and write overlay image |
| `--no-stream` | Force file mode even when stdin/stdout are piped |

---

## face

Detect faces, bodies, and poses in images.

| Operation | Description |
|-----------|-------------|
| `face-rectangles` | **(default)** Bounding boxes around detected faces |
| `face-landmarks` | 68-point facial landmark geometry |
| `face-quality` | Per-face capture quality score |
| `human-rectangles` | Bounding boxes around detected human bodies |
| `body-pose` | 17-joint human body pose skeleton |
| `hand-pose` | 21-point hand pose landmarks |
| `animal-pose` | Animal body pose landmarks |

| Flag | Description |
|------|-------------|
| `--input <path>` | Image file to process (required unless streaming) |
| `--operation <op>` | Operation to run (default: `face-rectangles`) |
| `--output <path>` | Directory or `.json` file for output |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--artifacts-dir <dir>` | Write debug overlay images here (requires `--debug`) |
| `--boxes-format <fmt>` | Overlay image format: `png` (default), `jpg`, `tiff`, `bmp`, `gif` |
| `--debug` | Draw detection boxes and write overlay image |
| `--no-stream` | Force file mode even when stdin/stdout are piped |
| `--max-lag <n>` | Max queued frames before dropping in stream mode (default: 1) |

---

## classify

Classify scenes, objects, and image content.

| Operation | Description |
|-----------|-------------|
| `classify` | **(default)** Top scene/object classifications for an image |
| `animals` | Detect and classify animals with bounding boxes |
| `rectangles` | Detect salient rectangular regions (documents, screens) |
| `horizon` | Detect horizon angle |
| `contours` | Detect contour paths in the image |
| `aesthetics` | Aesthetic quality scores (overall, composition, lighting) |
| `feature-print` | Compute a perceptual feature vector for similarity search |

| Flag | Description |
|------|-------------|
| `--input <path>` | Image file to process (required) |
| `--operation <op>` | Operation to run (default: `classify`) |
| `--output <path>` | Directory or `.json` file for output |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--artifacts-dir <dir>` | Write debug overlay images here (requires `--debug`) |
| `--boxes-format <fmt>` | Overlay image format: `png` (default), `jpg`, `tiff`, `bmp`, `gif` |
| `--debug` | Draw detection boxes and write overlay image |
| `--no-stream` | Force file mode even when stdin/stdout are piped |

---

## segment

Separate subjects from backgrounds and generate saliency maps.

| Operation | Description |
|-----------|-------------|
| `foreground-mask` | **(default)** Foreground subject mask |
| `person-segment` | Full-body person segmentation mask |
| `person-mask` | Fine-grained person instance mask |
| `attention-saliency` | Heatmap of visually salient regions |
| `objectness-saliency` | Heatmap of object-like regions |

| Flag | Description |
|------|-------------|
| `--input <path>` | Image file to process (required) |
| `--operation <op>` | Operation to run (default: `foreground-mask`) |
| `--output <path>` | Output mask image file, directory, or `.json` path |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--artifacts-dir <dir>` | Write mask images here |
| `--no-stream` | Force file mode even when stdin is piped |

---

## track

Measure motion and registration across video frames.

| Operation | Description |
|-----------|-------------|
| `homographic` | **(default)** Estimate a homographic transform between frames |
| `translational` | Estimate a translational (2-DOF) transform between frames |
| `optical-flow` | Dense per-pixel optical flow; writes flow PNGs to `--artifacts-dir` |
| `trajectories` | Track salient feature point trajectories across frames |

| Flag | Description |
|------|-------------|
| `--input <path>` | Video file or directory of ordered image frames (required) |
| `--operation <op>` | Operation to run (default: `homographic`) |
| `--output <path>` | Directory or `.json` file for output |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--artifacts-dir <dir>` | Directory for optical-flow PNG frames |

---

## overlay

Visualise analysis results as an interactive SVG.

| Operation | Description |
|-----------|-------------|
| *(only one)* | Render a JSON result file as an SVG overlay on the source image |

| Flag | Description |
|------|-------------|
| `--json <path>` | JSON result file to render; use `-` to read from stdin |
| `--input <path>` | Override the image path embedded in the JSON |
| `--output <path>` | Output file path (default: `<json-basename>.svg`) |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--show-labels` | Draw visible text labels on bounding boxes and polygons |
| `--no-stream` | Force file mode even when stdin/stdout are piped |

---

## debug

Inspect image file metadata and properties.

| Operation | Description |
|-----------|-------------|
| *(only one)* | Report image dimensions, color space, DPI, and format metadata |

| Flag | Description |
|------|-------------|
| `--input <path>` | Image file to inspect (required) |
| `--output <path>` | Directory or `.json` file for output |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |

---

## shazam

Identify songs and audio from recordings.

| Operation | Description |
|-----------|-------------|
| `match` | **(default)** Identify a song from an audio file *(requires Apple Developer account; not yet tested)* |
| `match-custom` | Match against a custom `.shazamcatalog` (requires `--catalog`) |
| `build` | Build a `.shazamcatalog` from a directory of audio files |

| Flag | Description |
|------|-------------|
| `--input <path>` | Audio file, or directory of audio files (`build`) |
| `--operation <op>` | Operation to run (default: `match`) |
| `--output <path>` | Directory or `.json` file for output |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--artifacts-dir <dir>` | Output directory for built catalog (`build`) |
| `--catalog <path>` | Path to `.shazamcatalog` file (`match-custom`) |
| `--sample-rate <hz>` | Sample rate for raw PCM stdin (default: 16000) |
| `--channels <n>` | Channel count for raw PCM stdin (default: 1) |
| `--bit-depth <n>` | Bit depth for raw PCM stdin (default: 16) |
| `--no-stream` | Force file mode even when stdin is piped |
| `--debug` | Emit `processing_ms` in output |

---

## streamcapture

Capture stills, video, and audio from cameras and displays.

| Operation | Description |
|-----------|-------------|
| `screenshot` | **(default)** Capture a still image of a display |
| `photo` | Capture a still photo from a camera |
| `audio` | Record audio from the microphone (runs until Ctrl+C) |
| `video` | Record video with audio from a camera (runs until Ctrl+C) |
| `screen-record` | Record a display to a video file (runs until Ctrl+C) |
| `barcode` | Scan for barcodes/QR codes and stream results as NDJSON |
| `list-devices` | List available cameras and microphones |

| Flag | Description |
|------|-------------|
| `--operation <op>` | Operation to run (default: `screenshot`) |
| `--output <path>` | Output file path for captured media |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--artifacts-dir <dir>` | Directory for captured media when `--output` is not set |
| `--display-index <n>` | Display to use for `screenshot`/`screen-record` (default: 0) |
| `--device-index <n>` | Camera or mic to use for `photo`/`video`/`mic`/`barcode` (default: 0) |
| `--duration <secs>` | Stop recording after this many seconds (`mic`, `video`, `screen-record`) |
| `--format <fmt>` | Video container format: `mp4` (default), `mov` |
| `--no-audio` | Omit microphone when recording video |
| `--types <list>` | Comma-separated barcode types to scan for (default: all) |
| `--preview` | Show a live preview window before/during capture |
| `--fps <n>` | Target frame rate for video stream (default: 30) |
| `--jpeg-quality <0-1>` | JPEG quality for MJPEG stream (default: 0.85) |
| `--sample-rate <hz>` | Audio sample rate for audio stream (default: 16000) |
| `--channels <n>` | Audio channel count for audio stream (default: 1) |
| `--bit-depth <n>` | Audio bit depth for audio stream (default: 16) |
| `--no-stream` | Force file mode even when stdout is piped |
| `--debug` | Emit `processing_ms` in output |

---

## nl

Analyse and process natural language text.

| Operation | Description |
|-----------|-------------|
| `detect-language` | **(default)** Identify the language of text |
| `tokenize` | Split text into tokens (words, sentences, paragraphs) |
| `tag` | Part-of-speech, named entity, lemma, or custom scheme tagging |
| `embed` | Compute a word or sentence embedding vector |
| `distance` | Semantic distance between two words |
| `contextual-embed` | Contextual word embedding (requires macOS 14+) |
| `classify` | Text classification with a CoreML model |

| Flag | Description |
|------|-------------|
| `--text <string>` | Inline text to analyse |
| `--input <path>` | Text file to analyse |
| `--operation <op>` | Operation to run (default: `detect-language`) |
| `--output <path>` | Directory or `.json` file for output |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--language <lang>` | BCP-47 language tag (e.g. `en`, `fr-FR`) |
| `--scheme <scheme>` | Tagging scheme for `tag` operation |
| `--unit <unit>` | Tokenizer unit: `word` (default), `sentence`, `paragraph` |
| `--word <word>` | Word for `embed` operation |
| `--word-a <word>` | First word for `distance` operation |
| `--word-b <word>` | Second word for `distance` operation |
| `--similar <word>` | Find words nearest to this word (`embed` operation) |
| `--model <path>` | CoreML model path for `classify` |
| `--topk <n>` | Top-K results (default: 3) |
| `--debug` | Emit `processing_ms` in output |
| `--no-stream` | Force file mode even when stdin/stdout are piped |

---

## av

Inspect, convert, and process audio and video files.

| Operation | Description |
|-----------|-------------|
| `probe` | **(default)** Inspect tracks, duration, codec, and transform info |
| `tracks` | List all tracks with type, codec, dimensions, and frame rate |
| `meta` | Read embedded metadata (ID3, iTunes, QuickTime) and chapters |
| `frames` | Extract one or more frames as PNG images |
| `encode` | Re-encode or remux to a different preset; `--audio-only` for audio-only output |
| `waveform` | Generate normalised waveform sample data from audio |
| `concat` | Concatenate multiple video files into one |
| `tts` | Synthesise speech from text to an audio file |
| `noise` | Compute RMS noise level over 100 ms windows |
| `pitch` | Autocorrelation-based pitch detection with note names |
| `stems` | Separate vocals from background using a high-pass filter |
| `presets` | List available AVAssetExportSession preset names |
| `split` | Divide a video into segments at given timestamps |
| `mix` | Overlay multiple audio files into a single mixed output |
| `burn` | Burn text or an image watermark into a video |
| `fetch` | Download a remote media URL to a local file |
| `retime` | Change playback speed by a given factor (2.0 = 2x, 0.5 = half) |

| Flag | Description |
|------|-------------|
| `--input <path>` | Input video, audio, or image file (or URL for `fetch`) |
| `--operation <op>` | Operation to run (default: `probe`) |
| `--output <path>` | Output file or directory |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--artifacts-dir <dir>` | Directory for extracted frames / waveform data |
| `--preset <name>` | Export preset: `low`, `medium`, `high`, `hevc-1080p`, `hevc-4k`, … |
| `--audio-only` | Export audio track only (`encode`) |
| `--time <t>` | Timestamp in seconds or `HH:MM:SS` (`frames`) |
| `--times <t1,t2,...>` | Comma-separated timestamps (`frames`, `split`) |
| `--time-range <s,d>` | Start and duration in seconds, comma-separated (`encode`) |
| `--key <key>` | Metadata key filter (`meta`) |
| `--videos <p1,p2,...>` | Comma-separated video paths (`concat`) |
| `--inputs <p1,p2,...>` | Comma-separated audio paths (`mix`) |
| `--overlay <path>` | Image file to burn into video (`burn`) |
| `--text <string>` | Inline text for `tts` or `burn` |
| `--voice <id>` | Voice identifier (`tts`) |
| `--factor <n>` | Speed multiplier, e.g. `2.0` = 2x speed (`retime`) |
| `--pitch-hop <n>` | Hop size in audio frames for pitch analysis |
| `--fps <n>` | Frame rate for MJPEG stdin → video file (`encode`, default: 30) |
| `--no-stream` | Disable auto-detection of pipe I/O |
| `--debug` | Emit `processing_ms` in output |

---

## speech

Transcribe speech and analyse voice characteristics.

| Operation | Description |
|-----------|-------------|
| `transcribe` | **(default)** Transcribe an audio file to text |
| `voice-analytics` | Emit per-segment voice analytics (pitch, jitter, shimmer, …) |
| `list-locales` | List supported recognition locales |

| Flag | Description |
|------|-------------|
| `--input <path>` | Audio file to process (required for `transcribe`/`voice-analytics`) |
| `--operation <op>` | Operation to run (default: `transcribe`) |
| `--output <path>` | Directory or `.json` file for output |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--audio-lang <lang>` | BCP-47 locale for recognition (default: `en-US`) |
| `--offline` | Use on-device recognition only (no network) |
| `--sample-rate <hz>` | Sample rate for raw PCM stdin (default: 16000) |
| `--channels <n>` | Channel count for raw PCM stdin (default: 1) |
| `--bit-depth <n>` | Bit depth for raw PCM stdin (default: 16) |
| `--no-header` | Force raw PCM mode, ignoring any MVAU header |
| `--no-stream` | Force file mode even when stdin is piped |
| `--debug` | Emit `processing_ms` in output |

---

## sna

Classify sounds and environmental audio.

| Operation | Description |
|-----------|-------------|
| `classify` | **(default)** Classify audio with Apple's built-in sound classifier |
| `list-labels` | List labels supported by Apple's classifier |

| Flag | Description |
|------|-------------|
| `--input <path>` | Audio file to analyse (required for `classify`) |
| `--operation <op>` | Operation to run (default: `classify`) |
| `--output <path>` | Directory or `.json` file for output |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--topk <n>` | Top-K results per window (default: 3) |
| `--classify-window <secs>` | Analysis window duration in seconds |
| `--classify-overlap <frac>` | Overlap factor between windows, `[0.0, 1.0)` |
| `--sample-rate <hz>` | Sample rate for raw PCM stdin (default: 16000) |
| `--channels <n>` | Channel count for raw PCM stdin (default: 1) |
| `--bit-depth <n>` | Bit depth for raw PCM stdin (default: 16) |
| `--no-stream` | Force file mode even when stdin is piped |
| `--debug` | Emit `processing_ms` in output |

---

## coreimage

Apply image filters and analyse visual properties.

| Operation | Description |
|-----------|-------------|
| `apply-filter` | **(default)** Apply a filter to an image and write the result |
| `suggest-filters` | Suggest applicable filters for an image (optionally apply with `--apply`) |
| `list-filters` | List available filter names (optionally with category metadata) |

| Flag | Description |
|------|-------------|
| `--input <path>` | Image file to process (required for `apply-filter`) |
| `--operation <op>` | Operation to run (default: `apply-filter`) |
| `--output <path>` | Output image file, directory, or `.json` path |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--artifacts-dir <dir>` | Write rendered images here |
| `--filter-name <name>` | Filter name, e.g. `CISepiaTone` (`apply-filter`) |
| `--filter-params <json>` | JSON object of scalar filter parameters |
| `--format <fmt>` | Output image format: `png` (default), `jpg`, `heif`, `tiff` |
| `--apply` | Also render images when using `suggest-filters` |
| `--category-only` | Return category metadata instead of filter names (`list-filters`) |
| `--debug` | Emit `processing_ms` in output |

---

## imagetransfer

Import and manage files on connected cameras and scanners.

| Operation | Description |
|-----------|-------------|
| `list-devices` | **(default)** List connected cameras and scanners |
| `camera/files` | List files on a camera's media storage |
| `camera/thumbnail` | Fetch a thumbnail for a file on the camera |
| `camera/metadata` | Fetch EXIF/metadata for a file on the camera |
| `camera/import` | Download file(s) from the camera to disk |
| `camera/delete` | Delete file(s) from the camera |
| `camera/capture` | Fire the shutter remotely for tethered shooting |
| `camera/sync-clock` | Synchronise the camera's clock to system time |
| `scanner/preview` | Run an overview scan and save the preview image |
| `scanner/scan` | Run a full scan and save the result |

| Flag | Description |
|------|-------------|
| `--operation <op>` | Operation to run (default: `list-devices`) |
| `--output <path>` | Output file or directory (import destination, scan output) |
| `--json-output <path>` | Write JSON envelope here (default: stdout) |
| `--device-index <n>` | Which device to use when multiple are found (default: 0) |
| `--file-index <n>` | File index within the camera's file list (default: 0) |
| `--all` | Operate on all files instead of a single `--file-index` |
| `--delete-after` | Delete from device after successful import |
| `--sidecars` | Also download sidecar files during import |
| `--thumb-size <px>` | Max thumbnail dimension in pixels |
| `--dpi <n>` | Scan resolution in DPI (default: scanner preferred) |
| `--format <fmt>` | Scanner output format: `tiff` (default), `jpeg`, `png` |
| `--catalog-timeout <s>` | Seconds to wait for camera file catalog (default: 15) |
| `--debug` | Emit `processing_ms` in output |
