#import "main.h"
#import "../svg/main.h"
#import <Cocoa/Cocoa.h>
#import <Vision/Vision.h>

static NSString * const FaceErrorDomain = @"FaceError";
typedef NS_ENUM(NSInteger, FaceErrorCode) {
    FaceErrorMissingInput    = 1,
    FaceErrorImageLoadFailed = 2,
    FaceErrorRequestFailed   = 3,
    FaceErrorEncodeFailed    = 4,
    FaceErrorUnsupportedOS   = 5,
};

// ── coordinate helpers ────────────────────────────────────────────────────────

// Bounding box: Vision uses bottom-left origin; flip y to top-left for output
static NSDictionary *boxDict(CGRect r) {
    return @{
        @"x":      @(r.origin.x),
        @"y":      @(1.0 - r.origin.y - r.size.height),
        @"width":  @(r.size.width),
        @"height": @(r.size.height),
    };
}

// Landmark points are in face-bounding-box space; convert to image-normalized top-left coords
static NSArray<NSDictionary *> *landmarkPts(VNFaceLandmarkRegion2D * _Nullable region, CGRect bbox) {
    if (!region || region.pointCount == 0) return @[];
    const CGPoint *raw = region.normalizedPoints;
    NSMutableArray *out = [NSMutableArray arrayWithCapacity:region.pointCount];
    for (NSUInteger i = 0; i < region.pointCount; i++) {
        CGFloat imgX = bbox.origin.x + raw[i].x * bbox.size.width;
        CGFloat imgY = bbox.origin.y + raw[i].y * bbox.size.height;
        [out addObject:@{@"x": @(imgX), @"y": @(1.0 - imgY)}];
    }
    return out;
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

@implementation FaceProcessor

- (instancetype)init {
    if ((self = [super init])) {
        _svgLabels = NO;
    }
    return self;
}

// ── public entry point ────────────────────────────────────────────────────────

- (BOOL)runWithError:(NSError **)error {
    NSString *op = self.operation.length ? self.operation : @"face-rectangles";
    if (self.img) {
        return [self processImage:self.img outputDir:self.output operation:op error:error];
    } else if (self.imgDir) {
        return [self processBatch:self.imgDir outputDir:self.outputDir operation:op error:error];
    }
    if (error) {
        *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorMissingInput
                                userInfo:@{NSLocalizedDescriptionKey: @"Either --img or --img-dir must be provided"}];
    }
    return NO;
}

// ── single image ──────────────────────────────────────────────────────────────

- (BOOL)processImage:(NSString *)imagePath outputDir:(nullable NSString *)outputDir operation:(NSString *)op error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (outputDir && ![fm fileExistsAtPath:outputDir]) {
        if (![fm createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    }
    NSString *base = [[imagePath lastPathComponent] stringByDeletingPathExtension];

    if ([op isEqualToString:@"face-rectangles"])
        return [self runFaceRectangles:imagePath base:base outputDir:outputDir error:error];
    if ([op isEqualToString:@"face-landmarks"])
        return [self runFaceLandmarks:imagePath base:base outputDir:outputDir error:error];
    if ([op isEqualToString:@"face-quality"])
        return [self runFaceQuality:imagePath base:base outputDir:outputDir error:error];
    if ([op isEqualToString:@"human-rectangles"])
        return [self runHumanRectangles:imagePath base:base outputDir:outputDir error:error];
    if ([op isEqualToString:@"body-pose"])
        return [self runBodyPose:imagePath base:base outputDir:outputDir error:error];
    if ([op isEqualToString:@"hand-pose"])
        return [self runHandPose:imagePath base:base outputDir:outputDir error:error];
    if ([op isEqualToString:@"animal-pose"])
        return [self runAnimalPose:imagePath base:base outputDir:outputDir error:error];

    if (error) {
        *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorMissingInput
                                userInfo:@{NSLocalizedDescriptionKey:
                                    [NSString stringWithFormat:@"Unknown operation '%@'. Supported: face-rectangles, face-landmarks, face-quality, human-rectangles, body-pose, hand-pose, animal-pose", op]}];
    }
    return NO;
}

// ── batch mode ────────────────────────────────────────────────────────────────

