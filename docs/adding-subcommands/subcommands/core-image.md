# CoreImage subcommand

SDK headers: `$SDK/CoreImage.framework/Versions/A/Headers/`  
Framework: `CoreImage` (already linked in `Package.swift`)  
Availability: macOS 10.15+

---

## Operations implemented

| Operation | Functionality | Flags | API used |
|-----------|--------------|-------|----------|
| `apply-filter` | Apply any built-in `CIFilter` by name; scalar params overridable via JSON | `--input`, `--filter-name`, `--filter-params`, `--format`, `--artifacts-dir`, `--output` | `CIFilter`, `CIContext` render methods |
| `suggest-filters` | Ask Apple's algorithm which filters to apply to a photo and with what values; optionally render the result | `--input`, `--apply`, `--format`, `--artifacts-dir`, `--output` | `CIImage.autoAdjustmentFiltersWithOptions:` |
| `list-filters` | List all built-in filter names grouped by category; `--category-only` returns category metadata instead | `--category-only` | `CIFilter.filterNamesInCategory:` |

### Output formats (`--format`)

Applies to `apply-filter` and `suggest-filters --apply`. Default: `png`.

| Value | API | Min macOS |
|-------|-----|-----------|
| `png` | `PNGRepresentationOfImage:format:colorSpace:options:` | 10.13 |
| `jpg` | `JPEGRepresentationOfImage:colorSpace:options:` | 10.12 |
| `heif` | `HEIFRepresentationOfImage:format:colorSpace:options:` | 10.13.4 |
| `tiff` | `TIFFRepresentationOfImage:format:colorSpace:options:` | 10.12 |

---

## Key classes

| Class | Purpose | Header |
|-------|---------|--------|
| `CIFilter` | Image processor; create with `+filterWithName:`; must call `setDefaults` on macOS before setting params | `CIFilter.h` |
| `CIImage` | Lazy image graph node; input or output of filters; exposes `autoAdjustmentFiltersWithOptions:` | `CIImage.h` |
| `CIContext` | Evaluation context; renders `CIImage` to data via format-specific methods | `CIContext.h` |
| `CIColor` | Color value for filter parameters | `CIColor.h` |
| `CIVector` | 1–4 element vector for filter parameters | `CIVector.h` |

---

## Filter categories

The 14 primary categories used by `list-filters` (use-type tags like `kCICategoryBuiltIn` are excluded):

`kCICategoryDistortionEffect` · `kCICategoryGeometryAdjustment` · `kCICategoryCompositeOperation` · `kCICategoryHalftoneEffect` · `kCICategoryColorAdjustment` · `kCICategoryColorEffect` · `kCICategoryTransition` · `kCICategoryTileEffect` · `kCICategoryGenerator` · `kCICategoryReduction` · `kCICategoryGradient` · `kCICategoryStylize` · `kCICategorySharpen` · `kCICategoryBlur`

---

## Notes

- `CIFilter.setDefaults` is required on macOS — unlike iOS, filter inputs are undefined until it is called.
- Generator and gradient filters produce `CGRectInfinite` output extent; the implementation clamps to the input image extent or `1024×1024` when no input is provided.
- `--filter-params` only accepts `NSNumber` scalar values. `CIVector`, `CIColor`, and image-type params are not supported via JSON.
- `suggest-filters` without `--apply` returns the filter list and params only — no image is written.
