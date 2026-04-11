#import "main.h"
#import <Cocoa/Cocoa.h>
#import <math.h>

static NSString * const SVGErrorDomain = @"SVGError";
typedef NS_ENUM(NSInteger, SVGErrorCode) {
    SVGErrorMissingInput    = 1,
    SVGErrorImageLoadFailed = 2,
    SVGErrorWriteFailed     = 3,
};

// ─────────────────────────────────────────────────────────────────────────────
// Helpers
// ─────────────────────────────────────────────────────────────────────────────

static NSString *svgEscape(NSString *s) {
    s = [s stringByReplacingOccurrencesOfString:@"&"  withString:@"&amp;"];
    s = [s stringByReplacingOccurrencesOfString:@"<"  withString:@"&lt;"];
    s = [s stringByReplacingOccurrencesOfString:@">"  withString:@"&gt;"];
    s = [s stringByReplacingOccurrencesOfString:@"\"" withString:@"&quot;"];
    return s;
}

static NSString *styleAttrs(SVGStyle *style) {
    if (!style) return @"";
    return [NSString stringWithFormat:@"stroke=\"%@\" stroke-width=\"%.1f\" fill=\"%@\"",
            style.stroke, style.strokeWidth, style.fill];
}

static NSString *pointsString(NSArray<NSValue *> *points, CGFloat w, CGFloat h) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:points.count];
    for (NSValue *v in points) {
        NSPoint p = v.pointValue;
        [parts addObject:[NSString stringWithFormat:@"%.2f,%.2f", p.x * w, p.y * h]];
    }
    return [parts componentsJoinedByString:@" "];
}

// ─────────────────────────────────────────────────────────────────────────────
// SVGStyle
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGStyle

+ (instancetype)styleWithStroke:(NSString *)stroke fill:(NSString *)fill strokeWidth:(CGFloat)strokeWidth {
    SVGStyle *s = [[self alloc] init];
    s.stroke = stroke;
    s.fill = fill;
    s.strokeWidth = strokeWidth;
    return s;
}

+ (instancetype)defaultBoxStyle {
    return [self styleWithStroke:@"#FF4444" fill:@"none" strokeWidth:2.0];
}

+ (instancetype)defaultPointStyle {
    return [self styleWithStroke:@"none" fill:@"#00FF00" strokeWidth:0.0];
}

+ (instancetype)defaultLineStyle {
    return [self styleWithStroke:@"#FFFF00" fill:@"none" strokeWidth:2.0];
}

+ (instancetype)defaultPolygonStyle {
    return [self styleWithStroke:@"#00FFFF" fill:@"rgba(0,255,255,0.1)" strokeWidth:1.5];
}

