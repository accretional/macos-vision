# Speech framework — API surface

Source: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/Speech.framework/`  
Framework: `Speech` (already linked in `Package.swift`)  
Availability: macOS 10.15+

---

## Operations implemented

| Operation | Functionality | Flags | API used |
|-----------|--------------|-------|----------|
| `transcribe` | Transcribe an audio file to text with per-word timestamps and confidence | `--input`, `--audio-lang`, `--offline` | `SFSpeechURLRecognitionRequest` + `SFTranscriptionSegment` |
| `voice-analytics` | Transcribe and emit per-frame pitch, jitter, shimmer, and voicing metrics | `--input`, `--audio-lang` | `SFSpeechRecognitionMetadata.voiceAnalytics` (macOS 11.3+) |
| `list-locales` | List all locales supported by the on-device recognizer | *(none)* | `SFSpeechRecognizer.supportedLocales` |

---

## Key classes

| Class | Purpose | Header |
|-------|---------|--------|
| `SFSpeechRecognizer` | Main entry point; create with `-initWithLocale:`; check `.supportsOnDeviceRecognition` before requiring offline | `SFSpeechRecognizer.h` |
| `SFSpeechURLRecognitionRequest` | File-based recognition request; configure `requiresOnDeviceRecognition`, `addsPunctuation`, `contextualStrings` | `SFSpeechURLRecognitionRequest.h` |
| `SFSpeechRecognitionResult` | Delivered to the result handler; `.isFinal` signals completion; holds `bestTranscription` and alternatives | `SFSpeechRecognitionResult.h` |
| `SFTranscription` | Full transcript with `.formattedString` and `.segments` array | `SFTranscription.h` |
| `SFTranscriptionSegment` | Per-word: `.substring`, `.timestamp`, `.duration`, `.confidence`, `.alternativeSubstrings` | `SFTranscriptionSegment.h` |
| `SFSpeechRecognitionMetadata` | Speaking rate, average pause, speech timestamps, and `voiceAnalytics` (macOS 11.3+) | `SFSpeechRecognitionMetadata.h` |
| `SFVoiceAnalytics` | Per-frame pitch (ln Hz), jitter (%), shimmer (dB), and voicing probability; each property is an `SFAcousticFeature` | `SFVoiceAnalytics.h` |
| `SFAcousticFeature` | Wraps `acousticFeatureValuePerFrame` (`NSArray<NSNumber *>`) and `frameDuration` | `SFVoiceAnalytics.h` |

---

## Authorization notes

- Use `+authorizationStatus` to check current status without prompting.
- Use `+requestAuthorization:` to trigger the OS permission prompt — requires:
  - `NSSpeechRecognitionUsageDescription` key in `Info.plist`
  - Binary signed with a Developer ID certificate (on macOS 26, unsigned binaries crash on `requestAuthorization`)
- Voice analytics require `requiresOnDeviceRecognition = YES`.
