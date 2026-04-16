#import "main.h"
#import "common/MVJsonEmit.h"
#import <Cocoa/Cocoa.h>
#import <Vision/Vision.h>

static NSString * const ClassifyErrorDomain = @"ClassifyError";
typedef NS_ENUM(NSInteger, ClassifyErrorCode) {
    ClassifyErrorMissingInput    = 1,
    ClassifyErrorImageLoadFailed = 2,
    ClassifyErrorRequestFailed   = 3,
    ClassifyErrorEncodeFailed    = 4,
    ClassifyErrorUnsupportedOS   = 5,
};

// ── coordinate helpers ────────────────────────────────────────────────────────

static NSDictionary *boxDict(CGRect r) {
    return @{
        @"x":      @(r.origin.x),
        @"y":      @(1.0 - r.origin.y - r.size.height),
        @"width":  @(r.size.width),
        @"height": @(r.size.height),
    };
}

static NSDictionary *cornerDict(CGPoint p) {
    return @{@"x": @(p.x), @"y": @(1.0 - p.y)};
}

// ── format helpers ────────────────────────────────────────────────────────────

static NSBitmapImageFileType bitmapTypeForFormat(NSString *fmt) {
    NSDictionary<NSString *, NSNumber *> *map = @{
        @"png":  @(NSBitmapImageFileTypePNG),
        @"jpg":  @(NSBitmapImageFileTypeJPEG),
        @"jpeg": @(NSBitmapImageFileTypeJPEG),
        @"tiff": @(NSBitmapImageFileTypeTIFF),
        @"tif":  @(NSBitmapImageFileTypeTIFF),
        @"bmp":  @(NSBitmapImageFileTypeBMP),
        @"gif":  @(NSBitmapImageFileTypeGIF),
    };
    NSNumber *type = map[[fmt lowercaseString]];
    return type ? (NSBitmapImageFileType)[type unsignedIntegerValue] : NSBitmapImageFileTypePNG;
}

static NSString *extensionForFormat(NSString *fmt) {
    NSDictionary<NSString *, NSString *> *map = @{
        @"png":  @"png",
        @"jpg":  @"jpg",
        @"jpeg": @"jpg",
        @"tiff": @"tiff",
        @"tif":  @"tiff",
        @"bmp":  @"bmp",
        @"gif":  @"gif",
    };
    return map[[fmt lowercaseString]] ?: @"png";
}

@implementation ClassifyProcessor

- (instancetype)init {
    return [super init];
}

// ── public entry point ────────────────────────────────────────────────────────

- (BOOL)runWithError:(NSError **)error {
    NSString *op = self.operation.length ? self.operation : @"classify";
    if (!self.inputPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:ClassifyErrorDomain code:ClassifyErrorMissingInput
                                    userInfo:@{NSLocalizedDescriptionKey: @"Provide --input <image>"}];
        }
        return NO;
    }
    return [self processImage:self.inputPath operation:op error:error];
}

- (BOOL)processImage:(NSString *)imagePath operation:(NSString *)op error:(NSError **)error {
    NSString *base = [[imagePath lastPathComponent] stringByDeletingPathExtension];

    if ([op isEqualToString:@"classify"])      return [self runClassify:imagePath base:base error:error];
    if ([op isEqualToString:@"animals"])       return [self runAnimals:imagePath base:base error:error];
    if ([op isEqualToString:@"rectangles"])    return [self runRectangles:imagePath base:base error:error];
    if ([op isEqualToString:@"horizon"])       return [self runHorizon:imagePath base:base error:error];
    if ([op isEqualToString:@"contours"])      return [self runContours:imagePath base:base error:error];
    if ([op isEqualToString:@"aesthetics"])    return [self runAesthetics:imagePath base:base error:error];
    if ([op isEqualToString:@"feature-print"]) return [self runFeaturePrint:imagePath base:base error:error];

    if (error) {
        *error = [NSError errorWithDomain:ClassifyErrorDomain code:ClassifyErrorMissingInput
                                userInfo:@{NSLocalizedDescriptionKey:
                                    [NSString stringWithFormat:@"Unknown operation '%@'. Supported: classify, animals, rectangles, horizon, contours, aesthetics, feature-print", op]}];
    }
    return NO;
}

