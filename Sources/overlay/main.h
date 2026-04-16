#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// ─────────────────────────────────────────────────────────────────────────────
// SVGShape — base class; coordinates are normalized 0–1, top-left origin.
//
// Each shape carries semantic metadata used to emit interactive SVG elements:
//   cssClass   → CSS class applied to the element (controls hover/selection style)
//   layerID    → <g id="…"> group the shape belongs to (for layer toggling)
//   label      → data-label attribute and <title> tooltip text (bounding boxes also use
//                labels[0].identifier from JSON when present, e.g. classify animals)
//   confidence → data-confidence attribute (0–1); omitted if nil
// ─────────────────────────────────────────────────────────────────────────────

@interface SVGShape : NSObject
@property (nonatomic, copy, nullable) NSString *cssClass;
@property (nonatomic, copy, nullable) NSString *layerID;
@property (nonatomic, copy, nullable) NSString *label;
@property (nonatomic, strong, nullable) NSNumber *confidence;
- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height;
@end

@interface SVGPointShape : SVGShape
@property (nonatomic, assign) CGPoint center;
@property (nonatomic, assign) CGFloat radius;
+ (instancetype)shapeWithCenter:(CGPoint)center radius:(CGFloat)radius;
@end

@interface SVGRectShape : SVGShape
@property (nonatomic, assign) CGRect rect;
+ (instancetype)shapeWithRect:(CGRect)rect;
@end

@interface SVGPolygonShape : SVGShape
@property (nonatomic, copy) NSArray<NSValue *> *points;
+ (instancetype)shapeWithPoints:(NSArray<NSValue *> *)points;
@end

@interface SVGLineShape : SVGShape
@property (nonatomic, assign) CGPoint start;
@property (nonatomic, assign) CGPoint end;
+ (instancetype)shapeWithStart:(CGPoint)start end:(CGPoint)end;
@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGOverlay — embeds image as base64 + interactive annotation layers.
//
// The generated SVG is self-contained: it includes an embedded <style> block
// (hover/selection CSS) and a <script> block (click → info panel, layer toggle).
// It works as a standalone file in any browser and can be embedded via <object>
// in a host page, which can reach its contentDocument to drive layer toggles.
// ─────────────────────────────────────────────────────────────────────────────

@interface SVGOverlay : NSObject
- (instancetype)initWithImagePath:(nullable NSString *)imagePath;
- (void)addShape:(SVGShape *)shape;
- (void)addShapes:(NSArray<SVGShape *> *)shapes;
- (nullable NSString *)generateSVGWithError:(NSError **)error;
- (BOOL)writeToPath:(NSString *)outputPath error:(NSError **)error;
@end

// ─────────────────────────────────────────────────────────────────────────────
// OverlayProcessor — CLI-facing processor for `macos-vision overlay`
// ─────────────────────────────────────────────────────────────────────────────

@interface OverlayProcessor : NSObject

/// Path to a Vision JSON file produced by any subcommand (required).
@property (nonatomic, copy, nullable) NSString *jsonPath;
/// Override image path. If nil, falls back to info.filepath inside the JSON.
@property (nonatomic, copy, nullable) NSString *inputPath;
/// Path to the .svg file to write. If nil, writes <jsonBasename>.svg next to the JSON.
@property (nonatomic, copy, nullable) NSString *svgOutput;
/// JSON envelope written to this file, or stdout if nil.
@property (nonatomic, copy, nullable) NSString *jsonOutput;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
