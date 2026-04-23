# Testing

## Running the suite

```bash
bash LET_IT_RIP.sh   # full gate: build → smoke tests → release build check
bash test.sh         # build + smoke tests only
bash tests/smoke-test.sh  # smoke tests only (requires prior build)
```

Each subcommand has its own `Sources/<name>/test.sh`. `smoke-test.sh` runs all of them and reports pass/fail per subcommand.

---

## Current status (as of 2026-04-17)

| Subcommand     | Result  | Notes                                      |
|----------------|---------|--------------------------------------------|
| av             | ✓ pass  |                                            |
| classify       | ✓ pass  |                                            |
| coreimage      | ✓ pass  |                                            |
| debug          | ✓ pass  |                                            |
| face           | ✓ pass  |                                            |
| imagecapture   | ✓ pass  |                                            |
| ocr            | ✓ pass  |                                            |
| overlay        | ✓ pass  |                                            |
| segment        | ✓ pass  |                                            |
| shazam         | ✓ pass  |                                            |
| sna            | ✓ pass  |                                            |
| speech         | ✓ pass  | 2 tests skipped (see below)                |
| track          | ✓ pass  | 3 tests skipped (see below)                |

---

## Skipped tests

### `speech` — `transcribe` and `voice-analytics`

**What's skipped:**
```
PASS  transcribe: skipped (speech not authorized)
PASS  voice-analytics: skipped (speech not authorized)
```

**Why they're skipped:**

`SFSpeechRecognizer` requires the binary to hold the `com.apple.security.speech-recognition` entitlement. On macOS 26, calling `requestAuthorization:` from a binary **without** this entitlement causes an immediate `__TCC_CRASHING_DUE_TO_PRIVACY_VIOLATION__` abort — there is no graceful fallback. Ad-hoc signing (`codesign -s -`) does not satisfy TCC on macOS 26; a real Developer ID certificate is required.

The binary therefore only checks `authorizationStatus` (no crash) and returns a "not authorized" error, which the test catches and records as a soft PASS.

**How to fix / make these tests run:**

1. Enroll in the Apple Developer Program and obtain a Developer ID Application certificate.
2. Sign the binary with that certificate plus `macos-vision.entitlements` (already present in the repo root with `com.apple.security.speech-recognition`):
   ```bash
   codesign --force --sign "Developer ID Application: <Your Name> (<TeamID>)" \
            --entitlements macos-vision.entitlements \
            .build/debug/macos-vision
   ```
3. Run the binary once to trigger the TCC permission dialog:
   ```bash
   say -o /tmp/t.aiff "test" && .build/debug/macos-vision speech \
       --input /tmp/t.aiff --operation transcribe --output /tmp/t.json
   ```
4. Grant Speech Recognition in the system dialog. The binary will then appear in System Settings → Privacy & Security → Speech Recognition.
5. Subsequent runs of `bash test.sh` will exercise the full `transcribe` and `voice-analytics` paths.

Until a Developer ID certificate is available, these tests soft-skip and count as PASS (non-blocking).