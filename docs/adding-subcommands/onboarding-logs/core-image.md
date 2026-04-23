# Onboarding Log - Core Image

Process notes for adding the `coreimage` subcommand to `macos-vision`,
cross-referencing against `docs/new-subcommand-instructions.md`.

---

## Core Image subcommand (2026-04-17)

### What was implemented

- `Sources/coreimage/main.h` + `Sources/coreimage/main.m` — three operations:
  `apply`, `list-filters`, `list-categories`
- `Sources/coreimage/test.sh` — smoke tests (31/31 passing)
- `cmd/example/subcommand_coreimage.sh` — example script (11 operations)
- `docs/subcommands/core-image.md` — API surface doc
- `Sources/main.m` — import, routing, dispatch, usage text

---

## Step 1: Info Gathering — gaps and notes

**Gap 1 (known from prior logs): Apple docs require JavaScript.**  
The URL in `apple-apis.csv` (`https://developer.apple.com/documentation/CoreImage`)
renders with JavaScript. The `WebFetch` tool returned a "This page requires JavaScript"
error. Use the SDK headers instead:

```bash
SDK=/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks
ls "$SDK/CoreImage.framework/Versions/A/Headers/"
# Use Read tool on individual headers — faster and authoritative
```

Key headers read: `CIFilter.h`, `CIContext.h`.

**Gap 2: Check `Package.swift` before anything else.**  
`CoreImage` was already in `linkerSettings` — no changes needed.
The instructions don't call this out explicitly, but it's the first check to make.

**Gap 3: `setDefaults` is required on macOS, silently broken without it.**  
On iOS, `filterWithName:` sets all inputs to their default values automatically.
On macOS, inputs are **undefined** until you call `[filter setDefaults]`.
Forgetting `setDefaults` produces garbage output with no error — one of the most
surprising Core Image gotchas. The header documents this but it's easy to miss.

**Gap 4: Use-type category tags vs. filter-type category tags.**  
`CIFilter.h` defines two groups of `kCICategoryXxx` constants:

- **Filter-type** (14 categories, e.g. `kCICategoryBlur`, `kCICategoryColorEffect`) —
  describe *what the filter does*. These are the useful categories for `list-filters`.
- **Use-type** (e.g. `kCICategoryBuiltIn`, `kCICategoryStillImage`, `kCICategoryVideo`) —
  describe *where the filter is used*. Including these in `filterNamesInCategories:`
  returns duplicates. Filter only on the 14 filter-type categories.

**Gap 5: Generator/gradient filters have infinite extent.**  
Filters that generate output without an input image (e.g. `CICheckerboardGenerator`,
`CILinearGradient`) produce a `CIImage` with `CGRectInfinite` as their `extent`.
Passing an infinite extent to `PNGRepresentationOfImage:format:colorSpace:options:`
returns nil with no error message. Always clamp to the input image extent (or a fallback
size) before rendering. Detect with:

```objc
if (isinf(renderRect.size.width) || isinf(renderRect.size.height) ||
    isinf(renderRect.origin.x) || isinf(renderRect.origin.y)) { … }
```

**Gap 6: `filterNamesInCategory:` returns duplicates across categories.**  
Calling `filterNamesInCategory:` for each category and concatenating results
produces duplicate filter names (many filters belong to multiple categories).
Use an `NSMutableSet` to de-duplicate, then sort to a stable `NSArray`.

---

## Step 2: Implementation — gaps and notes

**Gap 7: Four places in `main.m` need changes (same as prior logs).**  
The instructions don't mention this. The four locations are:
1. `MVMainEffectiveOperation` — default operation (`apply`)
2. `jsonStem` block — use `inputPath ?: @""` for non-image ops
3. `MVMainResolvedArtifactsDir` — return `outOpt` for `apply`, nil for list-* ops
4. Dispatch block + error message at the bottom

**Gap 8: New args `--filter` and `--filter-params` need two new variables in `main.m`.**  
The existing args (`--model`, `--text`, etc.) are all shared across subcommands.
`--filter` and `--filter-params` are new. They are harmlessly ignored by every other
subcommand because no other dispatch block reads them.

**Gap 9: Exact image output path via `--output <file.png>`.**  
Other image subcommands (segment, face) use `artifactsDir` for all image output.
Core Image's primary use case is producing a single processed image — users expect
`--output result.png` to work like a standard image tool. To support this, the dispatch
block checks if `--output` is neither a directory nor a `.json` file and sets
`processor.outputPath` for the exact path.

**Gap 10: Only `NSNumber` scalar params supported via `--filter-params`.**  
`CIVector`, `CIColor`, and image params require richer types that can't trivially be
expressed as JSON. The current implementation silently ignores non-`NSNumber` values
in the JSON object. This is a known gap — sufficient for the common case (intensity,
radius, scale, brightness, etc.) but not for advanced filters.

---

## Step 3: Testing — gaps and notes

**Gap 11: `grep -qiE "a\|b\|c"` does NOT mean alternation in ERE.**  
In BRE (no `-E`), `\|` is alternation on macOS BSD grep.
In ERE (`-E`), `|` is alternation and `\|` is a **literal pipe character**.
So `grep -qiE "unknown\|filter\|error"` silently matches the literal string
`unknown|filter|error` — not "unknown OR filter OR error".

Two patterns:
- Use `grep -qi "unknown\|filter\|error"` (BRE, no `-E`) for alternation
- Or `grep -qiE "unknown|filter|error"` (ERE, no backslash) for alternation

Both tests failed with `-E` + `\|` until the patterns were fixed. This is the same
category of bug that can silently pass tests (if the error output happened to
contain the literal `|` character).

**Gap 12: `sample_data/input/images/gorilla.jpg` is the best smoke-test image.**  
It's a high-contrast natural scene that makes filter effects visually obvious.
The file was already in `data_files.json` as `EXAMPLE_IMG_GORILLA`. No new sample
data was needed for the `coreimage` subcommand.

---

## Helpful tools / tips for Core Image

| Tool / Tip | Use |
|------------|-----|
| `Read $SDK/CoreImage.framework/Versions/A/Headers/CIFilter.h` | All category constants, input key constants, `CIFilter` API |
| `[CIFilter filterNamesInCategory:kCICategoryBlur]` | Enumerate built-in filters by category |
| `[filter.attributes objectForKey:@"inputIntensity"][kCIAttributeDefault]` | Get default value for any param |
| `filter.inputKeys` | Check if a filter supports `inputImage` before loading the image |
| `isinf(outputImage.extent.size.width)` | Detect generator filters with infinite extent |
| `[filter setDefaults]` | **Always call this on macOS** — inputs are undefined by default |
| `CIContext PNGRepresentationOfImage:format:colorSpace:options:` | Consistent with `segment` subcommand; no separate file-write step needed |
| `NSMutableSet` + `allObjects` + `sortedArrayUsingSelector:` | De-duplicate filter names across categories |
| `jq '.result.by_category | keys'` | Quick check that category grouping worked |
| `swift build 2>&1 \| grep -E "warning:|error:"` | Quick build validation |
