# SoundAnalysis framework — API surface

SDK headers: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/SoundAnalysis.framework/`  
Framework: `SoundAnalysis` (already linked in `Package.swift`)  
Availability: macOS 10.15+

---

## Key classes

### SNAudioFileAnalyzer (macOS 10.15+)

Synchronously or asynchronously analyzes an audio file. Used for all file-based classification.

| Member | Notes |
|--------|-------|
| `-initWithURL:error:` | Only initializer; returns nil on invalid/unsupported file |
| `-addRequest:withObserver:error:` | Register an `SNClassifySoundRequest` + observer; returns NO if analyzer can't satisfy the request |
| `-analyze` | Blocking; all observer callbacks complete before returning |
| `-analyzeWithCompletionHandler:` | Async variant; completion called with `didReachEndOfFile` |
| `-cancelAnalysis` | Async; still calls completion handler |

### SNAudioStreamAnalyzer (macOS 10.15+)

For real-time or streaming audio (e.g. AVAudioEngine tap). Not used in the `sna` subcommand.

### SNClassifySoundRequest (macOS 10.15+)

The only request type in the framework.

| Member | Availability | Notes |
|--------|-------------|-------|
| `-initWithMLModel:error:` | macOS 10.15+ | Custom CoreML audio classification model |
| `-initWithClassifierIdentifier:error:` | macOS 12.0+ | Built-in Apple classifier (`SNClassifierIdentifierVersion1`) |
| `.overlapFactor` | macOS 10.15+ | `[0.0, 1.0)`, default 0.5; higher = more results, more compute |
| `.windowDuration` | macOS 12.0+ | `CMTime`; read after init to see the model's default (3 s for v1) |
| `.windowDurationConstraint` | macOS 12.0+ | `SNTimeDurationConstraint` — query supported window durations |
| `.knownClassifications` | macOS 12.0+ | All sound labels the model can produce, sorted by identifier |

**Built-in classifier defaults (SNClassifierIdentifierVersion1):**
- Default window: **3 seconds**
- Default overlap: **0.5**
- 303 known labels (e.g. speech, music, laughter, dog, siren, …)
- Minimum audio duration to produce any output: > 3 s (one full window)

### SNClassificationResult (macOS 10.15+)

Delivered to the observer per analysis window.

| Member | Notes |
|--------|-------|
| `.classifications` | `NSArray<SNClassification *>` sorted by confidence descending |
| `.timeRange` | `CMTimeRange` — start + duration in the audio stream |
| `-classificationForIdentifier:` | macOS 12+ — lookup by label string |

### SNClassification (macOS 10.15+)

| Member | Notes |
|--------|-------|
| `.identifier` | Label string (e.g. `"speech"`, `"dog"`) |
| `.confidence` | `[0.0, 1.0]` |

### SNTimeDurationConstraint (macOS 12.0+)

Union type: either `.type == SNTimeDurationConstraintTypeEnumerated` (discrete set of CMTime values) or `SNTimeDurationConstraintTypeRange` (continuous range). Read via `request.windowDurationConstraint` to know what window durations are legal before configuring.

### Error domain

`SNErrorDomain` with codes: `SNErrorCodeUnknownError`, `SNErrorCodeOperationFailed`, `SNErrorCodeInvalidFormat`, `SNErrorCodeInvalidModel`, `SNErrorCodeInvalidFile`.

---

## Custom CoreML models

Any CoreML model that accepts audio and outputs a classification dictionary works with `SNClassifySoundRequest`. Models can be trained with Create ML (Sound Classifier template). The model file is a `.mlmodel` or compiled `.mlmodelc` bundle.

---

## Operations implemented

| Operation | API used |
|-----------|----------|
| `classify` | `SNClassifySoundRequest(classifierIdentifier: .version1)` + `SNAudioFileAnalyzer` (macOS 12+) |
| `classify-custom` | `SNClassifySoundRequest(mlModel:)` + `SNAudioFileAnalyzer` (macOS 10.15+) |
| `list-labels` | `SNClassifySoundRequest.knownClassifications` — no audio input needed (macOS 12+) |
