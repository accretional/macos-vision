#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// ─────────────────────────────────────────────────────────────────────────────
// SVGStyle — stroke / fill / strokeWidth for any shape
// ─────────────────────────────────────────────────────────────────────────────

@interface SVGStyle : NSObject <NSCopying>

/// CSS color string or @"none"
@property (nonatomic, copy) NSString *stroke;
/// CSS color string or @"none"
@property (nonatomic, copy) NSString *fill;
@property (nonatomic, assign) CGFloat strokeWidth;

+ (instancetype)styleWithStroke:(NSString *)stroke fill:(NSString *)fill strokeWidth:(CGFloat)strokeWidth;

// Default factory styles (usable without a full palette)
+ (instancetype)defaultBoxStyle;      // red stroke, no fill
+ (instancetype)defaultPointStyle;    // green fill, no stroke
+ (instancetype)defaultLineStyle;     // yellow stroke, no fill
+ (instancetype)defaultPolygonStyle;  // cyan stroke, semi-transparent fill

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGPalette — per-operation color scheme
// ─────────────────────────────────────────────────────────────────────────────

@interface SVGPalette : NSObject

// Face operations
@property (nonatomic, strong) SVGStyle *faceBox;
@property (nonatomic, strong) SVGStyle *faceLandmarkEye;
@property (nonatomic, strong) SVGStyle *faceLandmarkLip;
@property (nonatomic, strong) SVGStyle *faceLandmarkNose;
@property (nonatomic, strong) SVGStyle *faceLandmarkBrow;
@property (nonatomic, strong) SVGStyle *faceLandmarkContour;
@property (nonatomic, strong) SVGStyle *faceLandmarkDot;

// Body / human
@property (nonatomic, strong) SVGStyle *humanBox;
@property (nonatomic, strong) SVGStyle *poseJoint;
@property (nonatomic, strong) SVGStyle *poseBone;

// Animal
@property (nonatomic, strong) SVGStyle *animalJoint;
@property (nonatomic, strong) SVGStyle *animalBox;

// Classify
@property (nonatomic, strong) SVGStyle *objectBox;
@property (nonatomic, strong) SVGStyle *rectangleQuad;

// Track
@property (nonatomic, strong) SVGStyle *trajectoryPath;
@property (nonatomic, strong) SVGStyle *trajectoryPoint;

// Horizon
@property (nonatomic, strong) SVGStyle *horizonLine;

// Labels
@property (nonatomic, assign) BOOL showLabels;             // default YES; set NO to suppress all text labels
@property (nonatomic, copy) NSString *labelColor;          // CSS color for text fill
@property (nonatomic, assign) CGFloat labelFontSize;       // pixels — for box / region labels
@property (nonatomic, assign) CGFloat smallLabelFontSize;  // pixels — for per-joint / per-point labels

+ (instancetype)defaultPalette;

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGShape — base class; all coordinates are normalized 0–1, top-left origin
// ─────────────────────────────────────────────────────────────────────────────

@interface SVGShape : NSObject

@property (nonatomic, strong, nullable) SVGStyle *style;

/// Produce an SVG element string. Implementations scale normalized coords to
/// pixel coords using width × height.
- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height;

@end

// ─────────────────────────────────────────────────────────────────────────────
// Concrete shape subclasses
// ─────────────────────────────────────────────────────────────────────────────

/// A single dot rendered as <circle>
@interface SVGPointShape : SVGShape
@property (nonatomic, assign) CGPoint center;  // normalized, top-left
@property (nonatomic, assign) CGFloat radius;  // pixels (not normalized)
+ (instancetype)shapeWithCenter:(CGPoint)center radius:(CGFloat)radius style:(SVGStyle *)style;
@end

/// An axis-aligned bounding box rendered as <rect>
@interface SVGRectShape : SVGShape
@property (nonatomic, assign) CGRect rect;  // normalized, top-left origin
+ (instancetype)shapeWithRect:(CGRect)rect style:(SVGStyle *)style;
@end

/// A closed polygon rendered as <polygon>
@interface SVGPolygonShape : SVGShape
@property (nonatomic, copy) NSArray<NSValue *> *points;  // NSPoint values, normalized top-left
+ (instancetype)shapeWithPoints:(NSArray<NSValue *> *)points style:(SVGStyle *)style;
@end

/// An open polyline rendered as <polyline>
@interface SVGPolylineShape : SVGShape
@property (nonatomic, copy) NSArray<NSValue *> *points;  // NSPoint values, normalized top-left
+ (instancetype)shapeWithPoints:(NSArray<NSValue *> *)points style:(SVGStyle *)style;
@end

/// A line segment rendered as <line>
@interface SVGLineShape : SVGShape
@property (nonatomic, assign) CGPoint start;  // normalized, top-left
@property (nonatomic, assign) CGPoint end;    // normalized, top-left
+ (instancetype)shapeWithStart:(CGPoint)start end:(CGPoint)end style:(SVGStyle *)style;
@end

/// A text label rendered as <text> with outline for readability
@interface SVGTextShape : SVGShape
/// Normalized position; the text baseline is placed at position.y + fontSize/height
@property (nonatomic, assign) CGPoint position;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *color;    // CSS color for text fill
@property (nonatomic, assign) CGFloat fontSize; // pixels
+ (instancetype)shapeWithPosition:(CGPoint)position
                             text:(NSString *)text
                            color:(NSString *)color
                         fontSize:(CGFloat)fontSize;
@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGOverlay — generic SVG generator; embeds image as base64
// ─────────────────────────────────────────────────────────────────────────────

@interface SVGOverlay : NSObject

/// Pass nil to render shapes on a white canvas.
- (instancetype)initWithImagePath:(nullable NSString *)imagePath;

- (void)addShape:(SVGShape *)shape;
- (void)addShapes:(NSArray<SVGShape *> *)shapes;

/// Returns the complete SVG document as a string, or nil on error.
- (nullable NSString *)generateSVGWithError:(NSError **)error;

/// Writes the SVG to outputPath. Creates intermediate directories as needed.
- (BOOL)writeToPath:(NSString *)outputPath error:(NSError **)error;

@end

// ─────────────────────────────────────────────────────────────────────────────
// VisionShapeBuilder — converts Vision JSON output → SVGShape array
// ─────────────────────────────────────────────────────────────────────────────

@interface VisionShapeBuilder : NSObject

/// Build shapes using the default palette.
+ (NSArray<SVGShape *> *)shapesFromVisionJSON:(NSDictionary *)json;

/// Build shapes using a custom palette.
+ (NSArray<SVGShape *> *)shapesFromVisionJSON:(NSDictionary *)json
                                      palette:(SVGPalette *)palette;

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGProcessor — CLI-facing processor for `macos-vision svg`
// ─────────────────────────────────────────────────────────────────────────────

@interface SVGProcessor : NSObject

/// Override image path. If nil, falls back to info.filepath inside the JSON.
@property (nonatomic, copy, nullable) NSString *img;

/// Whether to render text labels on shapes. Default YES.
@property (nonatomic, assign) BOOL showLabels;

/// Path to a Vision JSON file produced by any subcommand.
@property (nonatomic, copy, nullable) NSString *jsonPath;

/// Output directory. If nil, writes SVG alongside the JSON file.
@property (nonatomic, copy, nullable) NSString *output;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
