#import "main.h"
#import "common/MVJsonEmit.h"
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

static NSString *pointsString(NSArray<NSValue *> *points, CGFloat w, CGFloat h) {
    NSMutableArray<NSString *> *parts = [NSMutableArray arrayWithCapacity:points.count];
    for (NSValue *v in points) {
        NSPoint p = v.pointValue;
        [parts addObject:[NSString stringWithFormat:@"%.2f,%.2f", p.x * w, p.y * h]];
    }
    return [parts componentsJoinedByString:@" "];
}

/// Returns `data-label="…" data-confidence="…"` attributes for a shape.
static NSString *dataAttrs(SVGShape *shape) {
    NSMutableString *s = [NSMutableString string];
    if (shape.label.length)
        [s appendFormat:@" data-label=\"%@\"", svgEscape(shape.label)];
    if (shape.confidence)
        [s appendFormat:@" data-confidence=\"%.4f\"", shape.confidence.doubleValue];
    return s;
}

/// Returns a `<title>` child element for native browser tooltips, or "" if no label.
static NSString *titleElem(SVGShape *shape) {
    if (!shape.label.length) return @"";
    NSMutableString *t = [NSMutableString stringWithString:shape.label];
    if (shape.confidence)
        [t appendFormat:@" — %d%%", (int)round(shape.confidence.doubleValue * 100)];
    return [NSString stringWithFormat:@"<title>%@</title>", svgEscape(t)];
}

// ─────────────────────────────────────────────────────────────────────────────
// Embedded CSS — hover/selection states for all shape classes
// ─────────────────────────────────────────────────────────────────────────────

/// Colours rotate by JSON array element index (faces[0], faces[1], …).
static const NSUInteger OVPaletteSize = 8;

static NSString * const OV_CSS =
    @"<defs><style>\n"
     "  .ov-c0 { --r:239; --g:68;  --b:68;  }\n"
     "  .ov-c1 { --r:0;   --g:221; --b:204; }\n"
     "  .ov-c2 { --r:255; --g:170; --b:0;   }\n"
     "  .ov-c3 { --r:170; --g:255; --b:68;  }\n"
     "  .ov-c4 { --r:168; --g:85;  --b:247; }\n"
     "  .ov-c5 { --r:59;  --g:130; --b:246; }\n"
     "  .ov-c6 { --r:236; --g:72;  --b:153; }\n"
     "  .ov-c7 { --r:34;  --g:197; --b:94;  }\n"
     "\n"
     "  .ov-box          { stroke:rgb(var(--r,239),var(--g,68),var(--b,68)); fill:none; stroke-width:2; cursor:pointer; transition:fill .18s; }\n"
     "  .ov-box:hover    { fill:rgba(var(--r,239),var(--g,68),var(--b,68),.18); }\n"
     "  .ov-box.active   { fill:rgba(var(--r,239),var(--g,68),var(--b,68),.38); stroke-width:3; }\n"
     "\n"
     "  .ov-quad         { stroke:rgb(var(--r,239),var(--g,68),var(--b,68)); fill:rgba(var(--r,239),var(--g,68),var(--b,68),.07); stroke-width:1.5; cursor:pointer; transition:fill .18s; }\n"
     "  .ov-quad:hover   { fill:rgba(var(--r,239),var(--g,68),var(--b,68),.28); }\n"
     "  .ov-quad.active  { fill:rgba(var(--r,239),var(--g,68),var(--b,68),.45); }\n"
     "\n"
     "  .ov-landmark        { stroke:rgb(var(--r,239),var(--g,68),var(--b,68)); fill:rgba(var(--r,239),var(--g,68),var(--b,68),.07); stroke-width:1.5; cursor:pointer; transition:fill .18s; }\n"
     "  .ov-landmark:hover  { fill:rgba(var(--r,239),var(--g,68),var(--b,68),.3); }\n"
     "  .ov-landmark.active { fill:rgba(var(--r,239),var(--g,68),var(--b,68),.48); }\n"
     "  .ov-landmark.hidden { display:none; }\n"
     "\n"
     "  .ov-point        { fill:rgb(var(--r,239),var(--g,68),var(--b,68)); cursor:pointer; transition:fill .15s; }\n"
     "  .ov-point:hover  { fill:#fff; }\n"
     "  .ov-point.active { fill:#FF88FF; }\n"
     "\n"
     "  .ov-joint        { fill:rgb(var(--r,239),var(--g,68),var(--b,68)); cursor:pointer; transition:fill .15s; }\n"
     "  .ov-joint:hover  { fill:#fff; }\n"
     "  .ov-joint.active { fill:#FF88FF; }\n"
     "  .ov-joint.hidden { display:none; }\n"
     "\n"
     "  .ov-bone         { stroke:rgb(var(--r,239),var(--g,68),var(--b,68)); fill:none; stroke-width:1.5; stroke-dasharray:5,3; opacity:.7; }\n"
     "  .ov-bone.hidden  { display:none; }\n"
     "\n"
     "  #ov-panel        { pointer-events:none; }\n"
     "  #ov-panel.hidden { display:none; }\n"
     "  #ov-panel-text   { font-family:sans-serif; font-size:13px; fill:#fff; }\n"
     "</style></defs>\n";

