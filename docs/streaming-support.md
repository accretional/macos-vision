# Streaming Support

Tools can be composed into pipelines by piping stdout of one command into stdin of the next. This page lists which operations support streaming.

**Supported** — can be used in a pipeline (reads from stdin, writes to stdout, or both)  
**—** — file operation; does not apply  
**Planned** — streaming not yet available but will be added

---

## streamcapture

| Operation | Streaming | Notes |
|---|---|---|
| `video` | Supported | Captures video from camera into the pipeline |
| `audio` | Supported | Captures audio from microphone into the pipeline |
| `photo` | Supported | Captures a single photo and emits it into the pipeline |
| `screenshot` | Supported | Captures a single screenshot and emits it into the pipeline |
| `screen-record` | Supported | Captures screen video into the pipeline |
| `barcode` | Supported | Reads video from pipeline, emits video with barcode detections attached |
| `list-devices` | — | Lists available cameras and microphones |

---

## face

| Operation | Streaming | Notes |
|---|---|---|
| `face-rectangles` | Supported | Reads video from pipeline, emits video with face bounding boxes attached |
| `face-landmarks` | Supported | Reads video from pipeline, emits video with 68-point facial geometry attached |
| `face-quality` | Supported | Reads video from pipeline, emits video with per-face quality scores attached |
| `human-rectangles` | Supported | Reads video from pipeline, emits video with human body bounding boxes attached |
| `body-pose` | Supported | Reads video from pipeline, emits video with 17-joint body pose attached |
| `hand-pose` | Supported | Reads video from pipeline, emits video with 21-point hand landmarks attached |
| `animal-pose` | Supported | Reads video from pipeline, emits video with animal pose landmarks attached |

---

## classify

| Operation | Streaming | Notes |
|---|---|---|
| `classify` | Supported | Reads video from pipeline, emits video with scene classifications attached |
| `animals` | Supported | Reads video from pipeline, emits video with animal detections attached |
| `rectangles` | Supported | Reads video from pipeline, emits video with salient rectangles attached |
| `horizon` | Supported | Reads video from pipeline, emits video with horizon angle attached |
| `contours` | Supported | Reads video from pipeline, emits video with detected contours attached |
| `aesthetics` | Supported | Reads video from pipeline, emits video with aesthetic scores attached |
| `feature-print` | Supported | Reads video from pipeline, emits video with perceptual feature vector attached |

---

## ocr

| Operation | Streaming | Notes |
|---|---|---|
| `recognize` | Supported | Reads video from pipeline, emits video with recognised text attached |

---

## segment

| Operation | Streaming | Notes |
|---|---|---|
| `foreground-mask` | Supported | Reads video from pipeline, emits masked video frames |
| `person-segment` | Supported | Reads video from pipeline, emits person-segmented video frames |
| `person-mask` | Supported | Reads video from pipeline, emits fine-grained person mask frames |
| `attention-saliency` | Supported | Reads video from pipeline, emits saliency heatmap frames |
| `objectness-saliency` | Supported | Reads video from pipeline, emits objectness heatmap frames |

---

## overlay

| Operation | Streaming | Notes |
|---|---|---|
| *(default)* | Supported | Reads video and detection results from pipeline, emits annotated video frames |

---

## coreimage

| Operation | Streaming | Notes |
|---|---|---|
| `apply-filter` | Supported | Reads video from pipeline, emits filtered video frames |
| `suggest-filters` | — | Suggests applicable filters for a given image file |
| `list-filters` | — | Lists available filter names |

---

## speech

| Operation | Streaming | Notes |
|---|---|---|
| `transcribe` | Supported | Reads audio from pipeline, passes audio through, emits transcript results as they arrive |
| `voice-analytics` | — | Requires a complete audio file for analysis |
| `list-locales` | — | Lists supported recognition locales |

---

## sna

| Operation | Streaming | Notes |
|---|---|---|
| `classify` | Supported | Reads audio from pipeline, passes audio through, emits sound classification results |
| `classify-custom` | Supported | Same as classify with a custom model |
| `list-labels` | — | Lists supported classifier labels |

---

## shazam

| Operation | Streaming | Notes |
|---|---|---|
| `match-custom` | Supported | Same as match against a custom catalog |
| `build` | — | Builds a song catalog from a directory of audio files |

---

## av

| Operation | Streaming | Notes |
|---|---|---|
| `frames` | Supported | Extracts frames from a video file and emits them into the pipeline |
| `encode` | Supported | Reads video and audio from pipeline, encodes to a video file |
| `probe` | — | Inspects a media file's tracks, duration, and codec info |
| `tracks` | — | Lists all tracks in a media file |
| `meta` | — | Reads embedded metadata from a media file |
| `waveform` | — | Generates waveform sample data from an audio file |
| `noise` | — | Computes RMS noise level over time |
| `pitch` | — | Detects pitch and note names from an audio file |
| `stems` | — | Separates vocals from background audio |
| `tts` | — | Synthesises speech from text to an audio file |
| `concat` | — | Concatenates multiple video files |
| `mix` | — | Overlays multiple audio files into a single output |
| `burn` | — | Burns a text or image watermark into a video |
| `fetch` | — | Downloads a remote media URL to a local file |
| `retime` | — | Changes the playback speed of a video |
| `split` | — | Splits a video into segments at given timestamps |
| `presets` | — | Lists available export presets |

---

## track

| Operation | Streaming | Notes |
|---|---|---|
| `homographic` | Planned | Estimates homographic transform between frames |
| `translational` | Planned | Estimates translational transform between frames |
| `optical-flow` | Planned | Computes dense per-pixel optical flow |
| `trajectories` | Planned | Tracks salient feature point trajectories |

---

## nl

Streaming operations read OCR text from the pipeline (requires `ocr recognize` upstream) and attach results as metadata to each frame.

| Operation | Streaming | Notes |
|---|---|---|
| `detect-language` | Supported | Reads OCR text from pipeline, emits frames with detected language attached |
| `tokenize` | Supported | Reads OCR text from pipeline, emits frames with token list attached |
| `tag` | Supported | Reads OCR text from pipeline, emits frames with tagged tokens attached |
| `embed` | Supported | Reads OCR text from pipeline, emits frames with embedding vector attached |
| `distance` | — | Requires two explicit words; not applicable in a pipeline |
| `contextual-embed` | — | Not supported in stream mode |
| `classify` | — | Requires a CoreML model and explicit text input |

---

## debug

| Operation | Streaming | Notes |
|---|---|---|
| *(default)* | — | Inspects image properties and metadata |

---

## imagetransfer

| Operation | Streaming | Notes |
|---|---|---|
| `list-devices` | — | Lists connected cameras and scanners |
| `camera/files` | — | Lists files on a connected camera |
| `camera/thumbnail` | — | Fetches a thumbnail from a camera file |
| `camera/metadata` | — | Fetches EXIF metadata from a camera file |
| `camera/import` | — | Downloads files from a camera to disk |
| `camera/delete` | — | Deletes files from a camera |
| `camera/capture` | — | Fires the shutter remotely |
| `camera/sync-clock` | — | Synchronises the camera clock to system time |
| `scanner/preview` | — | Runs an overview scan and saves the preview |
| `scanner/scan` | — | Runs a full scan and saves the result |
