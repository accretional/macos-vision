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
// SVGPalette
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGPalette

+ (instancetype)defaultPalette {
    SVGPalette *p = [[self alloc] init];

    // Face
    p.faceBox             = [SVGStyle styleWithStroke:@"#FF4444" fill:@"none"                    strokeWidth:2.0];
    p.faceLandmarkEye     = [SVGStyle styleWithStroke:@"#00FFFF" fill:@"rgba(0,255,255,0.08)"    strokeWidth:1.5];
    p.faceLandmarkLip     = [SVGStyle styleWithStroke:@"#FF88FF" fill:@"rgba(255,136,255,0.08)"  strokeWidth:1.5];
    p.faceLandmarkNose    = [SVGStyle styleWithStroke:@"#FFFF44" fill:@"none"                    strokeWidth:1.5];
    p.faceLandmarkBrow    = [SVGStyle styleWithStroke:@"#88FF44" fill:@"none"                    strokeWidth:1.5];
    p.faceLandmarkContour = [SVGStyle styleWithStroke:@"#FF8844" fill:@"none"                    strokeWidth:1.5];
    p.faceLandmarkDot     = [SVGStyle styleWithStroke:@"none"    fill:@"#00FF88"                 strokeWidth:0.0];

    // Body / human
    p.humanBox  = [SVGStyle styleWithStroke:@"#4488FF" fill:@"none"     strokeWidth:2.0];
    p.poseJoint = [SVGStyle styleWithStroke:@"none"    fill:@"#FFFF44"  strokeWidth:0.0];
    p.poseBone  = [SVGStyle styleWithStroke:@"#FF8844" fill:@"none"     strokeWidth:2.0];

    // Animal
    p.animalJoint = [SVGStyle styleWithStroke:@"none"    fill:@"#FF44FF" strokeWidth:0.0];
    p.animalBox   = [SVGStyle styleWithStroke:@"#44FFFF" fill:@"none"    strokeWidth:2.0];

    // Classify
    p.objectBox      = [SVGStyle styleWithStroke:@"#44FF44" fill:@"none" strokeWidth:2.0];
    p.rectangleQuad  = [SVGStyle styleWithStroke:@"#FFAA44" fill:@"rgba(255,170,68,0.1)" strokeWidth:2.0];

    // Track
    p.trajectoryPath  = [SVGStyle styleWithStroke:@"#FF4444" fill:@"none"    strokeWidth:2.0];
    p.trajectoryPoint = [SVGStyle styleWithStroke:@"none"    fill:@"#FF8888" strokeWidth:0.0];

    // Horizon
    p.horizonLine = [SVGStyle styleWithStroke:@"#00FFFF" fill:@"none" strokeWidth:2.5];

    // Labels
    p.showLabels         = NO;
    p.labelColor         = @"#FFFFFF";
    p.labelFontSize      = 13.0;
    p.smallLabelFontSize = 10.0;

    return p;
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGShape base
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
// VisionShapeBuilder
// ─────────────────────────────────────────────────────────────────────────────

@implementation VisionShapeBuilder

+ (NSArray<SVGShape *> *)shapesFromVisionJSON:(NSDictionary *)json {
    return [self shapesFromVisionJSON:json palette:[SVGPalette defaultPalette]];
}

+ (NSArray<SVGShape *> *)shapesFromVisionJSON:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSString *op = json[@"operation"];
    if (!op) return @[];

    if ([op isEqualToString:@"face-rectangles"])  return [self shapesForFaceRectangles:json  palette:palette];
    if ([op isEqualToString:@"face-landmarks"])   return [self shapesForFaceLandmarks:json   palette:palette];
    if ([op isEqualToString:@"face-quality"])     return [self shapesForFaceQuality:json     palette:palette];
    if ([op isEqualToString:@"human-rectangles"]) return [self shapesForHumanRectangles:json palette:palette];
    if ([op isEqualToString:@"body-pose"])        return [self shapesForBodyPose:json        palette:palette];
    if ([op isEqualToString:@"hand-pose"])        return [self shapesForHandPose:json        palette:palette];
    if ([op isEqualToString:@"animal-pose"])      return [self shapesForAnimalPose:json      palette:palette];
    if ([op isEqualToString:@"classify"])         return [self shapesForClassify:json        palette:palette];
    if ([op isEqualToString:@"animals"])          return [self shapesForAnimals:json         palette:palette];
    if ([op isEqualToString:@"rectangles"])       return [self shapesForRectangles:json      palette:palette];
    if ([op isEqualToString:@"horizon"])          return [self shapesForHorizon:json         palette:palette];
    if ([op isEqualToString:@"trajectories"])     return [self shapesForTrajectories:json    palette:palette];
    if ([op isEqualToString:@"aesthetics"])       return [self shapesForAesthetics:json      palette:palette];
    if ([op isEqualToString:@"ocr"])              return [self shapesForOCR:json             palette:palette];

    // Operations with no visual overlay (feature-print, contours metadata, flow maps)
    return @[];
}

