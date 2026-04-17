# Onboarding log — SoundAnalysis (`sna` subcommand)

Date: 2026-04-16  
Framework: `SoundAnalysis` (`SNAudioFileAnalyzer`, `SNClassifySoundRequest`, …)  
Subcommand: `sna`  
Operations: `classify`, `classify-custom`, `list-labels`

---

## Process followed

### Step 1 — Info gathering

1. Located `SoundAnalysis` in `docs/apple-apis.csv` → URL `https://developer.apple.com/documentation/SoundAnalysis`
2. Apple doc page requires JavaScript rendering and cannot be fetched by CLI tools. Used SDK headers directly instead (see Gap 1 below).
3. Checked `Package.swift` — `SoundAnalysis` was already linked. No change needed.
4. Checked `Sources/audio/main.m` — it already uses `SNClassifySoundRequest` for `classify` and `detect`. Read it to understand the observer pattern and window configuration before starting (see Gap 2 below).
5. Wrote `docs/subcommands/sound-analysis.md` covering all classes, properties, and availability.

### Step 2 — Implementation

- `Sources/sna/main.h` — `SNAProcessor` interface
- `Sources/sna/main.m` — `SNAObserver`, `classify`, `classify-custom`, `list-labels`
- `Sources/main.m` — wired in across four locations (imports, `MVMainEffectiveOperation`, `MVMainJsonInDirectory`, jsonStem block, dispatch block, error message)
- No new flags added to `main.m` — all needed flags (`--topk`, `--classify-window`, `--classify-overlap`, `--model`) were already parsed.

### Step 3 — Testing

- `Sources/sna/test.sh` — 25/25 passing
- `cmd/example/subcommand_sna.sh` — runs all operations; produces valid JSON output
- Added `window_duration_s` to the result after observing that the default was non-obvious (discovered during testing — see Gap 4)

---

## Gaps found in `docs/new-subcommand-instructions.md`

### Gap 1: Apple docs require JavaScript; use SDK headers instead

The instructions say to "fetch the details from the document webpage" from the URL in `apple-apis.csv`. Those pages render via JavaScript and cannot be fetched with any plain HTTP tool. **The SDK headers are the authoritative source and should be used first:**

```bash
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks
ls "$SDK/SoundAnalysis.framework/Versions/A/Headers/"
cat "$SDK/SoundAnalysis.framework/Versions/A/Headers/SNClassifySoundRequest.h"
```

The headers include full docstrings, availability annotations, and deprecation notices — more reliable than the web page.

---

### Gap 2: Check all existing subcommands for prior usage of the framework

The instructions say to look at "two other subcommands as reference" for *implementation style*, but they don't say to check whether any existing subcommand *already uses the target framework*.

`audio/main.m` already used `SNClassifySoundRequest`, `SNAudioFileAnalyzer`, and the observer pattern. Reading it before starting:
- Revealed the exact observer pattern (implementing `SNResultsObserving`)
- Showed the `@available(macOS 12.0, *)` gate required for `SNClassifierIdentifierVersion1`
- Provided working window/overlap configuration code
- Clarified what was genuinely new in the dedicated subcommand vs already shipped

**Rule:** Before implementing, `grep -r "import <FrameworkName"` across all Sources to find prior usage.

---

### Gap 3: `--model` and window/overlap flags already exist in `main.m`

The instructions don't mention checking which flags are already parsed in `main.m`. For `sna`, **four flags were available for free** with no changes to the arg-parsing loop:

| Flag | Variable in `main.m` | Used by |
|------|--------------------|---------|
| `--model` | `nlModelPath` | `nl` (NLModel), now also `sna` |
| `--classify-window` | `classifyWindow` / `classifyWindowSet` | `audio`, now also `sna` |
| `--classify-overlap` | `classifyOverlap` / `classifyOverlapSet` | `audio`, now also `sna` |
| `--topk` | `topk` | `audio`, `nl`, now also `sna` |

**Rule:** Before adding new flags, scan `main.m`'s arg-parsing loop for anything that matches your subcommand's needs.

---

### Gap 4: The built-in classifier has a ~3 second minimum audio requirement

This is not documented anywhere in the framework headers. Discovered only during testing when short `say`-generated audio (< 3 s) produced zero windows with no error — the analyzer succeeded but the observer was never called.

**Root cause:** `SNClassifierIdentifierVersion1` uses a 3-second default window duration. An audio file shorter than one window produces no output. The analyzer completes successfully and returns an empty results array — no error, no warning.

**Impact on test scripts:** Any `say` phrase used for sound classification tests must be long enough to exceed the window. A one-sentence phrase (~2 s) is too short; three sentences (~6–8 s) is reliable.

**What to include in the result:** Always include `window_duration_s` in the JSON output (read from `request.windowDuration` after initialization) so callers know what window the model used. This is essential context for interpreting empty results.

---

### Gap 5: `grep` with `--` prefixed patterns fails on macOS BSD grep

When writing test scripts, a `grep -qiE "--input|..."` pattern fails because BSD `grep` interprets `--input` as a flag, not a literal string:

```bash
# BAD (crashes on macOS):
echo "$err" | grep -qiE "--input|audio|error"

# GOOD (remove the -- prefix from the pattern):
echo "$err" | grep -qiE "input|audio|error"
```

This is specific to macOS BSD grep (vs GNU grep on Linux). The fix is simply to not start pattern alternatives with `--`.

---

### Gap 6: `main.m` wiring requires four separate edit locations

The instructions say "Wire into `Sources/main.m` and `docs/cli-reference.md`" but don't enumerate what "wire in" means. For every subcommand, `main.m` needs changes in exactly four places:

1. **Import** — `#import "sna/main.h"` at the top
2. **`MVMainEffectiveOperation`** — add default operation for the subcommand
3. **`MVMainJsonInDirectory` / `jsonStem` block** — how the output JSON filename stem is derived
4. **Dispatch block + error message** — the actual `if/else if` that instantiates and runs the processor

Missing any of these causes silent misbehavior (wrong output path, wrong default op) rather than a build error.

---

## Helpful tools / tips

| Tool / tip | Use |
|-----------|-----|
| `cat "$SDK/<Framework>.framework/Versions/A/Headers/*.h"` | Read all headers at once; faster than web docs |
| `grep -rn "SoundAnalysis\|SNClassify" Sources/` | Find all existing framework usage across the codebase |
| `afinfo <file> 2>/dev/null \| grep duration` | Check audio duration before running classify; clip must be > window duration |
| `say -o out.aiff "long phrase with 3+ sentences"` | Generate synthetic test audio reliably; use ≥ 3 full sentences for SoundAnalysis |
| `jq '{windows: (.result.windows\|length), window_s: .result.window_duration_s}' out.json` | Quick sanity check on classify output |
| `"$BINARY" sna --operation list-labels` | Verify framework is working without any audio file; use as the first smoke test |
| `@available(macOS 12.0, *)` gate | Required for `SNClassifierIdentifierVersion1` and `knownClassifications` |
| `request.windowDuration` after init | Read this to discover the model's effective window duration before running analysis |