- (BOOL)processBatch:(NSString *)imgDir outputDir:(nullable NSString *)outputDir operation:(NSString *)op error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (outputDir && ![fm fileExistsAtPath:outputDir]) {
        if (![fm createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:error]) return NO;
    }
    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:imgDir];
    NSMutableArray<NSString *> *imageFiles = [NSMutableArray array];
    NSString *filePath;
    while ((filePath = [enumerator nextObject])) {
        if ([self isImageFile:filePath]) [imageFiles addObject:filePath];
    }
    [imageFiles sortUsingSelector:@selector(compare:)];

    for (NSString *relativePath in imageFiles) {
        NSString *fullPath = [imgDir stringByAppendingPathComponent:relativePath];
        if (![self processImage:fullPath outputDir:outputDir operation:op error:error]) return NO;
    }
    return YES;
}

// ── face-rectangles (VNDetectFaceRectanglesRequest) ───────────────────────────

- (BOOL)runFaceRectangles:(NSString *)imagePath base:(NSString *)base outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    CGImageRef cg = [self loadCGImage:imagePath error:error];
    if (!cg) return NO;

    __block NSArray *results = nil;
    __block NSError *vnErr = nil;
    VNDetectFaceRectanglesRequest *req = [[VNDetectFaceRectanglesRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    BOOL ok = [handler performRequests:@[req] error:error];
    CGImageRelease(cg);
    if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

    NSMutableArray *faces = [NSMutableArray array];
    NSMutableArray<NSValue *> *debugBoxes = [NSMutableArray array];
    for (VNFaceObservation *obs in results) {
        [faces addObject:@{@"boundingBox": boxDict(obs.boundingBox), @"confidence": @(obs.confidence)}];
        [debugBoxes addObject:[NSValue valueWithRect:NSRectFromCGRect(CGRectMake(
            obs.boundingBox.origin.x,
            1.0 - obs.boundingBox.origin.y - obs.boundingBox.size.height,
            obs.boundingBox.size.width,
            obs.boundingBox.size.height))]];
    }

    NSDictionary *json = @{@"info": [self imageInfo:imagePath], @"operation": @"face-rectangles", @"faces": faces};
    if (![self saveJSON:json base:base suffix:@"face_rectangles" outputDir:outputDir imagePath:imagePath error:error]) return NO;
    if (self.debug && debugBoxes.count > 0) {
        NSString *dbgPath = [self debugPath:imagePath base:base suffix:@"face_rectangles"];
        [self drawDebug:imagePath boxes:debugBoxes points:@[] toPath:dbgPath error:nil];
    }
    return YES;
}

// ── face-landmarks (VNDetectFaceLandmarksRequest) ─────────────────────────────

- (BOOL)runFaceLandmarks:(NSString *)imagePath base:(NSString *)base outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    CGImageRef cg = [self loadCGImage:imagePath error:error];
    if (!cg) return NO;

    __block NSArray *results = nil;
    __block NSError *vnErr = nil;
    VNDetectFaceLandmarksRequest *req = [[VNDetectFaceLandmarksRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    BOOL ok = [handler performRequests:@[req] error:error];
    CGImageRelease(cg);
    if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

    NSMutableArray *faces = [NSMutableArray array];
    NSMutableArray<NSValue *> *debugBoxes = [NSMutableArray array];
    NSMutableArray<NSValue *> *debugPoints = [NSMutableArray array];

    for (VNFaceObservation *obs in results) {
        CGRect bbox = obs.boundingBox;
        NSMutableDictionary *face = [NSMutableDictionary dictionaryWithDictionary:@{
            @"boundingBox": boxDict(bbox),
            @"confidence":  @(obs.confidence),
        }];
        [debugBoxes addObject:[NSValue valueWithRect:NSRectFromCGRect(CGRectMake(
            bbox.origin.x, 1.0 - bbox.origin.y - bbox.size.height, bbox.size.width, bbox.size.height))]];

        VNFaceLandmarks2D *lm = obs.landmarks;
        if (lm) {
            NSMutableDictionary *landmarks = [NSMutableDictionary dictionary];
            void (^addRegion)(NSString *, VNFaceLandmarkRegion2D *) = ^(NSString *key, VNFaceLandmarkRegion2D *region) {
                NSArray *pts = landmarkPts(region, bbox);
                if (pts.count > 0) {
                    landmarks[key] = pts;
                    for (NSDictionary *p in pts) {
                        [debugPoints addObject:[NSValue valueWithPoint:NSMakePoint([p[@"x"] doubleValue], [p[@"y"] doubleValue])]];
                    }
                }
            };
            addRegion(@"faceContour",   lm.faceContour);
            addRegion(@"leftEye",       lm.leftEye);
            addRegion(@"rightEye",      lm.rightEye);
            addRegion(@"leftEyebrow",   lm.leftEyebrow);
            addRegion(@"rightEyebrow",  lm.rightEyebrow);
            addRegion(@"nose",          lm.nose);
            addRegion(@"noseCrest",     lm.noseCrest);
            addRegion(@"medianLine",    lm.medianLine);
            addRegion(@"outerLips",     lm.outerLips);
            addRegion(@"innerLips",     lm.innerLips);
            addRegion(@"leftPupil",     lm.leftPupil);
            addRegion(@"rightPupil",    lm.rightPupil);
            face[@"landmarks"] = landmarks;
        }
        [faces addObject:face];
    }

    NSDictionary *json = @{@"info": [self imageInfo:imagePath], @"operation": @"face-landmarks", @"faces": faces};
    if (![self saveJSON:json base:base suffix:@"face_landmarks" outputDir:outputDir imagePath:imagePath error:error]) return NO;
    if (self.debug && (debugBoxes.count > 0 || debugPoints.count > 0)) {
        NSString *dbgPath = [self debugPath:imagePath base:base suffix:@"face_landmarks"];
        [self drawDebug:imagePath boxes:debugBoxes points:debugPoints toPath:dbgPath error:nil];
    }
    return YES;
}

// ── face-quality (VNDetectFaceCaptureQualityRequest) ──────────────────────────

- (BOOL)runFaceQuality:(NSString *)imagePath base:(NSString *)base outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    CGImageRef cg = [self loadCGImage:imagePath error:error];
    if (!cg) return NO;

    __block NSArray *results = nil;
    __block NSError *vnErr = nil;
    VNDetectFaceCaptureQualityRequest *req = [[VNDetectFaceCaptureQualityRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    BOOL ok = [handler performRequests:@[req] error:error];
    CGImageRelease(cg);
    if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

    NSMutableArray *faces = [NSMutableArray array];
    NSMutableArray<NSValue *> *debugBoxes = [NSMutableArray array];
    for (VNFaceObservation *obs in results) {
        NSMutableDictionary *face = [NSMutableDictionary dictionaryWithDictionary:@{
            @"boundingBox": boxDict(obs.boundingBox),
        }];
        if (obs.faceCaptureQuality) face[@"quality"] = obs.faceCaptureQuality;
        [faces addObject:face];
        [debugBoxes addObject:[NSValue valueWithRect:NSRectFromCGRect(CGRectMake(
            obs.boundingBox.origin.x,
            1.0 - obs.boundingBox.origin.y - obs.boundingBox.size.height,
            obs.boundingBox.size.width, obs.boundingBox.size.height))]];
    }

    NSDictionary *json = @{@"info": [self imageInfo:imagePath], @"operation": @"face-quality", @"faces": faces};
    if (![self saveJSON:json base:base suffix:@"face_quality" outputDir:outputDir imagePath:imagePath error:error]) return NO;
    if (self.debug && debugBoxes.count > 0) {
        NSString *dbgPath = [self debugPath:imagePath base:base suffix:@"face_quality"];
        [self drawDebug:imagePath boxes:debugBoxes points:@[] toPath:dbgPath error:nil];
    }
    return YES;
}

// ── human-rectangles (VNDetectHumanRectanglesRequest, macOS 11+) ──────────────

- (BOOL)runHumanRectangles:(NSString *)imagePath base:(NSString *)base outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    if (@available(macOS 12.0, *)) {
        CGImageRef cg = [self loadCGImage:imagePath error:error];
        if (!cg) return NO;

        __block NSArray *results = nil;
        __block NSError *vnErr = nil;
        VNDetectHumanRectanglesRequest *req = [[VNDetectHumanRectanglesRequest alloc]
            initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        BOOL ok = [handler performRequests:@[req] error:error];
        CGImageRelease(cg);
        if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

        NSMutableArray *humans = [NSMutableArray array];
        NSMutableArray<NSValue *> *debugBoxes = [NSMutableArray array];
        for (VNHumanObservation *obs in results) {
            [humans addObject:@{
                @"boundingBox":  boxDict(obs.boundingBox),
                @"confidence":   @(obs.confidence),
                @"upperBodyOnly": @(obs.upperBodyOnly),
            }];
            [debugBoxes addObject:[NSValue valueWithRect:NSRectFromCGRect(CGRectMake(
                obs.boundingBox.origin.x,
                1.0 - obs.boundingBox.origin.y - obs.boundingBox.size.height,
                obs.boundingBox.size.width, obs.boundingBox.size.height))]];
        }

        NSDictionary *json = @{@"info": [self imageInfo:imagePath], @"operation": @"human-rectangles", @"humans": humans};
        if (![self saveJSON:json base:base suffix:@"human_rectangles" outputDir:outputDir imagePath:imagePath error:error]) return NO;
        if (self.debug && debugBoxes.count > 0) {
            NSString *dbgPath = [self debugPath:imagePath base:base suffix:@"human_rectangles"];
            [self drawDebug:imagePath boxes:debugBoxes points:@[] toPath:dbgPath error:nil];
        }
        return YES;
    } else {
        if (error) *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"human-rectangles requires macOS 12.0+"}];
        return NO;
    }
}

// ── body-pose (VNDetectHumanBodyPoseRequest, macOS 11+) ───────────────────────

- (BOOL)runBodyPose:(NSString *)imagePath base:(NSString *)base outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    if (@available(macOS 11.0, *)) {
        CGImageRef cg = [self loadCGImage:imagePath error:error];
        if (!cg) return NO;

        __block NSArray *results = nil;
        __block NSError *vnErr = nil;
        VNDetectHumanBodyPoseRequest *req = [[VNDetectHumanBodyPoseRequest alloc]
            initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        BOOL ok = [handler performRequests:@[req] error:error];
        CGImageRelease(cg);
        if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

        NSMutableArray *bodies = [NSMutableArray array];
        NSMutableArray<NSValue *> *debugPoints = [NSMutableArray array];

        for (VNHumanBodyPoseObservation *obs in results) {
            NSMutableDictionary *joints = [NSMutableDictionary dictionary];
            NSArray<VNHumanBodyPoseObservationJointName> *names = obs.availableJointNames;
            for (VNHumanBodyPoseObservationJointName name in names) {
                NSError *ptErr = nil;
                VNRecognizedPoint *pt = [obs recognizedPointForJointName:name error:&ptErr];
                if (pt && pt.confidence > 0) {
                    joints[name] = @{
                        @"x":          @(pt.location.x),
                        @"y":          @(1.0 - pt.location.y),
                        @"confidence": @(pt.confidence),
                    };
                    [debugPoints addObject:[NSValue valueWithPoint:NSMakePoint(pt.location.x, 1.0 - pt.location.y)]];
                }
            }
            [bodies addObject:@{@"confidence": @(obs.confidence), @"joints": joints}];
        }

        NSDictionary *json = @{@"info": [self imageInfo:imagePath], @"operation": @"body-pose", @"bodies": bodies};
        if (![self saveJSON:json base:base suffix:@"body_pose" outputDir:outputDir imagePath:imagePath error:error]) return NO;
        if (self.debug && debugPoints.count > 0) {
            NSString *dbgPath = [self debugPath:imagePath base:base suffix:@"body_pose"];
            [self drawDebug:imagePath boxes:@[] points:debugPoints toPath:dbgPath error:nil];
        }
        return YES;
    } else {
        if (error) *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"body-pose requires macOS 11.0+"}];
        return NO;
    }
}