// ── face-rectangles ───────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForFaceRectangles:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];
    for (NSDictionary *face in json[@"faces"]) {
        CGRect r = [self rectFromDict:face[@"boundingBox"]];
        [shapes addObject:[SVGRectShape shapeWithRect:r style:palette.faceBox]];
        if (palette.showLabels && face[@"confidence"]) {
            NSString *label = [NSString stringWithFormat:@"%.0f%%", [face[@"confidence"] doubleValue] * 100];
            [shapes addObject:[self labelAtTopLeft:r text:label palette:palette]];
        }
    }
    return shapes;
}

// ── face-landmarks ────────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForFaceLandmarks:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];

    for (NSDictionary *face in json[@"faces"]) {
        // Face bounding box
        CGRect r = [self rectFromDict:face[@"boundingBox"]];
        [shapes addObject:[SVGRectShape shapeWithRect:r style:palette.faceBox]];

        NSDictionary *landmarks = face[@"landmarks"];
        if (![landmarks isKindOfClass:[NSDictionary class]]) continue;

        // Landmark region points as individual dots
        for (NSString *key in landmarks) {
            NSArray *pts = landmarks[key];
            if (![pts isKindOfClass:[NSArray class]] || pts.count == 0) continue;

            NSArray<NSValue *> *nspts = [self pointValuesFromDicts:pts];

            if (pts.count == 1) {
                // single point — draw as dot with optional label
                CGPoint center = nspts[0].pointValue;
                [shapes addObject:[SVGPointShape shapeWithCenter:center radius:3.0 style:palette.faceLandmarkDot]];
                if (palette.showLabels)
                    [shapes addObject:[self smallLabelAt:center text:key palette:palette]];
            } else {
                SVGStyle *style = [self styleForLandmarkRegion:key palette:palette];
                // Polygon closes last→first so each region is a bounded shape (polyline would leave it open).
                [shapes addObject:[SVGPolygonShape shapeWithPoints:nspts style:style]];
                // Label at centroid of the region
                if (palette.showLabels) {
                    CGPoint centroid = [self centroidOfPoints:nspts];
                    [shapes addObject:[self smallLabelAt:centroid text:key palette:palette]];
                }
            }
        }
    }
    return shapes;
}

// ── face-quality ──────────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForFaceQuality:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];
    for (NSDictionary *face in json[@"faces"]) {
        CGRect r = [self rectFromDict:face[@"boundingBox"]];
        [shapes addObject:[SVGRectShape shapeWithRect:r style:palette.faceBox]];
        if (palette.showLabels && face[@"quality"]) {
            NSString *label = [NSString stringWithFormat:@"q:%.2f", [face[@"quality"] doubleValue]];
            [shapes addObject:[self labelAtTopLeft:r text:label palette:palette]];
        }
    }
    return shapes;
}