// ── classify (VNClassifyImageRequest) ─────────────────────────────────────────

- (BOOL)runClassify:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
    CGImageRef cg = [self loadCGImage:imagePath error:error];
    if (!cg) return NO;

    __block NSArray *results = nil;
    __block NSError *vnErr = nil;
    VNClassifyImageRequest *req = [[VNClassifyImageRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    BOOL ok = [handler performRequests:@[req] error:error];
    CGImageRelease(cg);
    if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

    // Filter to meaningful confidence and sort descending
    NSMutableArray *classifications = [NSMutableArray array];
    for (VNClassificationObservation *obs in results) {
        if (obs.confidence >= 0.05f) {
            [classifications addObject:@{@"identifier": obs.identifier, @"confidence": @(obs.confidence)}];
        }
    }
    [classifications sortUsingDescriptors:@[[NSSortDescriptor sortDescriptorWithKey:@"confidence" ascending:NO]]];

    NSDictionary *json = @{
        @"info":            [self imageInfo:imagePath],
        @"operation":       @"classify",
        @"classifications": classifications,
    };
    return [self saveJSON:json artifactEntries:nil error:error];
}

// ── animals (VNRecognizeAnimalsRequest) ───────────────────────────────────────

- (BOOL)runAnimals:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
    CGImageRef cg = [self loadCGImage:imagePath error:error];
    if (!cg) return NO;

    __block NSArray *results = nil;
    __block NSError *vnErr = nil;
    VNRecognizeAnimalsRequest *req = [[VNRecognizeAnimalsRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    BOOL ok = [handler performRequests:@[req] error:error];
    CGImageRelease(cg);
    if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

    NSMutableArray *animals = [NSMutableArray array];
    NSMutableArray<NSValue *> *debugBoxes = [NSMutableArray array];
    for (VNRecognizedObjectObservation *obs in results) {
        NSMutableArray *labels = [NSMutableArray array];
        for (VNClassificationObservation *label in obs.labels) {
            [labels addObject:@{@"identifier": label.identifier, @"confidence": @(label.confidence)}];
        }
        [animals addObject:@{
            @"boundingBox": boxDict(obs.boundingBox),
            @"confidence":  @(obs.confidence),
            @"labels":      labels,
        }];
        [debugBoxes addObject:[NSValue valueWithRect:NSRectFromCGRect(CGRectMake(
            obs.boundingBox.origin.x,
            1.0 - obs.boundingBox.origin.y - obs.boundingBox.size.height,
            obs.boundingBox.size.width, obs.boundingBox.size.height))]];
    }

    NSDictionary *json = @{@"info": [self imageInfo:imagePath], @"operation": @"animals", @"animals": animals};
    NSMutableArray *artifactEntries = [NSMutableArray array];
    if (self.debug && debugBoxes.count > 0) {
        NSString *dbgPath = [self debugOutputPath:imagePath base:base suffix:@"animals"];
        if ([self drawDebug:imagePath boxes:debugBoxes toPath:dbgPath error:nil])
            [artifactEntries addObject:MVArtifactEntry(dbgPath, @"debug_overlay")];
    }
    return [self saveJSON:json artifactEntries:artifactEntries error:error];
}

// ── rectangles (VNDetectRectanglesRequest) ────────────────────────────────────

- (BOOL)runRectangles:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
    CGImageRef cg = [self loadCGImage:imagePath error:error];
    if (!cg) return NO;

    __block NSArray *results = nil;
    __block NSError *vnErr = nil;
    VNDetectRectanglesRequest *req = [[VNDetectRectanglesRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];
    req.maximumObservations = 16;
    req.minimumConfidence = 0.5f;
    req.minimumAspectRatio = 0.1f;
    req.maximumAspectRatio = 1.0f;

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    BOOL ok = [handler performRequests:@[req] error:error];
    CGImageRelease(cg);
    if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

    NSMutableArray *rects = [NSMutableArray array];
    NSMutableArray<NSValue *> *debugBoxes = [NSMutableArray array];
    for (VNRectangleObservation *obs in results) {
        [rects addObject:@{
            @"boundingBox":  boxDict(obs.boundingBox),
            @"confidence":   @(obs.confidence),
            @"topLeft":      cornerDict(obs.topLeft),
            @"topRight":     cornerDict(obs.topRight),
            @"bottomLeft":   cornerDict(obs.bottomLeft),
            @"bottomRight":  cornerDict(obs.bottomRight),
        }];
        [debugBoxes addObject:[NSValue valueWithRect:NSRectFromCGRect(CGRectMake(
            obs.boundingBox.origin.x,
            1.0 - obs.boundingBox.origin.y - obs.boundingBox.size.height,
            obs.boundingBox.size.width, obs.boundingBox.size.height))]];
    }

    NSDictionary *json = @{@"info": [self imageInfo:imagePath], @"operation": @"rectangles", @"rectangles": rects};
    NSMutableArray *artifactEntries = [NSMutableArray array];
    if (self.debug && debugBoxes.count > 0) {
        NSString *dbgPath = [self debugOutputPath:imagePath base:base suffix:@"rectangles"];
        if ([self drawDebug:imagePath boxes:debugBoxes toPath:dbgPath error:nil])
            [artifactEntries addObject:MVArtifactEntry(dbgPath, @"debug_overlay")];
    }
    return [self saveJSON:json artifactEntries:artifactEntries error:error];
}

// ── horizon (VNDetectHorizonRequest) ──────────────────────────────────────────

- (BOOL)runHorizon:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
    CGImageRef cg = [self loadCGImage:imagePath error:error];
    if (!cg) return NO;

    __block VNHorizonObservation *result = nil;
    __block NSError *vnErr = nil;
    VNDetectHorizonRequest *req = [[VNDetectHorizonRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; result = r.results.firstObject; }];

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    BOOL ok = [handler performRequests:@[req] error:error];
    CGImageRelease(cg);
    if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

    NSMutableDictionary *horizon = [NSMutableDictionary dictionary];
    if (result) {
        CGAffineTransform t = result.transform;
        horizon[@"angle"] = @(result.angle);
        horizon[@"angleDegrees"] = @(result.angle * 180.0 / M_PI);
        horizon[@"transform"] = @{
            @"a": @(t.a), @"b": @(t.b),
            @"c": @(t.c), @"d": @(t.d),
            @"tx": @(t.tx), @"ty": @(t.ty),
        };
    }

    NSDictionary *json = @{@"info": [self imageInfo:imagePath], @"operation": @"horizon", @"horizon": horizon};
    return [self saveJSON:json artifactEntries:nil error:error];
}

// ── contours (VNDetectContoursRequest, macOS 11+) ─────────────────────────────

- (BOOL)runContours:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
    if (@available(macOS 11.0, *)) {
        CGImageRef cg = [self loadCGImage:imagePath error:error];
        if (!cg) return NO;

        __block VNContoursObservation *result = nil;
        __block NSError *vnErr = nil;
        VNDetectContoursRequest *req = [[VNDetectContoursRequest alloc]
            initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; result = r.results.firstObject; }];
        req.contrastAdjustment = 1.0f;
        req.detectsDarkOnLight = YES;

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        BOOL ok = [handler performRequests:@[req] error:error];
        CGImageRelease(cg);
        if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

        NSMutableArray *topContours = [NSMutableArray array];
        if (result) {
            for (VNContour *contour in result.topLevelContours) {
                [topContours addObject:@{
                    @"pointCount":  @(contour.pointCount),
                    @"childCount":  @(contour.childContourCount),
                    @"aspectRatio": @(contour.aspectRatio),
                }];
            }
        }

        NSDictionary *json = @{
            @"info":          [self imageInfo:imagePath],
            @"operation":     @"contours",
            @"contourCount":  @(result ? result.contourCount : 0),
            @"topContours":   topContours,
        };
        return [self saveJSON:json artifactEntries:nil error:error];
    } else {
        if (error) *error = [NSError errorWithDomain:ClassifyErrorDomain code:ClassifyErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"contours requires macOS 11.0+"}];
        return NO;
    }
}