// ── hand-pose (VNDetectHumanHandPoseRequest, macOS 11+) ───────────────────────

- (BOOL)runHandPose:(NSString *)imagePath base:(NSString *)base outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    if (@available(macOS 11.0, *)) {
        CGImageRef cg = [self loadCGImage:imagePath error:error];
        if (!cg) return NO;

        __block NSArray *results = nil;
        __block NSError *vnErr = nil;
        VNDetectHumanHandPoseRequest *req = [[VNDetectHumanHandPoseRequest alloc]
            initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];
        req.maximumHandCount = 2;

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        BOOL ok = [handler performRequests:@[req] error:error];
        CGImageRelease(cg);
        if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

        NSMutableArray *hands = [NSMutableArray array];
        NSMutableArray<NSValue *> *debugPoints = [NSMutableArray array];

        for (VNHumanHandPoseObservation *obs in results) {
            NSString *chirality = @"unknown";
            if (@available(macOS 12.0, *)) {
                switch (obs.chirality) {
                    case VNChiralityLeft:  chirality = @"left";  break;
                    case VNChiralityRight: chirality = @"right"; break;
                    default: break;
                }
            }
            NSMutableDictionary *joints = [NSMutableDictionary dictionary];
            NSArray<VNHumanHandPoseObservationJointName> *names = obs.availableJointNames;
            for (VNHumanHandPoseObservationJointName name in names) {
                NSError *ptErr = nil;
                VNRecognizedPoint *pt = [obs recognizedPointForJointName:name error:&ptErr];
                if (pt && pt.confidence > 0) {
                    joints[name] = @{
                        @"x":          @(pt.location.x),
                        @"y":          @(1.0 - pt.location.y),
                        @"confidence": @(pt.confidence),
                    };
                    [debugPoints addObject:[NSValue valueWithPoint:NSMakePoint(pt.location.x, 1.0 - pt.location.y)]];
                }
            }
            [hands addObject:@{@"chirality": chirality, @"confidence": @(obs.confidence), @"joints": joints}];
        }

        NSDictionary *json = @{@"info": [self imageInfo:imagePath], @"operation": @"hand-pose", @"hands": hands};
        if (![self saveJSON:json base:base suffix:@"hand_pose" outputDir:outputDir imagePath:imagePath error:error]) return NO;
        if (self.debug && debugPoints.count > 0) {
            NSString *dbgPath = [self debugPath:imagePath base:base suffix:@"hand_pose"];
            [self drawDebug:imagePath boxes:@[] points:debugPoints toPath:dbgPath error:nil];
        }
        return YES;
    } else {
        if (error) *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"hand-pose requires macOS 11.0+"}];
        return NO;
    }
}