// ── human-rectangles ──────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForHumanRectangles:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];
    for (NSDictionary *human in json[@"humans"]) {
        CGRect r = [self rectFromDict:human[@"boundingBox"]];
        [shapes addObject:[SVGRectShape shapeWithRect:r style:palette.humanBox]];
        if (palette.showLabels) {
            BOOL upper = [human[@"upperBodyOnly"] boolValue];
            NSString *label = upper ? @"upper body" : @"full body";
            [shapes addObject:[self labelAtTopLeft:r text:label palette:palette]];
        }
    }
    return shapes;
}

// ── body-pose ─────────────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForBodyPose:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];

    // Skeleton bone edges (Vision joint name strings)
    NSArray<NSArray<NSString *> *> *boneEdges = @[
        @[@"nose_1_joint",           @"neck_1_joint"],
        @[@"neck_1_joint",           @"left_shoulder_1_joint"],
        @[@"neck_1_joint",           @"right_shoulder_1_joint"],
        @[@"left_shoulder_1_joint",  @"left_forearm_joint"],
        @[@"left_forearm_joint",     @"left_hand_joint"],
        @[@"right_shoulder_1_joint", @"right_forearm_joint"],
        @[@"right_forearm_joint",    @"right_hand_joint"],
        @[@"neck_1_joint",           @"root_hip_joint"],
        @[@"root_hip_joint",         @"left_upLeg_joint"],
        @[@"root_hip_joint",         @"right_upLeg_joint"],
        @[@"left_upLeg_joint",       @"left_leg_joint"],
        @[@"left_leg_joint",         @"left_foot_joint"],
        @[@"right_upLeg_joint",      @"right_leg_joint"],
        @[@"right_leg_joint",        @"right_foot_joint"],
    ];

    for (NSDictionary *body in json[@"bodies"]) {
        NSDictionary *joints = body[@"joints"];
        if (![joints isKindOfClass:[NSDictionary class]]) continue;

        // Draw bones first (behind joints)
        for (NSArray<NSString *> *edge in boneEdges) {
            NSDictionary *j1 = joints[edge[0]];
            NSDictionary *j2 = joints[edge[1]];
            if (!j1 || !j2) continue;
            CGPoint p1 = CGPointMake([j1[@"x"] doubleValue], [j1[@"y"] doubleValue]);
            CGPoint p2 = CGPointMake([j2[@"x"] doubleValue], [j2[@"y"] doubleValue]);
            [shapes addObject:[SVGLineShape shapeWithStart:p1 end:p2 style:palette.poseBone]];
        }

        // Draw joints on top with optional labels
        for (NSString *name in joints) {
            NSDictionary *joint = joints[name];
            CGPoint pt = CGPointMake([joint[@"x"] doubleValue], [joint[@"y"] doubleValue]);
            [shapes addObject:[SVGPointShape shapeWithCenter:pt radius:4.0 style:palette.poseJoint]];
            if (palette.showLabels)
                [shapes addObject:[self smallLabelAt:pt text:name palette:palette]];
        }
    }
    return shapes;
}