// ── aesthetics (VNCalculateImageAestheticsScoresRequest, macOS 15+) ───────────

- (BOOL)runAesthetics:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
    if (@available(macOS 15.0, *)) {
        CGImageRef cg = [self loadCGImage:imagePath error:error];
        if (!cg) return NO;

        __block VNImageAestheticsScoresObservation *result = nil;
        __block NSError *vnErr = nil;
        VNCalculateImageAestheticsScoresRequest *req = [[VNCalculateImageAestheticsScoresRequest alloc]
            initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; result = r.results.firstObject; }];

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        BOOL ok = [handler performRequests:@[req] error:error];
        CGImageRelease(cg);
        if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

        NSMutableDictionary *scores = [NSMutableDictionary dictionary];
        if (result) {
            scores[@"isUtility"]    = @(result.isUtility);
            scores[@"overallScore"] = @(result.overallScore);
        }

        NSDictionary *json = @{@"info": [self imageInfo:imagePath], @"operation": @"aesthetics", @"scores": scores};
        return [self saveJSON:json artifactEntries:nil error:error];
    } else {
        if (error) *error = [NSError errorWithDomain:ClassifyErrorDomain code:ClassifyErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"aesthetics requires macOS 15.0+"}];
        return NO;
    }
}

// ── feature-print (VNGenerateImageFeaturePrintRequest) ────────────────────────