// ─────────────────────────────────────────────────────────────────────────────
// Embedded JS — click → info panel; layer toggle API for host pages
// ─────────────────────────────────────────────────────────────────────────────

static NSString * const OV_SCRIPT =
    @"<script type=\"text/ecmascript\"><![CDATA[\n"
     "window.addEventListener('load', function () {\n"
     "  var panel    = document.getElementById('ov-panel');\n"
     "  var panelBg  = document.getElementById('ov-panel-bg');\n"
     "  var panelTxt = document.getElementById('ov-panel-text');\n"
     "  var svgRoot  = document.documentElement;\n"
     "  var vb       = svgRoot.viewBox.baseVal;\n"
     "  var svgW     = vb ? vb.width  : 800;\n"
     "  var svgH     = vb ? vb.height : 600;\n"
     "\n"
     "  function showPanel(label, confidence, bx, by) {\n"
     "    var txt = label + (confidence ? '  ' + Math.round(parseFloat(confidence) * 100) + '%' : '');\n"
     "    panelTxt.textContent = txt;\n"
     "    var w = Math.min(txt.length * 7.5 + 20, 320);\n"
     "    panelBg.setAttribute('width', w);\n"
     "    var px = Math.max(4, Math.min(bx, svgW - w - 4));\n"
     "    var py = Math.max(36, by);\n"
     "    panel.setAttribute('transform', 'translate(' + px + ',' + (py - 34) + ')');\n"
     "    panel.classList.remove('hidden');\n"
     "  }\n"
     "\n"
     "  function clearActive() {\n"
     "    svgRoot.querySelectorAll('.active').forEach(function (a) { a.classList.remove('active'); });\n"
     "    panel.classList.add('hidden');\n"
     "  }\n"
     "\n"
     "  svgRoot.querySelectorAll('[data-label]').forEach(function (el) {\n"
     "    el.addEventListener('click', function (e) {\n"
     "      clearActive();\n"
     "      el.classList.add('active');\n"
     "      var bb;\n"
     "      try { bb = el.getBBox(); } catch (_) { bb = { x: svgW / 2, y: svgH / 2 }; }\n"
     "      showPanel(el.dataset.label, el.dataset.confidence, bb.x, bb.y);\n"
     "      e.stopPropagation();\n"
     "    });\n"
     "  });\n"
     "\n"
     "  svgRoot.addEventListener('click', clearActive);\n"
     "\n"
     "  // Layer toggle API — callable from a host page via:\n"
     "  //   document.querySelector('object').contentDocument.ovToggleLayer('layer-joints', false)\n"
     "  window.ovToggleLayer = function (layerId, visible) {\n"
     "    var g = document.getElementById(layerId);\n"
     "    if (g) g.classList.toggle('hidden', !visible);\n"
     "  };\n"
     "});\n"
     "]]></script>\n";

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

+ (instancetype)shapeWithCenter:(CGPoint)center radius:(CGFloat)radius {
    SVGPointShape *s = [[self alloc] init];
    s.center = center;
    s.radius = radius;
    return s;
}

- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height {
    CGFloat cx  = self.center.x * width;
    CGFloat cy  = self.center.y * height;
    NSString *cls   = self.cssClass ?: @"ov-point";
    NSString *inner = titleElem(self);
    if (inner.length)
        return [NSString stringWithFormat:
            @"<circle class=\"%@\" cx=\"%.2f\" cy=\"%.2f\" r=\"%.1f\"%@>%@</circle>",
            cls, cx, cy, self.radius, dataAttrs(self), inner];
    return [NSString stringWithFormat:
        @"<circle class=\"%@\" cx=\"%.2f\" cy=\"%.2f\" r=\"%.1f\"%@/>",
        cls, cx, cy, self.radius, dataAttrs(self)];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGRectShape
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGRectShape

+ (instancetype)shapeWithRect:(CGRect)rect {
    SVGRectShape *s = [[self alloc] init];
    s.rect = rect;
    return s;
}

- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height {
    CGFloat x = self.rect.origin.x    * width;
    CGFloat y = self.rect.origin.y    * height;
    CGFloat w = self.rect.size.width  * width;
    CGFloat h = self.rect.size.height * height;
    NSString *cls   = self.cssClass ?: @"ov-box";
    NSString *inner = titleElem(self);
    if (inner.length)
        return [NSString stringWithFormat:
            @"<rect class=\"%@\" x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\"%@>%@</rect>",
            cls, x, y, w, h, dataAttrs(self), inner];
    return [NSString stringWithFormat:
        @"<rect class=\"%@\" x=\"%.2f\" y=\"%.2f\" width=\"%.2f\" height=\"%.2f\"%@/>",
        cls, x, y, w, h, dataAttrs(self)];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGPolygonShape
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGPolygonShape

+ (instancetype)shapeWithPoints:(NSArray<NSValue *> *)points {
    SVGPolygonShape *s = [[self alloc] init];
    s.points = points;
    return s;
}

- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height {
    if (self.points.count < 2) return @"";
    NSString *cls   = self.cssClass ?: @"ov-polygon";
    NSString *inner = titleElem(self);
    if (inner.length)
        return [NSString stringWithFormat:
            @"<polygon class=\"%@\" points=\"%@\"%@>%@</polygon>",
            cls, pointsString(self.points, width, height), dataAttrs(self), inner];
    return [NSString stringWithFormat:
        @"<polygon class=\"%@\" points=\"%@\"%@/>",
        cls, pointsString(self.points, width, height), dataAttrs(self)];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// SVGLineShape
// ─────────────────────────────────────────────────────────────────────────────

@implementation SVGLineShape

+ (instancetype)shapeWithStart:(CGPoint)start end:(CGPoint)end {
    SVGLineShape *s = [[self alloc] init];
    s.start = start;
    s.end   = end;
    return s;
}

- (NSString *)svgElementForImageWidth:(CGFloat)width height:(CGFloat)height {
    NSString *cls = self.cssClass ?: @"ov-line";
    return [NSString stringWithFormat:
        @"<line class=\"%@\" x1=\"%.2f\" y1=\"%.2f\" x2=\"%.2f\" y2=\"%.2f\"%@/>",
        cls,
        self.start.x * width,  self.start.y * height,
        self.end.x   * width,  self.end.y   * height,
        dataAttrs(self)];
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
        _shapes    = [NSMutableArray array];
    }
    return self;
}

- (void)addShape:(SVGShape *)shape   { [_shapes addObject:shape]; }
- (void)addShapes:(NSArray<SVGShape *> *)shapes { [_shapes addObjectsFromArray:shapes]; }

- (nullable NSString *)generateSVGWithError:(NSError **)error {
    // ── image dimensions + base64 ─────────────────────────────────────────────
    CGFloat imgWidth = 800, imgHeight = 600;
    NSString *b64      = nil;
    NSString *mimeType = @"image/png";

    if (self.imagePath.length > 0 &&
        [[NSFileManager defaultManager] fileExistsAtPath:self.imagePath]) {
        NSImage *nsImg = [[NSImage alloc] initByReferencingFile:self.imagePath];
        if (nsImg) { imgWidth = nsImg.size.width; imgHeight = nsImg.size.height; }
        NSData *imgData = [NSData dataWithContentsOfFile:self.imagePath];
        if (imgData) {
            b64      = [imgData base64EncodedStringWithOptions:0];
            mimeType = [self mimeTypeForExtension:[self.imagePath.pathExtension lowercaseString]];
        }
    }

    // ── SVG open ─────────────────────────────────────────────────────────────
    NSMutableString *svg = [NSMutableString string];
    [svg appendString:@"<?xml version=\"1.0\" encoding=\"UTF-8\"?>\n"];
    [svg appendFormat:
        @"<svg xmlns=\"http://www.w3.org/2000/svg\" "
         "width=\"%.0f\" height=\"%.0f\" viewBox=\"0 0 %.0f %.0f\">\n",
        imgWidth, imgHeight, imgWidth, imgHeight];

    // ── embedded CSS + JS ────────────────────────────────────────────────────
    [svg appendString:OV_CSS];
    [svg appendString:OV_SCRIPT];

    // ── layer 0: photo ───────────────────────────────────────────────────────
    if (b64) {
        [svg appendFormat:
            @"  <image href=\"data:%@;base64,%@\" "
             "x=\"0\" y=\"0\" width=\"%.0f\" height=\"%.0f\" preserveAspectRatio=\"none\"/>\n",
            mimeType, b64, imgWidth, imgHeight];
    } else {
        [svg appendFormat:
            @"  <rect x=\"0\" y=\"0\" width=\"%.0f\" height=\"%.0f\" fill=\"#1a1a1a\"/>\n",
            imgWidth, imgHeight];
    }

    // ── annotation layers — emit shapes grouped by layerID ───────────────────
    NSMutableArray<NSString *> *layerOrder = [NSMutableArray array];
    NSMutableSet<NSString *>   *seen       = [NSMutableSet set];
    for (SVGShape *shape in self.shapes) {
        NSString *lid = shape.layerID ?: @"layer-misc";
        if (![seen containsObject:lid]) {
            [layerOrder addObject:lid];
            [seen addObject:lid];
        }
    }

    for (NSString *lid in layerOrder) {
        [svg appendFormat:@"  <g id=\"%@\">\n", lid];
        for (SVGShape *shape in self.shapes) {
            if (![(shape.layerID ?: @"layer-misc") isEqualToString:lid]) continue;
            NSString *elem = [shape svgElementForImageWidth:imgWidth height:imgHeight];
            if (elem.length > 0)
                [svg appendFormat:@"    %@\n", elem];
        }
        [svg appendString:@"  </g>\n"];
    }

    // ── floating info panel (hidden by default, shown on click) ──────────────
    [svg appendString:
        @"  <g id=\"ov-panel\" class=\"hidden\">\n"
         "    <rect id=\"ov-panel-bg\" height=\"28\" rx=\"4\" fill=\"rgba(0,0,0,.72)\"/>\n"
         "    <text id=\"ov-panel-text\" x=\"10\" y=\"19\"/>\n"
         "  </g>\n"];

    [svg appendString:@"</svg>\n"];
    return svg;
}

- (BOOL)writeToPath:(NSString *)outputPath error:(NSError **)error {
    NSString *dir = [outputPath stringByDeletingLastPathComponent];
    if (dir.length > 0)
        [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                  withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *svg = [self generateSVGWithError:error];
    if (!svg) return NO;
    if (![svg writeToFile:outputPath atomically:YES encoding:NSUTF8StringEncoding error:error]) return NO;
    return YES;
}

- (NSString *)mimeTypeForExtension:(NSString *)ext {
    NSDictionary *map = @{
        @"jpg":  @"image/jpeg", @"jpeg": @"image/jpeg",
        @"png":  @"image/png",  @"gif":  @"image/gif",
        @"bmp":  @"image/bmp",  @"tiff": @"image/tiff",
        @"tif":  @"image/tiff", @"webp": @"image/webp",
    };
    return map[ext] ?: @"image/png";
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// Body pose skeleton — joint pairs to connect with ov-bone lines
// ─────────────────────────────────────────────────────────────────────────────

static NSArray<NSArray<NSString *> *> *bodyBonePairs(void) {
    return @[
        @[@"head_joint",             @"neck_1_joint"],
        @[@"neck_1_joint",           @"right_shoulder_1_joint"],
        @[@"neck_1_joint",           @"left_shoulder_1_joint"],
        @[@"right_shoulder_1_joint", @"right_forearm_joint"],
        @[@"right_forearm_joint",    @"right_hand_joint"],
        @[@"left_shoulder_1_joint",  @"left_forearm_joint"],
        @[@"left_forearm_joint",     @"left_hand_joint"],
        @[@"right_shoulder_1_joint", @"root"],
        @[@"left_shoulder_1_joint",  @"root"],
        @[@"root",                   @"right_upLeg_joint"],
        @[@"root",                   @"left_upLeg_joint"],
        @[@"right_upLeg_joint",      @"right_leg_joint"],
        @[@"right_leg_joint",        @"right_foot_joint"],
        @[@"left_upLeg_joint",       @"left_leg_joint"],
        @[@"left_leg_joint",         @"left_foot_joint"],
    ];
}

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

static NSString *OVColorClassForElementIndex(NSUInteger i) {
    return [NSString stringWithFormat:@"ov-c%lu", (unsigned long)(i % OVPaletteSize)];
}

/// Prefer `labels[0].identifier` (classify animals, etc.) over the generic singularized key.
static NSString *OVBoxLabelFromElement(NSDictionary *element, NSString *fallback) {
    id labels = element[@"labels"];
    if ([labels isKindOfClass:[NSArray class]] && [(NSArray *)labels count] > 0) {
        id first = [(NSArray *)labels objectAtIndex:0];
        if ([first isKindOfClass:[NSDictionary class]]) {
            id idf = ((NSDictionary *)first)[@"identifier"];
            if ([idf isKindOfClass:[NSString class]] && [(NSString *)idf length] > 0)
                return (NSString *)idf;
            if ([idf isKindOfClass:[NSNumber class]])
                return [(NSNumber *)idf stringValue];
        }
    }
    return fallback.length ? fallback : @"region";
}

static NSNumber *OVBoxConfidenceFromElement(NSDictionary *element) {
    id labels = element[@"labels"];
    if ([labels isKindOfClass:[NSArray class]] && [(NSArray *)labels count] > 0) {
        id first = [(NSArray *)labels objectAtIndex:0];
        if ([first isKindOfClass:[NSDictionary class]]) {
            NSDictionary *fd = (NSDictionary *)first;
            if (fd[@"confidence"] != nil)
                return @([fd[@"confidence"] doubleValue]);
        }
    }
    if (element[@"confidence"] != nil)
        return @([element[@"confidence"] doubleValue]);
    return nil;
}

static NSArray<SVGShape *> *OVShapesFromJSON(NSDictionary *json) {
    NSMutableArray<SVGShape *> *shapes = [NSMutableArray array];
    NSSet *skip = [NSSet setWithObjects:@"info", @"operation", nil];

    for (NSString *topKey in json) {
        if ([skip containsObject:topKey]) continue;
        NSArray *elements = json[topKey];
        if (![elements isKindOfClass:[NSArray class]]) continue;

        NSString *elementName = OVSingularize(topKey);

        for (NSUInteger elemIdx = 0; elemIdx < elements.count; elemIdx++) {
            id rawEl = elements[elemIdx];
            if (![rawEl isKindOfClass:[NSDictionary class]]) continue;
            NSDictionary *element = (NSDictionary *)rawEl;
            NSString *colorCls = OVColorClassForElementIndex(elemIdx);

            // ── boundingBox ───────────────────────────────────────────────────
            // Does not continue — an element may also carry landmarks or joints.
            NSDictionary *bb = element[@"boundingBox"];
            if ([bb isKindOfClass:[NSDictionary class]]) {
                CGRect r = CGRectMake([bb[@"x"] doubleValue], [bb[@"y"] doubleValue],
                                      [bb[@"width"] doubleValue], [bb[@"height"] doubleValue]);
                SVGRectShape *box = [SVGRectShape shapeWithRect:r];
                box.cssClass   = [NSString stringWithFormat:@"ov-box %@", colorCls];
                box.layerID    = @"layer-boxes";
                box.label      = OVBoxLabelFromElement(element, elementName);
                box.confidence = OVBoxConfidenceFromElement(element);
                [shapes addObject:box];
            }

            // ── quad (OCR text-line quadrilateral) ────────────────────────────
            NSDictionary *quad = element[@"quad"];
            if ([quad isKindOfClass:[NSDictionary class]]) {
                NSArray<NSString *> *cornerKeys =
                    @[@"topLeft", @"topRight", @"bottomRight", @"bottomLeft"];
                NSMutableArray<NSValue *> *qpts = [NSMutableArray arrayWithCapacity:4];
                BOOL ok = YES;
                for (NSString *k in cornerKeys) {
                    NSDictionary *c = quad[k];
                    if (![c isKindOfClass:[NSDictionary class]] || !c[@"x"] || !c[@"y"]) {
                        ok = NO; break;
                    }
                    [qpts addObject:[NSValue valueWithPoint:
                        NSMakePoint([c[@"x"] doubleValue], [c[@"y"] doubleValue])]];
                }
                if (ok && qpts.count == 4) {
                    SVGPolygonShape *q = [SVGPolygonShape shapeWithPoints:qpts];
                    q.cssClass   = [NSString stringWithFormat:@"ov-quad %@", colorCls];
                    q.layerID    = @"layer-quads";
                    q.confidence = element[@"confidence"] ? @([element[@"confidence"] doubleValue]) : nil;
                    NSString *text = element[@"text"];
                    if ([text isKindOfClass:[NSString class]] && text.length > 0)
                        q.label = text.length > 60
                            ? [[text substringToIndex:57] stringByAppendingString:@"…"]
                            : text;
                    [shapes addObject:q];
                }
            }

            // ── face landmarks ────────────────────────────────────────────────
            // One palette slot per landmark group (sorted keys → stable colours), offset
            // by element index so multiple faces do not all start on ov-c0.
            NSDictionary *landmarks = element[@"landmarks"];
            if ([landmarks isKindOfClass:[NSDictionary class]]) {
                NSArray *groupNames =
                    [[landmarks allKeys] sortedArrayUsingSelector:@selector(compare:)];
                NSUInteger lmSlot = 0;
                for (NSString *groupName in groupNames) {
                    NSArray *pts = landmarks[groupName];
                    if (![pts isKindOfClass:[NSArray class]] || pts.count == 0) continue;
                    NSMutableArray<NSValue *> *nspts = [NSMutableArray arrayWithCapacity:pts.count];
                    for (NSDictionary *p in pts)
                        [nspts addObject:[NSValue valueWithPoint:
                            NSMakePoint([p[@"x"] doubleValue], [p[@"y"] doubleValue])]];

                    NSString *lmColorCls =
                        OVColorClassForElementIndex(elemIdx + lmSlot);
                    lmSlot++;

                    if (nspts.count == 1) {
                        SVGPointShape *pt = [SVGPointShape shapeWithCenter:nspts[0].pointValue
                                                                     radius:3.0];
                        pt.cssClass = [NSString stringWithFormat:@"ov-point %@", lmColorCls];
                        pt.layerID  = @"layer-landmarks";
                        pt.label    = groupName;
                        [shapes addObject:pt];
                    } else {
                        SVGPolygonShape *lm = [SVGPolygonShape shapeWithPoints:nspts];
                        lm.cssClass = [NSString stringWithFormat:@"ov-landmark %@", lmColorCls];
                        lm.layerID  = @"layer-landmarks";
                        lm.label    = groupName;
                        [shapes addObject:lm];
                    }
                }
            }

            // ── generic named-point dicts (joints, etc.) ──────────────────────
            // Skip VNRectangleObservation corner points (classify rectangles) — only the box should be labeled.
            NSSet *handled = [NSSet setWithObjects:@"boundingBox", @"confidence", @"quality",
                                                   @"landmarks", @"quad", @"labels",
                                                   @"topLeft", @"topRight", @"bottomLeft", @"bottomRight",
                                                   @"detectedPoints", @"equationCoefficients", nil];
            for (NSString *key in element) {
                if ([handled containsObject:key]) continue;
                id val = element[key];
                if (![val isKindOfClass:[NSDictionary class]]) continue;
                NSDictionary *d = (NSDictionary *)val;

                if (d[@"x"] && d[@"y"]) {
                    // Single named point at element top-level
                    CGPoint pt = CGPointMake([d[@"x"] doubleValue], [d[@"y"] doubleValue]);
                    SVGPointShape *sp = [SVGPointShape shapeWithCenter:pt radius:4.0];
                    sp.cssClass   = [NSString stringWithFormat:@"ov-joint %@", colorCls];
                    sp.layerID    = @"layer-joints";
                    sp.label      = key;
                    sp.confidence = d[@"confidence"] ? @([d[@"confidence"] doubleValue]) : nil;
                    [shapes addObject:sp];
                } else {
                    // Dict of named points — treat as joints map, draw bones too.
                    // Bones are emitted before joints so joints render on top.
                    NSMutableDictionary<NSString *, NSValue *> *positions =
                        [NSMutableDictionary dictionary];

                    for (NSString *jointName in d) {
                        id sv = d[jointName];
                        if (![sv isKindOfClass:[NSDictionary class]]) continue;
                        NSDictionary *sd = (NSDictionary *)sv;
                        if (!sd[@"x"] || !sd[@"y"]) continue;
                        CGPoint pt = CGPointMake([sd[@"x"] doubleValue], [sd[@"y"] doubleValue]);
                        positions[jointName] = [NSValue valueWithPoint:pt];
                    }

                    // Bones first
                    for (NSArray<NSString *> *pair in bodyBonePairs()) {
                        NSValue *aVal = positions[pair[0]];
                        NSValue *bVal = positions[pair[1]];
                        if (!aVal || !bVal) continue;
                        SVGLineShape *bone = [SVGLineShape shapeWithStart:aVal.pointValue
                                                                      end:bVal.pointValue];
                        bone.cssClass = [NSString stringWithFormat:@"ov-bone %@", colorCls];
                        bone.layerID  = @"layer-bones";
                        [shapes addObject:bone];
                    }

                    // Then joints on top
                    for (NSString *jointName in d) {
                        id sv = d[jointName];
                        if (![sv isKindOfClass:[NSDictionary class]]) continue;
                        NSDictionary *sd = (NSDictionary *)sv;
                        if (!sd[@"x"] || !sd[@"y"]) continue;
                        CGPoint pt = CGPointMake([sd[@"x"] doubleValue], [sd[@"y"] doubleValue]);
                        SVGPointShape *joint = [SVGPointShape shapeWithCenter:pt radius:4.0];
                        joint.cssClass   = [NSString stringWithFormat:@"ov-joint %@", colorCls];
                        joint.layerID    = @"layer-joints";
                        joint.label      = jointName;
                        joint.confidence = sd[@"confidence"] ? @([sd[@"confidence"] doubleValue]) : nil;
                        [shapes addObject:joint];
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
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                @"--json <path> is required"}];
        return NO;
    }

    NSData *data = [NSData dataWithContentsOfFile:self.jsonPath options:0 error:error];
    if (!data) return NO;
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) return NO;

    NSDictionary *doc = json;
    if ([json[@"cliVersion"] isKindOfClass:[NSString class]] &&
        [json[@"result"] isKindOfClass:[NSDictionary class]])
        doc = json[@"result"];

    NSString *imagePath = self.inputPath;
    if (!imagePath.length) {
        imagePath = doc[@"info"][@"filepath"];
        if (!imagePath.length && [json[@"input"] isKindOfClass:[NSString class]])
            imagePath = json[@"input"];
    }
    if (imagePath.length && ![imagePath hasPrefix:@"/"])
        imagePath = [[NSFileManager defaultManager].currentDirectoryPath
                     stringByAppendingPathComponent:imagePath];

    SVGOverlay *overlay = [[SVGOverlay alloc] initWithImagePath:imagePath];
    [overlay addShapes:OVShapesFromJSON(doc)];

    NSString *base    = [[self.jsonPath lastPathComponent] stringByDeletingPathExtension];
    NSString *svgName = [base stringByAppendingPathExtension:@"svg"];
    NSString *outPath;
    if (self.svgOutput.length) {
        BOOL isDir = NO;
        if ([[NSFileManager defaultManager] fileExistsAtPath:self.svgOutput isDirectory:&isDir] && isDir)
            outPath = [self.svgOutput stringByAppendingPathComponent:svgName];
        else
            outPath = self.svgOutput;
    } else {
        outPath = [[self.jsonPath stringByDeletingLastPathComponent]
                   stringByAppendingPathComponent:svgName];
    }

    if (![overlay writeToPath:outPath error:error]) return NO;
    NSDictionary *payload = @{ @"svgPath": MVRelativePath(outPath), @"sourceJson": MVRelativePath(self.jsonPath) };
    NSArray *arts = @[
        MVArtifactEntry(outPath, @"svg"),
        MVArtifactEntry(self.jsonPath, @"source_json"),
    ];
    NSDictionary *result = MVResultByMergingArtifacts(payload, arts);
    NSDictionary *envelope = MVMakeEnvelope(@"overlay", @"svg", imagePath, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

@end