// ── hand-pose ─────────────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForHandPose:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];

    // Each finger chain: wrist → CMC/MCP → ... → tip
    NSArray<NSArray<NSString *> *> *fingerChains = @[
        @[@"wrist_joint", @"thumb_cmc_joint",         @"thumb_mp_joint",          @"thumb_ip_joint",          @"thumb_tip_joint"],
        @[@"wrist_joint", @"index_finger_mcp_joint",  @"index_finger_pip_joint",  @"index_finger_dip_joint",  @"index_finger_tip_joint"],
        @[@"wrist_joint", @"middle_finger_mcp_joint", @"middle_finger_pip_joint", @"middle_finger_dip_joint", @"middle_finger_tip_joint"],
        @[@"wrist_joint", @"ring_finger_mcp_joint",   @"ring_finger_pip_joint",   @"ring_finger_dip_joint",   @"ring_finger_tip_joint"],
        @[@"wrist_joint", @"little_finger_mcp_joint", @"little_finger_pip_joint", @"little_finger_dip_joint", @"little_finger_tip_joint"],
    ];

    for (NSDictionary *hand in json[@"hands"]) {
        NSDictionary *joints = hand[@"joints"];
        if (![joints isKindOfClass:[NSDictionary class]]) continue;

        // Draw finger chains (bones)
        for (NSArray<NSString *> *chain in fingerChains) {
            NSMutableArray<NSValue *> *pts = [NSMutableArray array];
            for (NSString *name in chain) {
                NSDictionary *j = joints[name];
                if (!j) continue;
                [pts addObject:[NSValue valueWithPoint:NSMakePoint([j[@"x"] doubleValue], [j[@"y"] doubleValue])]];
            }
            if (pts.count >= 2) {
                [shapes addObject:[SVGPolylineShape shapeWithPoints:pts style:palette.poseBone]];
            }
        }

        // Draw joints on top with optional labels
        for (NSString *name in joints) {
            NSDictionary *joint = joints[name];
            CGPoint pt = CGPointMake([joint[@"x"] doubleValue], [joint[@"y"] doubleValue]);
            [shapes addObject:[SVGPointShape shapeWithCenter:pt radius:3.5 style:palette.poseJoint]];
            if (palette.showLabels)
                [shapes addObject:[self smallLabelAt:pt text:name palette:palette]];
        }
    }
    return shapes;
}

// ── animal-pose ───────────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForAnimalPose:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];
    for (NSDictionary *animal in json[@"animals"]) {
        NSDictionary *joints = animal[@"joints"];
        if (![joints isKindOfClass:[NSDictionary class]]) continue;
        for (NSString *name in joints) {
            NSDictionary *joint = joints[name];
            CGPoint pt = CGPointMake([joint[@"x"] doubleValue], [joint[@"y"] doubleValue]);
            [shapes addObject:[SVGPointShape shapeWithCenter:pt radius:4.0 style:palette.animalJoint]];
            if (palette.showLabels)
                [shapes addObject:[self smallLabelAt:pt text:name palette:palette]];
        }
    }
    return shapes;
}

// ── classify ──────────────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForClassify:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];
    if (!palette.showLabels) return shapes;
    NSArray *classifications = json[@"classifications"];
    if (![classifications isKindOfClass:[NSArray class]]) return shapes;

    NSUInteger limit = MIN((NSUInteger)5, classifications.count);
    CGFloat lineH = palette.labelFontSize + 4;
    CGFloat marginX = 0.01;
    CGFloat marginY = 0.01;
    // Normalized line height (we'll use a fixed pixel estimate — approx 18px per line)
    // We pass un-normalized y positions and let SVGTextShape scale them.
    // But SVGTextShape takes normalized coords, so we need to provide them.
    // Problem: we don't know the image height here.
    // Solution: use a normalized estimate. 18px / 600px ≈ 0.03.
    // Actually the better approach: use a small enough fraction.
    // Let's use lineHeightNorm = 0.04 as an estimate, with 18px font.
    CGFloat lineHeightNorm = 0.04;
    (void)lineH;

    for (NSUInteger i = 0; i < limit; i++) {
        NSDictionary *cls = classifications[i];
        NSString *label = [NSString stringWithFormat:@"%@: %.0f%%",
                           cls[@"identifier"], [cls[@"confidence"] doubleValue] * 100];
        CGFloat yNorm = marginY + i * lineHeightNorm;
        CGPoint pos = CGPointMake(marginX, yNorm);
        [shapes addObject:[SVGTextShape shapeWithPosition:pos text:label
                                                    color:palette.labelColor
                                                 fontSize:palette.labelFontSize]];
    }
    return shapes;
}