- (BOOL)runFeaturePrint:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
    CGImageRef cg = [self loadCGImage:imagePath error:error];
    if (!cg) return NO;

    __block VNFeaturePrintObservation *result = nil;
    __block NSError *vnErr = nil;
    VNGenerateImageFeaturePrintRequest *req = [[VNGenerateImageFeaturePrintRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; result = r.results.firstObject; }];

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    BOOL ok = [handler performRequests:@[req] error:error];
    CGImageRelease(cg);
    if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

    NSMutableDictionary *featurePrint = [NSMutableDictionary dictionary];
    if (result) {
        NSString *elementTypeStr = (result.elementType == VNElementTypeFloat) ? @"float" : @"double";
        featurePrint[@"elementType"]  = elementTypeStr;
        featurePrint[@"elementCount"] = @(result.elementCount);
        featurePrint[@"data"]         = [result.data base64EncodedStringWithOptions:0];
    }

    NSDictionary *json = @{@"info": [self imageInfo:imagePath], @"operation": @"feature-print", @"featurePrint": featurePrint};
    return [self saveJSON:json artifactEntries:nil error:error];
}

// ── helpers ───────────────────────────────────────────────────────────────────

- (nullable CGImageRef)loadCGImage:(NSString *)imagePath error:(NSError **)error {
    NSImage *image = [[NSImage alloc] initByReferencingFile:imagePath];
    if (!image) {
        if (error) *error = [NSError errorWithDomain:ClassifyErrorDomain code:ClassifyErrorImageLoadFailed
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Failed to load image: %@", imagePath]}];
        return NULL;
    }
    CGImageRef cg = [image CGImageForProposedRect:nil context:nil hints:nil];
    if (!cg) {
        if (error) *error = [NSError errorWithDomain:ClassifyErrorDomain code:ClassifyErrorImageLoadFailed
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Failed to convert image: %@", imagePath]}];
        return NULL;
    }
    CGImageRetain(cg);
    return cg;
}

- (NSDictionary *)imageInfo:(NSString *)imagePath {
    NSImage *img = [[NSImage alloc] initByReferencingFile:imagePath];
    CGImageRef cg = img ? [img CGImageForProposedRect:nil context:nil hints:nil] : NULL;
    return @{
        @"filename": [imagePath lastPathComponent],
        @"filepath": MVRelativePath(imagePath),
        @"width":    @(cg ? CGImageGetWidth(cg)  : 0),
        @"height":   @(cg ? CGImageGetHeight(cg) : 0),
    };
}

- (BOOL)saveJSON:(NSDictionary *)json artifactEntries:(NSArray<NSDictionary *> *)artifactEntries error:(NSError **)error {
    NSString *op = json[@"operation"] ?: @"classify";
    NSDictionary *merged = MVResultByMergingArtifacts(json, artifactEntries ?: @[]);
    NSDictionary *envelope = MVMakeEnvelope(@"classify", op, self.inputPath, merged);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

- (BOOL)drawDebug:(NSString *)imagePath
            boxes:(NSArray<NSValue *> *)boxes
           toPath:(NSString *)outputPath
            error:(NSError **)error {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
    if (!image) return NO;

    NSString *parent = outputPath.stringByDeletingLastPathComponent;
    if (parent.length) {
        [[NSFileManager defaultManager] createDirectoryAtPath:parent
                                    withIntermediateDirectories:YES
                                                     attributes:nil
                                                          error:nil];
    }

    NSSize size = image.size;
    NSImage *out = [[NSImage alloc] initWithSize:size];
    [out lockFocus];
    [image drawInRect:NSMakeRect(0, 0, size.width, size.height)];

    [[NSColor redColor] setStroke];
    for (NSValue *v in boxes) {
        NSRect norm = v.rectValue;
        CGFloat sx = norm.origin.x * size.width;
        CGFloat sy = (1.0 - norm.origin.y - norm.size.height) * size.height;
        NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSMakeRect(sx, sy, norm.size.width * size.width, norm.size.height * size.height)];
        path.lineWidth = 2.0;
        [path stroke];
    }

    [out unlockFocus];

    NSString *fmt = self.boxesFormat.length ? self.boxesFormat : @"png";
    NSBitmapImageFileType bitmapType = bitmapTypeForFormat(fmt);
    NSString *ext = extensionForFormat(fmt);
    NSDictionary *props = (bitmapType == NSBitmapImageFileTypeJPEG) ? @{NSImageCompressionFactor: @(0.85)} : @{};

    NSData *tiff = [out TIFFRepresentation];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiff];
    NSData *imgData = [bitmap representationUsingType:bitmapType properties:props];
    if (!imgData) {
        if (error) *error = [NSError errorWithDomain:ClassifyErrorDomain code:ClassifyErrorEncodeFailed
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode debug image"}];
        return NO;
    }
    NSString *finalPath = [[outputPath stringByDeletingPathExtension] stringByAppendingPathExtension:ext];
    if (![imgData writeToFile:finalPath options:NSDataWritingAtomic error:error]) return NO;
    fprintf(stderr, "Debug image saved to: %s\n", finalPath.UTF8String);
    return YES;
}

- (NSString *)debugOutputPath:(NSString *)imagePath base:(NSString *)base suffix:(NSString *)suffix {
    NSString *dir = self.artifactsDir.length ? self.artifactsDir : [imagePath stringByDeletingLastPathComponent];
    NSString *fmt = self.boxesFormat.length ? self.boxesFormat : @"png";
    NSString *filename = [NSString stringWithFormat:@"%@_%@_boxes.%@", base, suffix, extensionForFormat(fmt)];
    return [dir stringByAppendingPathComponent:filename];
}

@end
