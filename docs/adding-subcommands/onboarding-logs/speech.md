# Onboarding Log - Speech

Process notes for adding subcommands to `macos-vision`, cross-referencing against `docs/new-subcommand-instructions.md` and `AGENTS.md`.

---

## Speech subcommand (2026-04-16)

### What was implemented

- `Sources/speech/main.h` + `Sources/speech/main.m` — three operations: `transcribe`, `voice-analytics`, `list-locales`
- `Sources/speech/test.sh` — smoke tests (10/10 passing)
- `cmd/example/subcommand_speech.sh` — example script
- `docs/subcommands/speech.md` — API surface doc
- `docs/cli-reference.md` — `speech` section added
- `Sources/main.m` — import, routing, dispatch, usage text

---

## Missing instructions and gaps found

### Step 1: Info Gathering

**Gap 1: Apple docs pages require JavaScript rendering.**  
The instructions say to fetch the Apple developer docs URL from `apple-apis.csv`. Those pages render with JavaScript and cannot be fetched with a plain HTTP tool. Instead, read the SDK headers directly — they contain all docstrings:

```bash
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks
find "$SDK/<Framework>.framework" -name "*.h"
cat "$SDK/Speech.framework/Versions/A/Headers/SFSpeechRecognizer.h"
```

This is faster and more authoritative than the web docs.

**Gap 2: Check if the framework is already linked.**  
Before anything, check `Package.swift`. `Speech` was already in `linkerSettings` — no changes needed. The instructions don't mention this check.

**Gap 3: Check if the framework is already used elsewhere.**  
`Sources/audio/main.m` already uses `SFSpeechRecognizer` for `transcribe`. Reading it first revealed:
- The auth challenge pattern (check-only, no `requestAuthorization`)
- Working code for `SFSpeechURLRecognitionRequest` / semaphore result handling

This saved time and kept implementations consistent.

**Gap 4: Check SDK headers for deprecation before designing operations.**  
`SFTranscriptionSegment.voiceAnalytics` is `NS_DEPRECATED(10_15, 11_3, ...)` — it was moved to `SFSpeechRecognitionMetadata.voiceAnalytics` in macOS 11.3. Designing `voice-analytics` on the deprecated property would have caused compiler warnings and incorrect behavior on modern macOS. Always `grep` headers for `NS_DEPRECATED` and `API_DEPRECATED` on properties you plan to use.

---

### Step 2: Implementation

**Gap 6: Read `main.m` routing before implementing.**  
Adding a subcommand requires touching four separate locations in `Sources/main.m`:
1. `MVMainEffectiveOperation` — default operation for the subcommand
2. `MVMainJsonInDirectory` — how the JSON output filename is derived
3. `jsonStem` block in `main()` — what path is used as the JSON filename stem
4. The dispatch block and error message at the bottom

None of this is mentioned in `new-subcommand-instructions.md`. The pattern is clear from the existing subcommands — `audio` and `nl` are the closest references for a text/audio-input subcommand with no artifact outputs.

**Gap 7: Authorization cannot be triggered from an unsigned binary on macOS 26.**  
`SFSpeechRecognizer.requestAuthorization` requires a Developer ID cert to show the OS permission prompt on macOS 26. Calling it from an unsigned `swift build` binary crashes. The correct pattern (from `audio/main.m`) is:
- Use `+authorizationStatus` (check-only, safe for any binary)
- Return a descriptive error if not authorized
- Document that the user must grant permission from an app or signed binary

Tip: To verify auth status by hand: `System Settings → Privacy & Security → Speech Recognition`.

**Gap 8: `@available` version must match the type declaration, not just the property.**  
`SFSpeechRecognitionResult.speechRecognitionMetadata` is declared `API_AVAILABLE(macos(11.0))`, but the type `SFSpeechRecognitionMetadata` itself is `API_AVAILABLE(macos(11.3))`. Using `@available(macOS 11.0, *)` still produces a `-Wunguarded-availability-new` warning. Use the stricter version (11.3) from the type's header.

---

### Step 3: Testing

**Gap 9: The `say` command is the key tool for synthetic audio.**  
`macOS say` is the built-in TTS command. It generates audio files suitable for all audio-related tests:

```bash
say -o smoke.aiff "Some text to recognize."
say -o smoke.wav --data-format=LEF32@22050 "Some text."
```

The test scripts in `audio/test.sh` use `say` and `set +e` / `set -e` to handle auth failures gracefully. Follow that pattern exactly.

**Gap 10: `data_files.json` is shared state between tests and examples.**  
`cmd/example/data_files.json` holds all sample data paths as relative paths from the repo root. Example scripts `eval` it into environment variables. If you add a new audio/image/text sample, add it here so all scripts can reference it by name (e.g., `EXAMPLE_AUDIO_SPEECH`).

**Gap 11: Test from repo root, not subcommand directory.**  
`test.sh` uses `ROOT="$(cd "$(dirname "$0")/../.." && pwd)"` to resolve paths. Always run it as:

```bash
# from repo root:
swift build && bash Sources/speech/test.sh
```

Running from inside `Sources/speech/` will still work because of the `ROOT` resolution, but the binary must already exist from a `swift build` at the root.

**Gap 12: `jq empty` is the minimal valid-JSON check.**  
Per `AGENTS.md`, always pipe JSON output through `jq empty` before marking a test passed. The flag `NSJSONWritingWithoutEscapingSlashes` is required in all JSON serialization calls — missing it causes `\/` in path strings that fail visual validation but still pass `jq empty`. Check for it in every `dataWithJSONObject:options:` call.

---

## Helpful tools / tips

| Tool / Tip | Use |
|-----------|-----|
| `find $SDK -name "*.h" -path "*/Speech.framework/*"` | Locate all headers for a framework |
| `grep -n "NS_DEPRECATED\|API_DEPRECATED" SFTranscriptionSegment.h` | Find deprecated properties before designing operations |
| `say -o /tmp/test.aiff "Hello world"` | Synthetic test audio, no external files needed |
| `jq -e '.result.field \| type == "array"' out.json` | Assert field type in test scripts |
| `set +e; cmd; ec=$?; set -e` | Capture exit code without aborting script |
| `grep -qi "authorized\|Developer ID"` | Match auth error messages across wording variants |
| `swift build 2>&1 \| grep -E "warning:|error:"` | Quick build validation |
| `NSJSONWritingWithoutEscapingSlashes` | Required in all JSON writes — prevents `\/` in paths |
| `MVRelativePath(path)` | Always use for any path placed in a JSON result dict |