// ── animals ───────────────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForAnimals:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];
    for (NSDictionary *animal in json[@"animals"]) {
        CGRect r = [self rectFromDict:animal[@"boundingBox"]];
        [shapes addObject:[SVGRectShape shapeWithRect:r style:palette.animalBox]];
        if (palette.showLabels) {
            NSArray *labels = animal[@"labels"];
            if ([labels isKindOfClass:[NSArray class]] && labels.count > 0) {
                NSString *label = [NSString stringWithFormat:@"%@: %.0f%%",
                                   labels[0][@"identifier"],
                                   [labels[0][@"confidence"] doubleValue] * 100];
                [shapes addObject:[self labelAtTopLeft:r text:label palette:palette]];
            }
        }
    }
    return shapes;
}

// ── rectangles ────────────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForRectangles:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];
    for (NSDictionary *rect in json[@"rectangles"]) {
        // Use the 4 corners to draw a precise (possibly tilted) quad
        NSDictionary *tl = rect[@"topLeft"];
        NSDictionary *tr = rect[@"topRight"];
        NSDictionary *br = rect[@"bottomRight"];
        NSDictionary *bl = rect[@"bottomLeft"];
        if (tl && tr && br && bl) {
            NSArray<NSValue *> *pts = @[
                [NSValue valueWithPoint:NSMakePoint([tl[@"x"] doubleValue], [tl[@"y"] doubleValue])],
                [NSValue valueWithPoint:NSMakePoint([tr[@"x"] doubleValue], [tr[@"y"] doubleValue])],
                [NSValue valueWithPoint:NSMakePoint([br[@"x"] doubleValue], [br[@"y"] doubleValue])],
                [NSValue valueWithPoint:NSMakePoint([bl[@"x"] doubleValue], [bl[@"y"] doubleValue])],
            ];
            [shapes addObject:[SVGPolygonShape shapeWithPoints:pts style:palette.rectangleQuad]];
        } else {
            // Fallback to bounding box
            CGRect r = [self rectFromDict:rect[@"boundingBox"]];
            [shapes addObject:[SVGRectShape shapeWithRect:r style:palette.rectangleQuad]];
        }
        if (palette.showLabels && rect[@"confidence"]) {
            NSString *label = [NSString stringWithFormat:@"%.0f%%", [rect[@"confidence"] doubleValue] * 100];
            CGRect bb = [self rectFromDict:rect[@"boundingBox"]];
            [shapes addObject:[self labelAtTopLeft:bb text:label palette:palette]];
        }
    }
    return shapes;
}

// ── horizon ───────────────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForHorizon:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSDictionary *horizon = json[@"horizon"];
    if (!horizon) return @[];

    double angle = [horizon[@"angle"] doubleValue];

    // Determine the vertical center of the horizon line.
    // Vision's transform.ty gives the vertical shift in image pixels (positive = shift down).
    double centerY = 0.5;
    NSDictionary *transform = horizon[@"transform"];
    NSDictionary *info = json[@"info"];
    if (transform && info) {
        double ty = [transform[@"ty"] doubleValue];
        double imgH = [info[@"height"] doubleValue];
        if (imgH > 0) {
            centerY = 0.5 - ty / imgH;
        }
    }

    // Line spans full width through (0.5, centerY) at the given angle.
    // slope = tan(angle); angle=0 → horizontal
    double slope = tan(angle);
    double y0 = centerY - 0.5 * slope;  // at x=0
    double y1 = centerY + 0.5 * slope;  // at x=1

    CGPoint start = CGPointMake(0.0, (CGFloat)y0);
    CGPoint end   = CGPointMake(1.0, (CGFloat)y1);
    return @[[SVGLineShape shapeWithStart:start end:end style:palette.horizonLine]];
}

// ── trajectories ──────────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForTrajectories:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];
    for (NSDictionary *traj in json[@"trajectories"]) {
        NSArray *detPts = traj[@"detectedPoints"];
        if (![detPts isKindOfClass:[NSArray class]] || detPts.count == 0) continue;

        NSArray<NSValue *> *pts = [self pointValuesFromDicts:detPts];
        // Polyline for the path
        if (pts.count >= 2) {
            [shapes addObject:[SVGPolylineShape shapeWithPoints:pts style:palette.trajectoryPath]];
        }
        // Dots at each detected point
        for (NSValue *v in pts) {
            [shapes addObject:[SVGPointShape shapeWithCenter:v.pointValue radius:3.0 style:palette.trajectoryPoint]];
        }
    }
    return shapes;
}

