#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>

NS_ASSUME_NONNULL_BEGIN

// ─────────────────────────────────────────────────────────────────────────────
// SVGStyle — stroke / fill / strokeWidth for any shape
// ─────────────────────────────────────────────────────────────────────────────

@interface SVGStyle : NSObject <NSCopying>

@property (nonatomic, copy) NSString *stroke;
@property (nonatomic, copy) NSString *fill;
@property (nonatomic, assign) CGFloat strokeWidth;

+ (instancetype)styleWithStroke:(NSString *)stroke fill:(NSString *)fill strokeWidth:(CGFloat)strokeWidth;

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGShape — base class; coordinates are normalized 0–1, top-left origin
// ─────────────────────────────────────────────────────────────────────────────

@interface SVGShape : NSObject
@property (nonatomic, strong, nullable) SVGStyle *style;
- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height;
@end

@interface SVGPointShape : SVGShape
@property (nonatomic, assign) CGPoint center;
@property (nonatomic, assign) CGFloat radius;
+ (instancetype)shapeWithCenter:(CGPoint)center radius:(CGFloat)radius style:(SVGStyle *)style;
@end

@interface SVGRectShape : SVGShape
@property (nonatomic, assign) CGRect rect;
+ (instancetype)shapeWithRect:(CGRect)rect style:(SVGStyle *)style;
@end

@interface SVGPolygonShape : SVGShape
@property (nonatomic, copy) NSArray<NSValue *> *points;
+ (instancetype)shapeWithPoints:(NSArray<NSValue *> *)points style:(SVGStyle *)style;
@end

@interface SVGPolylineShape : SVGShape
@property (nonatomic, copy) NSArray<NSValue *> *points;
+ (instancetype)shapeWithPoints:(NSArray<NSValue *> *)points style:(SVGStyle *)style;
@end

@interface SVGLineShape : SVGShape
@property (nonatomic, assign) CGPoint start;
@property (nonatomic, assign) CGPoint end;
+ (instancetype)shapeWithStart:(CGPoint)start end:(CGPoint)end style:(SVGStyle *)style;
@end

@interface SVGTextShape : SVGShape
@property (nonatomic, assign) CGPoint position;
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSString *color;
@property (nonatomic, assign) CGFloat fontSize;
+ (instancetype)shapeWithPosition:(CGPoint)position
                             text:(NSString *)text
                            color:(NSString *)color
                         fontSize:(CGFloat)fontSize;
@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGOverlay — embeds image as base64, renders shapes on top
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
@property (nonatomic, copy, nullable) NSString *img;
/// Output directory. If nil, writes SVG alongside the JSON file.
@property (nonatomic, copy, nullable) NSString *output;
/// Show labels: boundingBox → name + confidence; landmarks → group name.
@property (nonatomic, assign) BOOL showLabels;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