// ── animal-pose (VNDetectAnimalBodyPoseRequest, macOS 14+) ────────────────────

- (BOOL)runAnimalPose:(NSString *)imagePath base:(NSString *)base outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    if (@available(macOS 14.0, *)) {
        CGImageRef cg = [self loadCGImage:imagePath error:error];
        if (!cg) return NO;

        __block NSArray *results = nil;
        __block NSError *vnErr = nil;
        VNDetectAnimalBodyPoseRequest *req = [[VNDetectAnimalBodyPoseRequest alloc]
            initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        BOOL ok = [handler performRequests:@[req] error:error];
        CGImageRelease(cg);
        if (!ok || vnErr) { if (vnErr && error) *error = vnErr; return ok && !vnErr; }

        NSMutableArray *animals = [NSMutableArray array];
        NSMutableArray<NSValue *> *debugPoints = [NSMutableArray array];

        for (VNAnimalBodyPoseObservation *obs in results) {
            NSMutableDictionary *joints = [NSMutableDictionary dictionary];
            NSArray<VNAnimalBodyPoseObservationJointName> *names = obs.availableJointNames;
            for (VNAnimalBodyPoseObservationJointName name in names) {
                NSError *ptErr = nil;
                VNRecognizedPoint *pt = [obs recognizedPointForJointName:name error:&ptErr];
                if (pt && pt.confidence > 0) {
                    joints[name] = @{
                        @"x":          @(pt.location.x),
                        @"y":          @(1.0 - pt.location.y),
                        @"confidence": @(pt.confidence),
                    };
                    [debugPoints addObject:[NSValue valueWithPoint:NSMakePoint(pt.location.x, 1.0 - pt.location.y)]];
                }
            }
            [animals addObject:@{@"confidence": @(obs.confidence), @"joints": joints}];
        }

        NSDictionary *json = @{@"info": [self imageInfo:imagePath], @"operation": @"animal-pose", @"animals": animals};
        if (![self saveJSON:json base:base suffix:@"animal_pose" outputDir:outputDir imagePath:imagePath error:error]) return NO;
        if (self.debug && debugPoints.count > 0) {
            NSString *dbgPath = [self debugPath:imagePath base:base suffix:@"animal_pose"];
            [self drawDebug:imagePath boxes:@[] points:debugPoints toPath:dbgPath error:nil];
        }
        return YES;
    } else {
        if (error) *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"animal-pose requires macOS 14.0+"}];
        return NO;
    }
}