// ── aesthetics ────────────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForAesthetics:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];
    if (!palette.showLabels) return shapes;
    NSDictionary *scores = json[@"scores"];
    if (![scores isKindOfClass:[NSDictionary class]]) return shapes;

    NSString *utilStr = [scores[@"isUtility"] boolValue] ? @"utility" : @"non-utility";
    NSString *scoreStr = [NSString stringWithFormat:@"score:%.2f (%@)", [scores[@"overallScore"] doubleValue], utilStr];
    [shapes addObject:[SVGTextShape shapeWithPosition:CGPointMake(0.01, 0.01)
                                                 text:scoreStr
                                                color:palette.labelColor
                                             fontSize:palette.labelFontSize]];
    return shapes;
}

// ── ocr ───────────────────────────────────────────────────────────────────────

+ (NSArray<SVGShape *> *)shapesForOCR:(NSDictionary *)json palette:(SVGPalette *)palette {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];
    for (NSDictionary *obs in json[@"observations"]) {
        NSDictionary *quad = obs[@"quad"];
        if (![quad isKindOfClass:[NSDictionary class]]) continue;

        NSDictionary *tl = quad[@"topLeft"];
        NSDictionary *tr = quad[@"topRight"];
        NSDictionary *br = quad[@"bottomRight"];
        NSDictionary *bl = quad[@"bottomLeft"];
        if (!tl || !tr || !br || !bl) continue;

        NSArray<NSValue *> *pts = @[
            [NSValue valueWithPoint:NSMakePoint([tl[@"x"] doubleValue], [tl[@"y"] doubleValue])],
            [NSValue valueWithPoint:NSMakePoint([tr[@"x"] doubleValue], [tr[@"y"] doubleValue])],
            [NSValue valueWithPoint:NSMakePoint([br[@"x"] doubleValue], [br[@"y"] doubleValue])],
            [NSValue valueWithPoint:NSMakePoint([bl[@"x"] doubleValue], [bl[@"y"] doubleValue])],
        ];
        SVGPolygonShape *box = [SVGPolygonShape shapeWithPoints:pts style:palette.objectBox];
        [shapes addObject:box];

        if (palette.showLabels) {
            NSString *text = obs[@"text"];
            if ([text isKindOfClass:[NSString class]] && text.length > 0) {
                [shapes addObject:[SVGTextShape shapeWithPosition:CGPointMake([tl[@"x"] doubleValue], [tl[@"y"] doubleValue] - 0.01)
                                                             text:text
                                                            color:palette.labelColor
                                                         fontSize:palette.smallLabelFontSize]];
            }
        }
    }
    return shapes;
}

// ── private helpers ───────────────────────────────────────────────────────────

+ (CGRect)rectFromDict:(NSDictionary *)d {
    return CGRectMake([d[@"x"] doubleValue], [d[@"y"] doubleValue],
                      [d[@"width"] doubleValue], [d[@"height"] doubleValue]);
}

+ (NSArray<NSValue *> *)pointValuesFromDicts:(NSArray *)dicts {
    NSMutableArray<NSValue *> *pts = [NSMutableArray arrayWithCapacity:dicts.count];
    for (NSDictionary *d in dicts) {
        [pts addObject:[NSValue valueWithPoint:NSMakePoint([d[@"x"] doubleValue], [d[@"y"] doubleValue])]];
    }
    return pts;
}

+ (SVGTextShape *)labelAtTopLeft:(CGRect)rect text:(NSString *)text palette:(SVGPalette *)palette {
    CGPoint pos = CGPointMake(rect.origin.x, rect.origin.y);
    return [SVGTextShape shapeWithPosition:pos text:text
                                     color:palette.labelColor fontSize:palette.labelFontSize];
}