- (id)copyWithZone:(NSZone *)zone {
    SVGStyle *copy = [[SVGStyle allocWithZone:zone] init];
    copy.stroke = self.stroke;
    copy.fill = self.fill;
    copy.strokeWidth = self.strokeWidth;
    return copy;
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGShape base
// (SVGPalette removed — overlay uses hardcoded styles via generic walker)
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGShape

- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height {
    return @"";
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGPointShape
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGPointShape

+ (instancetype)shapeWithCenter:(CGPoint)center radius:(CGFloat)radius style:(SVGStyle *)style {
    SVGPointShape *s = [[self alloc] init];
    s.center = center;
    s.radius = radius;
    s.style  = style;
    return s;
}

- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height {
    CGFloat cx = self.center.x * width;
    CGFloat cy = self.center.y * height;
    return [NSString stringWithFormat:
        @"<circle cx=\"%.2f\" cy=\"%.2f\" r=\"%.1f\" %@/>",
        cx, cy, self.radius, styleAttrs(self.style)];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGRectShape
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGRectShape

+ (instancetype)shapeWithRect:(CGRect)rect style:(SVGStyle *)style {
    SVGRectShape *s = [[self alloc] init];
    s.rect  = rect;
    s.style = style;
    return s;
}

- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height {
    CGFloat x = self.rect.origin.x    * width;
    CGFloat y = self.rect.origin.y    * height;
    CGFloat w = self.rect.size.width  * width;
    CGFloat h = self.rect.size.height * height;
    return [NSString stringWithFormat:
        @"<rect x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\" %@/>",
        x, y, w, h, styleAttrs(self.style)];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGPolygonShape
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGPolygonShape

+ (instancetype)shapeWithPoints:(NSArray<NSValue *> *)points style:(SVGStyle *)style {
    SVGPolygonShape *s = [[self alloc] init];
    s.points = points;
    s.style  = style;
    return s;
}

- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height {
    if (self.points.count < 2) return @"";
    return [NSString stringWithFormat:
        @"<polygon points=\"%@\" %@/>",
        pointsString(self.points, width, height), styleAttrs(self.style)];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGPolylineShape
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGPolylineShape

+ (instancetype)shapeWithPoints:(NSArray<NSValue *> *)points style:(SVGStyle *)style {
    SVGPolylineShape *s = [[self alloc] init];
    s.points = points;
    s.style  = style;
    return s;
}

- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height {
    if (self.points.count < 2) return @"";
    return [NSString stringWithFormat:
        @"<polyline points=\"%@\" %@/>",
        pointsString(self.points, width, height), styleAttrs(self.style)];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGLineShape
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGLineShape

+ (instancetype)shapeWithStart:(CGPoint)start end:(CGPoint)end style:(SVGStyle *)style {
    SVGLineShape *s = [[self alloc] init];
    s.start = start;
    s.end   = end;
    s.style = style;
    return s;
}

- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height {
    return [NSString stringWithFormat:
        @"<line x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\" %@/>",
        self.start.x * width, self.start.y * height,
        self.end.x   * width, self.end.y   * height,
        styleAttrs(self.style)];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGTextShape
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGTextShape

+ (instancetype)shapeWithPosition:(CGPoint)position text:(NSString *)text color:(NSString *)color fontSize:(CGFloat)fontSize {
    SVGTextShape *s = [[self alloc] init];
    s.position = position;
    s.text     = text;
    s.color    = color;
    s.fontSize = fontSize;
    return s;
}

- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height {
    CGFloat px = self.position.x * width;
    // Offset by fontSize so position is the top-left, not baseline
    CGFloat py = self.position.y * height + self.fontSize;
    return [NSString stringWithFormat:
        @"<text x=\"%.2f\" y=\"%.2f\" font-family=\"sans-serif\" font-size=\"%.0f\" "
         "fill=\"%@\" stroke=\"#000000\" stroke-width=\"2.5\" paint-order=\"stroke fill\">%@</text>",
        px, py, self.fontSize, svgEscape(self.color), svgEscape(self.text)];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGOverlay
// ─────────────────────────────────────────────────────────────────────────────

@interface SVGOverlay ()
@property (nonatomic, copy, nullable) NSString *imagePath;
@property (nonatomic, strong) NSMutableArray<SVGShape *> *shapes;
@end

@implementation SVGOverlay

- (instancetype)initWithImagePath:(nullable NSString *)imagePath {
    if ((self = [super init])) {
        _imagePath = imagePath;
        _shapes = [NSMutableArray array];
    }
    return self;
}

- (void)addShape:(SVGShape *)shape {
    [_shapes addObject:shape];
}

- (void)addShapes:(NSArray<SVGShape *> *)shapes {
    [_shapes addObjectsFromArray:shapes];
}

- (nullable NSString *)generateSVGWithError:(NSError **)error {
    // ── determine image dimensions ────────────────────────────────────────────
    CGFloat imgWidth = 800, imgHeight = 600; // fallback canvas size
    NSString *b64 = nil;
    NSString *mimeType = @"image/png";

    if (self.imagePath.length > 0 && [[NSFileManager defaultManager] fileExistsAtPath:self.imagePath]) {
        NSImage *nsImg = [[NSImage alloc] initByReferencingFile:self.imagePath];
        if (nsImg) {
            imgWidth  = nsImg.size.width;
            imgHeight = nsImg.size.height;
        }
        NSData *imgData = [NSData dataWithContentsOfFile:self.imagePath];
        if (imgData) {
            b64 = [imgData base64EncodedStringWithOptions:0];
            mimeType = [self mimeTypeForExtension:[self.imagePath.pathExtension lowercaseString]];
        }
    }

    // ── build SVG ─────────────────────────────────────────────────────────────
    NSMutableString *svg = [NSMutableString string];
    [svg appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    [svg appendFormat:@"<svg xmlns=\"http://www.w3.org/2000/svg\" "
                       "width=\"%.0f\" height=\"%.0f\" viewBox=\"0 0 %.0f %.0f\">\n",
                       imgWidth, imgHeight, imgWidth, imgHeight];

    if (b64) {
        [svg appendFormat:@"  <image href=\"data:%@;base64,%@\" "
                           "x=\"0\" y=\"0\" width=\"%.0f\" height=\"%.0f\" preserveAspectRatio=\"none\"/>\n",
                           mimeType, b64, imgWidth, imgHeight];
    } else {
        [svg appendFormat:@"  <rect x=\"0\" y=\"0\" width=\"%.0f\" height=\"%.0f\" fill=\"#FFFFFF\"/>\n",
                           imgWidth, imgHeight];
    }

    for (SVGShape *shape in self.shapes) {
        NSString *elem = [shape svgElementForImageWidth:imgWidth height:imgHeight];
        if (elem.length > 0) {
            [svg appendFormat:@"  %@\n", elem];
        }
    }

    [svg appendString:@"</svg>\n"];
    return svg;
}

- (BOOL)writeToPath:(NSString *)outputPath error:(NSError **)error {
    NSString *dir = [outputPath stringByDeletingLastPathComponent];
    if (dir.length > 0) {
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:nil];
    }
    NSString *svg = [self generateSVGWithError:error];
    if (!svg) return NO;
    if (![svg writeToFile:outputPath atomically:YES encoding:NSUTF8StringEncoding error:error]) return NO;
    printf("SVG saved to: %s\n", outputPath.UTF8String);
    return YES;
}

- (NSString *)mimeTypeForExtension:(NSString *)ext {
    NSDictionary *map = @{
        @"jpg":  @"image/jpeg",
        @"jpeg": @"image/jpeg",
        @"png":  @"image/png",
        @"gif":  @"image/gif",
        @"bmp":  @"image/bmp",
        @"tiff": @"image/tiff",
        @"tif":  @"image/tiff",
        @"webp": @"image/webp",
    };
    return map[ext] ?: @"image/png";
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// Generic JSON → shapes walker
// ─────────────────────────────────────────────────────────────────────────────

static NSString *OVSingularize(NSString *key) {
    if ([key hasSuffix:@"ies"] && key.length > 3)
        return [[key substringToIndex:key.length - 3] stringByAppendingString:@"y"];
    if ([key hasSuffix:@"s"] && key.length > 1)
        return [key substringToIndex:key.length - 1];
    return key;
}

static NSArray<SVGShape *> *OVShapesFromJSON(NSDictionary *json, BOOL showLabels) {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];

    SVGStyle *boxStyle  = [SVGStyle styleWithStroke:@"#FF4444" fill:@"none"                   strokeWidth:2.0];
    SVGStyle *polyStyle = [SVGStyle styleWithStroke:@"#00FFFF" fill:@"rgba(0,255,255,0.08)"   strokeWidth:1.5];
    SVGStyle *dotStyle  = [SVGStyle styleWithStroke:@"none"    fill:@"#FFFF44"                strokeWidth:0.0];
    SVGStyle *singleDot = [SVGStyle styleWithStroke:@"none"    fill:@"#00FF88"                strokeWidth:0.0];

    NSSet *skip = [NSSet setWithObjects:@"info", @"operation", nil];

    for (NSString *topKey in json) {
        if ([skip containsObject:topKey]) continue;
        NSArray *elements = json[topKey];
        if (![elements isKindOfClass:[NSArray class]]) continue;

        NSString *elementName = OVSingularize(topKey);

        for (NSDictionary *element in elements) {
            if (![element isKindOfClass:[NSDictionary class]]) continue;

            // ── boundingBox ───────────────────────────────────────────────────
            NSDictionary *bb = element[@"boundingBox"];
            if ([bb isKindOfClass:[NSDictionary class]]) {
                CGRect r = CGRectMake([bb[@"x"] doubleValue], [bb[@"y"] doubleValue],
                                      [bb[@"width"] doubleValue], [bb[@"height"] doubleValue]);
                [shapes addObject:[SVGRectShape shapeWithRect:r style:boxStyle]];
                if (showLabels) {
                    NSMutableString *label = [elementName mutableCopy];
                    id conf = element[@"confidence"];
                    if ([conf isKindOfClass:[NSNumber class]])
                        [label appendFormat:@" %.2f", [conf doubleValue]];
                    CGPoint pos = CGPointMake(r.origin.x, r.origin.y);
                    [shapes addObject:[SVGTextShape shapeWithPosition:pos text:label
                                                               color:@"#FFFFFF" fontSize:13.0]];
                }
            }

            // ── landmarks ─────────────────────────────────────────────────────
            NSDictionary *landmarks = element[@"landmarks"];
            if ([landmarks isKindOfClass:[NSDictionary class]]) {
                for (NSString *groupName in landmarks) {
                    NSArray *pts = landmarks[groupName];
                    if (![pts isKindOfClass:[NSArray class]] || pts.count == 0) continue;
                    NSMutableArray<NSValue *> *nspts = [NSMutableArray arrayWithCapacity:pts.count];
                    for (NSDictionary *p in pts)
                        [nspts addObject:[NSValue valueWithPoint:
                            NSMakePoint([p[@"x"] doubleValue], [p[@"y"] doubleValue])]];
                    if (nspts.count == 1) {
                        [shapes addObject:[SVGPointShape shapeWithCenter:nspts[0].pointValue
                                                                  radius:3.0 style:singleDot]];
                    } else {
                        [shapes addObject:[SVGPolygonShape shapeWithPoints:nspts style:polyStyle]];
                        if (showLabels) {
                            double sx = 0, sy = 0;
                            for (NSValue *v in nspts) { sx += v.pointValue.x; sy += v.pointValue.y; }
                            CGPoint c = CGPointMake(sx / nspts.count + 0.012, sy / nspts.count - 0.012);
                            [shapes addObject:[SVGTextShape shapeWithPosition:c text:groupName
                                                                       color:@"#FFFFFF" fontSize:10.0]];
                        }
                    }
                }
                continue; // landmarks handled — skip generic scan for this element
            }

            // ── generic named point dicts (e.g. joints) ───────────────────────
            NSSet *handled = [NSSet setWithObjects:@"boundingBox", @"confidence", nil];
            for (NSString *key in element) {
                if ([handled containsObject:key]) continue;
                id val = element[key];
                if (![val isKindOfClass:[NSDictionary class]]) continue;
                NSDictionary *d = val;
                if (d[@"x"] && d[@"y"]) {
                    // Single named point
                    CGPoint pt = CGPointMake([d[@"x"] doubleValue], [d[@"y"] doubleValue]);
                    [shapes addObject:[SVGPointShape shapeWithCenter:pt radius:4.0 style:dotStyle]];
                } else {
                    // Dict of named points (e.g. joints dict)
                    for (NSString *subKey in d) {
                        (void)subKey;
                        id sv = d[subKey];
                        if (![sv isKindOfClass:[NSDictionary class]]) continue;
                        NSDictionary *sd = sv;
                        if (sd[@"x"] && sd[@"y"]) {
                            CGPoint pt = CGPointMake([sd[@"x"] doubleValue], [sd[@"y"] doubleValue]);
                            [shapes addObject:[SVGPointShape shapeWithCenter:pt radius:4.0 style:dotStyle]];
                        }
                    }
                }
            }
        }
    }
    return shapes;
}

// ─────────────────────────────────────────────────────────────────────────────
// OverlayProcessor
// ─────────────────────────────────────────────────────────────────────────────

@implementation OverlayProcessor

- (BOOL)runWithError:(NSError **)error {
    if (!self.jsonPath.length) {
        if (error) *error = [NSError errorWithDomain:SVGErrorDomain code:SVGErrorMissingInput
                                            userInfo:@{NSLocalizedDescriptionKey: @"--json <path> is required"}];
        return NO;
    }

    NSData *data = [NSData dataWithContentsOfFile:self.jsonPath options:0 error:error];
    if (!data) return NO;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) return NO;

    NSString *imagePath = self.img;
    if (!imagePath.length)
        imagePath = json[@"info"][@"filepath"];
    if (imagePath.length && ![imagePath hasPrefix:@"/"])
        imagePath = [[NSFileManager defaultManager].currentDirectoryPath
                     stringByAppendingPathComponent:imagePath];

    NSArray<SVGShape *> *shapes = OVShapesFromJSON(json, self.showLabels);

    SVGOverlay *overlay = [[SVGOverlay alloc] initWithImagePath:imagePath];
    [overlay addShapes:shapes];

    NSString *base    = [[self.jsonPath lastPathComponent] stringByDeletingPathExtension];
    NSString *svgName = [base stringByAppendingPathExtension:@"svg"];
    NSString *outPath = self.output.length
        ? [self.output stringByAppendingPathComponent:svgName]
        : [[self.jsonPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:svgName];

    return [overlay writeToPath:outPath error:error];
}

@end

// (VisionShapeBuilder removed — generic walker OVShapesFromJSON handles all JSON formats)
