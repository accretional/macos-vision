# SoundAnalysis framework — API surface

SDK headers: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/SoundAnalysis.framework/`  
Framework: `SoundAnalysis` (already linked in `Package.swift`)  
Availability: macOS 10.15+

---

## Operations implemented

| Operation | Functionality | Flags | API used |
|-----------|--------------|-------|----------|
| `classify` | Classify sounds in an audio file using Apple's built-in model | `--input`, `--topk`, `--classify-window`, `--classify-overlap` | `SNClassifySoundRequest(classifierIdentifier: .version1)` + `SNAudioFileAnalyzer` (macOS 12+) |
| `classify-custom` | Classify sounds using a custom CoreML audio model | `--input`, `--model`, `--topk`, `--classify-window`, `--classify-overlap` | `SNClassifySoundRequest(mlModel:)` + `SNAudioFileAnalyzer` (macOS 10.15+) |
| `list-labels` | List all sound labels the built-in classifier can produce | *(none)* | `SNClassifySoundRequest.knownClassifications` (macOS 12+) |

---

## Key classes

| Class | Purpose | Header |
|-------|---------|--------|
| `SNAudioFileAnalyzer` | Analyzes an audio file; `-analyze` blocks until done; `-addRequest:withObserver:error:` registers a request | `SNAudioFileAnalyzer.h` |
| `SNAudioStreamAnalyzer` | Real-time analysis via AVAudioEngine tap; not used in the `sna` subcommand | `SNAudioStreamAnalyzer.h` |
| `SNClassifySoundRequest` | The only request type; init with built-in classifier (macOS 12+) or custom CoreML model (macOS 10.15+); configure `overlapFactor` and `windowDuration` | `SNClassifySoundRequest.h` |
| `SNClassificationResult` | Delivered per analysis window; `.classifications` sorted by confidence descending; `.timeRange` gives position in the audio | `SNClassificationResult.h` |
| `SNClassification` | Single label: `.identifier` (e.g. `"speech"`) and `.confidence` `[0.0, 1.0]` | `SNClassification.h` |
| `SNTimeDurationConstraint` | Enumerated or range constraint on window duration; read via `request.windowDurationConstraint` (macOS 12+) | `SNTypes.h` |

---

## Custom CoreML models

Any CoreML model that accepts audio and outputs a classification dictionary works with `SNClassifySoundRequest`. Models can be trained with Create ML (Sound Classifier template). The model file is a `.mlmodel` or compiled `.mlmodelc` bundle.