+ (CGPoint)centroidOfPoints:(NSArray<NSValue *> *)points {
    if (points.count == 0) return CGPointZero;
    double sx = 0, sy = 0;
    for (NSValue *v in points) {
        NSPoint p = v.pointValue;
        sx += p.x; sy += p.y;
    }
    return CGPointMake(sx / points.count, sy / points.count);
}

+ (SVGTextShape *)smallLabelAt:(CGPoint)pt text:(NSString *)text palette:(SVGPalette *)palette {
    // Offset slightly right and up from the point so the label doesn't overlap the dot
    CGPoint pos = CGPointMake(pt.x + 0.012, pt.y - 0.012);
    return [SVGTextShape shapeWithPosition:pos text:text
                                     color:palette.labelColor
                                  fontSize:palette.smallLabelFontSize];
}

+ (SVGStyle *)styleForLandmarkRegion:(NSString *)key palette:(SVGPalette *)palette {
    if ([key isEqualToString:@"leftEye"]    || [key isEqualToString:@"rightEye"]   ||
        [key isEqualToString:@"leftPupil"]  || [key isEqualToString:@"rightPupil"])
        return palette.faceLandmarkEye;

    if ([key isEqualToString:@"outerLips"] || [key isEqualToString:@"innerLips"])
        return palette.faceLandmarkLip;

    if ([key isEqualToString:@"nose"] || [key isEqualToString:@"noseCrest"])
        return palette.faceLandmarkNose;

    if ([key isEqualToString:@"leftEyebrow"] || [key isEqualToString:@"rightEyebrow"])
        return palette.faceLandmarkBrow;

    if ([key isEqualToString:@"faceContour"] || [key isEqualToString:@"medianLine"])
        return palette.faceLandmarkContour;

    return palette.faceLandmarkDot;
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGProcessor
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGProcessor

- (instancetype)init {
    if ((self = [super init])) {
        _showLabels = NO;
    }
    return self;
}

- (BOOL)runWithError:(NSError **)error {
    if (!self.jsonPath.length) {
        if (error) *error = [NSError errorWithDomain:SVGErrorDomain code:SVGErrorMissingInput
                                            userInfo:@{NSLocalizedDescriptionKey: @"--json <path> is required"}];
        return NO;
    }

    // ── load JSON ─────────────────────────────────────────────────────────────
    NSData *data = [NSData dataWithContentsOfFile:self.jsonPath options:0 error:error];
    if (!data) return NO;

    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) return NO;

    // ── resolve image path ────────────────────────────────────────────────────
    NSString *imagePath = self.img;
    if (!imagePath.length) {
        imagePath = json[@"info"][@"filepath"];
    }
    // Make absolute if needed
    if (imagePath.length && ![imagePath hasPrefix:@"/"]) {
        imagePath = [[NSFileManager defaultManager].currentDirectoryPath
                     stringByAppendingPathComponent:imagePath];
    }

    // ── build shapes ──────────────────────────────────────────────────────────
    SVGPalette *palette = [SVGPalette defaultPalette];
    palette.showLabels = self.showLabels;
    NSArray<SVGShape *> *shapes = [VisionShapeBuilder shapesFromVisionJSON:json palette:palette];

    // ── create overlay ────────────────────────────────────────────────────────
    SVGOverlay *overlay = [[SVGOverlay alloc] initWithImagePath:imagePath];
    [overlay addShapes:shapes];

    // ── determine output path ─────────────────────────────────────────────────
    NSString *base = [[self.jsonPath lastPathComponent] stringByDeletingPathExtension];
    NSString *svgName = [base stringByAppendingPathExtension:@"svg"];
    NSString *outPath;

    if (self.output.length) {
        outPath = [self.output stringByAppendingPathComponent:svgName];
    } else {
        outPath = [[self.jsonPath stringByDeletingLastPathComponent]
                   stringByAppendingPathComponent:svgName];
    }

    return [overlay writeToPath:outPath error:error];
}

@end
