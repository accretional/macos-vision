# Speech framework — API surface

Source: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Speech.framework/`  
Framework: `Speech` (already linked in `Package.swift`)  
Availability: macOS 10.15+

---

## Key classes

### SFSpeechRecognizer

The main entry point for speech recognition.

| Member | Availability | Notes |
|--------|-------------|-------|
| `+supportedLocales` | macOS 10.15+ | Returns `NSSet<NSLocale *>` of all supported locales |
| `+authorizationStatus` | macOS 10.15+ | Returns current auth status; does NOT prompt user |
| `+requestAuthorization:` | macOS 10.15+ | Prompts user — **requires Developer ID signing on macOS 26**; crashes unsigned binaries |
| `-initWithLocale:` | macOS 10.15+ | Returns nil if locale unsupported |
| `.isAvailable` | macOS 10.15+ | Whether recognition is currently possible (network may be required) |
| `.supportsOnDeviceRecognition` | macOS 10.15+ | Whether the recognizer can run fully offline |
| `-recognitionTaskWithRequest:resultHandler:` | macOS 10.15+ | Starts recognition; returns `SFSpeechRecognitionTask` |

### SFSpeechURLRecognitionRequest

File-based recognition request.

| Member | Availability | Notes |
|--------|-------------|-------|
| `-initWithURL:` | macOS 10.15+ | Only initializer |
| `.shouldReportPartialResults` | macOS 10.15+ | Default YES; set NO for final-only |
| `.requiresOnDeviceRecognition` | macOS 10.15+ | Keeps audio on-device (less accurate) |
| `.addsPunctuation` | macOS 13+ | Auto-adds periods/commas/question marks |
| `.contextualStrings` | macOS 10.15+ | Up to 100 custom phrases to bias recognition |

### SFSpeechRecognitionResult

Returned in the recognition handler.

| Member | Availability | Notes |
|--------|-------------|-------|
| `.bestTranscription` | macOS 10.15+ | `SFTranscription` with highest confidence |
| `.transcriptions` | macOS 10.15+ | All alternatives, sorted by confidence |
| `.isFinal` | macOS 10.15+ | True when recognition is complete |
| `.speechRecognitionMetadata` | macOS 11.3+ | `SFSpeechRecognitionMetadata`; nil if unavailable |

### SFTranscription

| Member | Notes |
|--------|-------|
| `.formattedString` | Full transcript string |
| `.segments` | `NSArray<SFTranscriptionSegment *>` |

### SFTranscriptionSegment

| Member | Notes |
|--------|-------|
| `.substring` | Transcribed word/utterance |
| `.timestamp` | Start time in seconds |
| `.duration` | Duration in seconds |
| `.confidence` | 0.0–1.0 |
| `.alternativeSubstrings` | Other possible words |
| `.voiceAnalytics` | **Deprecated macOS 11.3** — moved to `SFSpeechRecognitionMetadata.voiceAnalytics` |

### SFSpeechRecognitionMetadata (macOS 11.3+)

| Member | Notes |
|--------|-------|
| `.speakingRate` | Words per minute |
| `.averagePauseDuration` | Average pause between words (seconds) |
| `.speechStartTimestamp` | When speech begins in the audio (seconds) |
| `.speechDuration` | Total speech duration (seconds) |
| `.voiceAnalytics` | `SFVoiceAnalytics` or nil |

### SFVoiceAnalytics (macOS 10.15+)

Voice quality metrics, each as `SFAcousticFeature` (per-frame array).

| Property | Unit | Notes |
|----------|------|-------|
| `.pitch` | ln(normalized Hz) | Logarithm base-e of normalized fundamental frequency |
| `.jitter` | % | Variation in pitch between consecutive frames |
| `.shimmer` | dB | Variation in amplitude |
| `.voicing` | probability [0, 1] | Likelihood each frame is voiced |

### SFAcousticFeature

| Member | Notes |
|--------|-------|
| `.acousticFeatureValuePerFrame` | `NSArray<NSNumber *>` — one value per audio frame |
| `.frameDuration` | Duration of each frame in seconds |

---

## Authorization notes

- Use `+authorizationStatus` to check current status without prompting.
- Use `+requestAuthorization:` to trigger the OS permission prompt — requires:
  - `NSSpeechRecognitionUsageDescription` key in `Info.plist`
  - Binary signed with a Developer ID certificate (on macOS 26, unsigned binaries crash on `requestAuthorization`)
- Voice analytics require `requiresOnDeviceRecognition = YES`.

---

## Operations implemented

| Operation | API used |
|-----------|----------|
| `transcribe` | `SFSpeechURLRecognitionRequest` + `SFTranscriptionSegment` (timestamp, confidence, alternatives) |
| `voice-analytics` | `SFSpeechRecognitionMetadata.voiceAnalytics` (macOS 11.3+) + speaking rate metadata |
| `list-locales` | `SFSpeechRecognizer.supportedLocales` — no auth required |