// ── helpers ───────────────────────────────────────────────────────────────────

- (nullable CGImageRef)loadCGImage:(NSString *)imagePath error:(NSError **)error {
    NSImage *image = [[NSImage alloc] initByReferencingFile:imagePath];
    if (!image) {
        if (error) *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorImageLoadFailed
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Failed to load image: %@", imagePath]}];
        return NULL;
    }
    CGImageRef cg = [image CGImageForProposedRect:nil context:nil hints:nil];
    if (!cg) {
        if (error) *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorImageLoadFailed
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Failed to convert image: %@", imagePath]}];
        return NULL;
    }
    CGImageRetain(cg);
    return cg;
}

- (NSDictionary *)imageInfo:(NSString *)imagePath {
    NSString *abs = [imagePath hasPrefix:@"/"]
        ? imagePath
        : [[NSFileManager defaultManager].currentDirectoryPath stringByAppendingPathComponent:imagePath];
    NSImage *img = [[NSImage alloc] initByReferencingFile:imagePath];
    CGImageRef cg = img ? [img CGImageForProposedRect:nil context:nil hints:nil] : NULL;
    return @{
        @"filename": [imagePath lastPathComponent],
        @"filepath": abs,
        @"width":    @(cg ? CGImageGetWidth(cg)  : 0),
        @"height":   @(cg ? CGImageGetHeight(cg) : 0),
    };
}

- (BOOL)saveJSON:(NSDictionary *)json
            base:(NSString *)base
          suffix:(NSString *)suffix
       outputDir:(nullable NSString *)outputDir
       imagePath:(NSString *)imagePath
           error:(NSError **)error {
    NSData *data = [NSJSONSerialization dataWithJSONObject:json options:NSJSONWritingPrettyPrinted error:error];
    if (!data) return NO;
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];

    if (outputDir) {
        NSString *filename = [NSString stringWithFormat:@"%@_%@.json", base, suffix];
        NSString *path = [outputDir stringByAppendingPathComponent:filename];
        if (![str writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:error]) return NO;
        printf("Saved: %s\n", path.UTF8String);
        if (self.svg) {
            SVGProcessor *svgProc = [[SVGProcessor alloc] init];
            svgProc.img        = imagePath;
            svgProc.jsonPath   = path;
            svgProc.output     = outputDir;
            svgProc.showLabels = self.svgLabels;
            [svgProc runWithError:nil];
        }
    } else {
        printf("%s\n", str.UTF8String);
    }
    return YES;
}

// boxes: NSRect values in top-left normalized coords; points: NSPoint values in top-left normalized coords
- (BOOL)drawDebug:(NSString *)imagePath
            boxes:(NSArray<NSValue *> *)boxes
           points:(NSArray<NSValue *> *)points
           toPath:(NSString *)outputPath
            error:(NSError **)error {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
    if (!image) return NO;

    NSSize size = image.size;
    NSImage *out = [[NSImage alloc] initWithSize:size];
    [out lockFocus];
    [image drawInRect:NSMakeRect(0, 0, size.width, size.height)];

    if (boxes.count > 0) {
        [[NSColor redColor] setStroke];
        for (NSValue *v in boxes) {
            NSRect norm = v.rectValue; // top-left normalized
            CGFloat sx = norm.origin.x * size.width;
            CGFloat sy = (1.0 - norm.origin.y - norm.size.height) * size.height; // flip to bottom-left screen
            NSBezierPath *path = [NSBezierPath bezierPathWithRect:NSMakeRect(sx, sy, norm.size.width * size.width, norm.size.height * size.height)];
            path.lineWidth = 2.0;
            [path stroke];
        }
    }

    if (points.count > 0) {
        [[NSColor colorWithCalibratedRed:0 green:1 blue:0 alpha:0.9] setFill];
        for (NSValue *v in points) {
            NSPoint norm = v.pointValue; // top-left normalized
            CGFloat sx = norm.x * size.width;
            CGFloat sy = (1.0 - norm.y) * size.height; // flip to bottom-left screen
            [[NSBezierPath bezierPathWithOvalInRect:NSMakeRect(sx - 3, sy - 3, 6, 6)] fill];
        }
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
        if (error) *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorEncodeFailed
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode debug image"}];
        return NO;
    }
    // Replace path extension with chosen format
    NSString *finalPath = [[outputPath stringByDeletingPathExtension] stringByAppendingPathExtension:ext];
    if (![imgData writeToFile:finalPath options:NSDataWritingAtomic error:error]) return NO;
    printf("Debug image saved to: %s\n", finalPath.UTF8String);
    return YES;
}

- (NSString *)debugPath:(NSString *)imagePath base:(NSString *)base suffix:(NSString *)suffix {
    NSString *dir = [imagePath stringByDeletingLastPathComponent];
    NSString *fmt = self.boxesFormat.length ? self.boxesFormat : @"png";
    NSString *filename = [NSString stringWithFormat:@"%@_%@_boxes.%@", base, suffix, extensionForFormat(fmt)];
    return [dir stringByAppendingPathComponent:filename];
}

- (BOOL)isImageFile:(NSString *)filePath {
    NSArray<NSString *> *extensions = @[@"jpg", @"jpeg", @"png", @"webp"];
    return [extensions containsObject:[filePath.pathExtension lowercaseString]];
}

@end
