#import "main.h"
#import "common/MVJsonEmit.h"
#import "common/MVMjpegStream.h"
#import <Cocoa/Cocoa.h>
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>

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
    return [super init];
}

// ── public entry point ────────────────────────────────────────────────────────

- (BOOL)runWithError:(NSError **)error {
    if (self.stream) return [self runStreamWithError:error];
    NSString *op = self.operation.length ? self.operation : @"face-rectangles";
    if (!self.inputPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorMissingInput
                                    userInfo:@{NSLocalizedDescriptionKey: @"Provide --input <image> (or --stream for pipeline mode)"}];
        }
        return NO;
    }
    return [self processImage:self.inputPath operation:op error:error];
}

// ── stream mode ───────────────────────────────────────────────────────────────

- (BOOL)runStreamWithError:(NSError **)error {
    NSString *op = self.operation.length ? self.operation : @"face-rectangles";
    NSString *headerKey = [NSString stringWithFormat:@"X-MV-face-%@", op];

    MVMjpegReader *reader = [[MVMjpegReader alloc] initWithFileDescriptor:STDIN_FILENO];
    MVMjpegWriter *writer = [[MVMjpegWriter alloc] initWithFileDescriptor:STDOUT_FILENO];

    [reader readFramesWithHandler:^(NSData *jpeg, NSDictionary<NSString *, NSString *> *inHeaders) {
        // Decode JPEG → CGImageRef
        CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)jpeg, nil);
        CGImageRef cg = src ? CGImageSourceCreateImageAtIndex(src, 0, nil) : NULL;
        if (src) CFRelease(src);

        // Pass-through all headers except Content-Type / Content-Length (re-added by writer)
        NSMutableDictionary<NSString *, NSString *> *outHeaders = [NSMutableDictionary dictionaryWithDictionary:inHeaders];
        [outHeaders removeObjectForKey:@"Content-Type"];
        [outHeaders removeObjectForKey:@"Content-Length"];

        if (cg) {
            NSDictionary *result = [self detectCGImage:cg operation:op];
            CGImageRelease(cg);
            if (result) {
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
                if (jsonData)
                    outHeaders[headerKey] = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            }
        }

        [writer writeFrame:jpeg extraHeaders:outHeaders];
    }];

    return YES;
}

/// Run detection on a CGImageRef and return the result dict (operation + detections), or nil on failure.
- (nullable NSDictionary *)detectCGImage:(CGImageRef)cg operation:(NSString *)op {
    if ([op isEqualToString:@"face-rectangles"])   return [self detectFaceRectangles:cg];
    if ([op isEqualToString:@"face-landmarks"])    return [self detectFaceLandmarks:cg];
    if ([op isEqualToString:@"face-quality"])      return [self detectFaceQuality:cg];
    if ([op isEqualToString:@"human-rectangles"])  return [self detectHumanRectangles:cg];
    if ([op isEqualToString:@"body-pose"])         return [self detectBodyPose:cg];
    if ([op isEqualToString:@"hand-pose"])         return [self detectHandPose:cg];
    if ([op isEqualToString:@"animal-pose"])       return [self detectAnimalPose:cg];
    return nil;
}

- (nullable NSDictionary *)detectFaceRectangles:(CGImageRef)cg {
    __block NSArray *results = nil;
    __block NSError *vnErr = nil;
    VNDetectFaceRectanglesRequest *req = [[VNDetectFaceRectanglesRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];
    VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    if (![h performRequests:@[req] error:nil] || vnErr) return nil;
    NSMutableArray *faces = [NSMutableArray array];
    for (VNFaceObservation *obs in results)
        [faces addObject:@{@"boundingBox": boxDict(obs.boundingBox), @"confidence": @(obs.confidence)}];
    return @{@"operation": @"face-rectangles", @"faces": faces};
}

- (nullable NSDictionary *)detectFaceLandmarks:(CGImageRef)cg {
    __block NSArray *results = nil;
    __block NSError *vnErr = nil;
    VNDetectFaceLandmarksRequest *req = [[VNDetectFaceLandmarksRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];
    VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    if (![h performRequests:@[req] error:nil] || vnErr) return nil;
    NSMutableArray *faces = [NSMutableArray array];
    for (VNFaceObservation *obs in results) {
        CGRect bbox = obs.boundingBox;
        NSMutableDictionary *face = [NSMutableDictionary dictionaryWithDictionary:
            @{@"boundingBox": boxDict(bbox), @"confidence": @(obs.confidence)}];
        VNFaceLandmarks2D *lm = obs.landmarks;
        if (lm) {
            NSMutableDictionary *landmarks = [NSMutableDictionary dictionary];
            void (^add)(NSString *, VNFaceLandmarkRegion2D *) = ^(NSString *key, VNFaceLandmarkRegion2D *region) {
                NSArray *pts = landmarkPts(region, bbox);
                if (pts.count > 0) landmarks[key] = pts;
            };
            add(@"faceContour",  lm.faceContour);  add(@"leftEye",      lm.leftEye);
            add(@"rightEye",     lm.rightEye);      add(@"leftEyebrow",  lm.leftEyebrow);
            add(@"rightEyebrow", lm.rightEyebrow);  add(@"nose",         lm.nose);
            add(@"noseCrest",    lm.noseCrest);      add(@"medianLine",   lm.medianLine);
            add(@"outerLips",    lm.outerLips);      add(@"innerLips",    lm.innerLips);
            add(@"leftPupil",    lm.leftPupil);      add(@"rightPupil",   lm.rightPupil);
            face[@"landmarks"] = landmarks;
        }
        [faces addObject:face];
    }
    return @{@"operation": @"face-landmarks", @"faces": faces};
}

- (nullable NSDictionary *)detectFaceQuality:(CGImageRef)cg {
    __block NSArray *results = nil;
    __block NSError *vnErr = nil;
    VNDetectFaceCaptureQualityRequest *req = [[VNDetectFaceCaptureQualityRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];
    VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
    if (![h performRequests:@[req] error:nil] || vnErr) return nil;
    NSMutableArray *faces = [NSMutableArray array];
    for (VNFaceObservation *obs in results) {
        NSMutableDictionary *face = [NSMutableDictionary dictionaryWithDictionary:@{@"boundingBox": boxDict(obs.boundingBox)}];
        if (obs.faceCaptureQuality) face[@"quality"] = obs.faceCaptureQuality;
        [faces addObject:face];
    }
    return @{@"operation": @"face-quality", @"faces": faces};
}

- (nullable NSDictionary *)detectHumanRectangles:(CGImageRef)cg {
    if (@available(macOS 12.0, *)) {
        __block NSArray *results = nil;
        __block NSError *vnErr = nil;
        VNDetectHumanRectanglesRequest *req = [[VNDetectHumanRectanglesRequest alloc]
            initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];
        VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        if (![h performRequests:@[req] error:nil] || vnErr) return nil;
        NSMutableArray *humans = [NSMutableArray array];
        for (VNHumanObservation *obs in results)
            [humans addObject:@{@"boundingBox": boxDict(obs.boundingBox),
                                @"confidence": @(obs.confidence),
                                @"upperBodyOnly": @(obs.upperBodyOnly)}];
        return @{@"operation": @"human-rectangles", @"humans": humans};
    }
    return nil;
}

- (nullable NSDictionary *)detectBodyPose:(CGImageRef)cg {
    if (@available(macOS 11.0, *)) {
        __block NSArray *results = nil;
        __block NSError *vnErr = nil;
        VNDetectHumanBodyPoseRequest *req = [[VNDetectHumanBodyPoseRequest alloc]
            initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];
        VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        if (![h performRequests:@[req] error:nil] || vnErr) return nil;
        NSMutableArray *bodies = [NSMutableArray array];
        for (VNHumanBodyPoseObservation *obs in results) {
            NSMutableDictionary *joints = [NSMutableDictionary dictionary];
            for (VNHumanBodyPoseObservationJointName name in obs.availableJointNames) {
                VNRecognizedPoint *pt = [obs recognizedPointForJointName:name error:nil];
                if (pt && pt.confidence > 0)
                    joints[name] = @{@"x": @(pt.location.x), @"y": @(1.0 - pt.location.y), @"confidence": @(pt.confidence)};
            }
            [bodies addObject:@{@"confidence": @(obs.confidence), @"joints": joints}];
        }
        return @{@"operation": @"body-pose", @"bodies": bodies};
    }
    return nil;
}

- (nullable NSDictionary *)detectHandPose:(CGImageRef)cg {
    if (@available(macOS 11.0, *)) {
        __block NSArray *results = nil;
        __block NSError *vnErr = nil;
        VNDetectHumanHandPoseRequest *req = [[VNDetectHumanHandPoseRequest alloc]
            initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];
        req.maximumHandCount = 2;
        VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        if (![h performRequests:@[req] error:nil] || vnErr) return nil;
        NSMutableArray *hands = [NSMutableArray array];
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
            for (VNHumanHandPoseObservationJointName name in obs.availableJointNames) {
                VNRecognizedPoint *pt = [obs recognizedPointForJointName:name error:nil];
                if (pt && pt.confidence > 0)
                    joints[name] = @{@"x": @(pt.location.x), @"y": @(1.0 - pt.location.y), @"confidence": @(pt.confidence)};
            }
            [hands addObject:@{@"chirality": chirality, @"confidence": @(obs.confidence), @"joints": joints}];
        }
        return @{@"operation": @"hand-pose", @"hands": hands};
    }
    return nil;
}

- (nullable NSDictionary *)detectAnimalPose:(CGImageRef)cg {
    if (@available(macOS 14.0, *)) {
        __block NSArray *results = nil;
        __block NSError *vnErr = nil;
        VNDetectAnimalBodyPoseRequest *req = [[VNDetectAnimalBodyPoseRequest alloc]
            initWithCompletionHandler:^(VNRequest *r, NSError *e) { vnErr = e; results = r.results; }];
        VNImageRequestHandler *h = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
        if (![h performRequests:@[req] error:nil] || vnErr) return nil;
        NSMutableArray *animals = [NSMutableArray array];
        for (VNAnimalBodyPoseObservation *obs in results) {
            NSMutableDictionary *joints = [NSMutableDictionary dictionary];
            for (VNAnimalBodyPoseObservationJointName name in obs.availableJointNames) {
                VNRecognizedPoint *pt = [obs recognizedPointForJointName:name error:nil];
                if (pt && pt.confidence > 0)
                    joints[name] = @{@"x": @(pt.location.x), @"y": @(1.0 - pt.location.y), @"confidence": @(pt.confidence)};
            }
            [animals addObject:@{@"confidence": @(obs.confidence), @"joints": joints}];
        }
        return @{@"operation": @"animal-pose", @"animals": animals};
    }
    return nil;
}

- (BOOL)processImage:(NSString *)imagePath operation:(NSString *)op error:(NSError **)error {
    NSString *base = [[imagePath lastPathComponent] stringByDeletingPathExtension];

    if ([op isEqualToString:@"face-rectangles"])
        return [self runFaceRectangles:imagePath base:base error:error];
    if ([op isEqualToString:@"face-landmarks"])
        return [self runFaceLandmarks:imagePath base:base error:error];
    if ([op isEqualToString:@"face-quality"])
        return [self runFaceQuality:imagePath base:base error:error];
    if ([op isEqualToString:@"human-rectangles"])
        return [self runHumanRectangles:imagePath base:base error:error];
    if ([op isEqualToString:@"body-pose"])
        return [self runBodyPose:imagePath base:base error:error];
    if ([op isEqualToString:@"hand-pose"])
        return [self runHandPose:imagePath base:base error:error];
    if ([op isEqualToString:@"animal-pose"])
        return [self runAnimalPose:imagePath base:base error:error];

    if (error) {
        *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorMissingInput
                                userInfo:@{NSLocalizedDescriptionKey:
                                    [NSString stringWithFormat:@"Unknown operation '%@'. Supported: face-rectangles, face-landmarks, face-quality, human-rectangles, body-pose, hand-pose, animal-pose", op]}];
    }
    return NO;
}

// ── face-rectangles (VNDetectFaceRectanglesRequest) ───────────────────────────

- (BOOL)runFaceRectangles:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
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
    NSMutableArray *artifactEntries = [NSMutableArray array];
    if (self.debug && debugBoxes.count > 0) {
        NSString *dbgPath = [self debugOutputPath:imagePath base:base suffix:@"face_rectangles"];
        if ([self drawDebug:imagePath boxes:debugBoxes points:@[] toPath:dbgPath error:nil])
            [artifactEntries addObject:MVArtifactEntry(dbgPath, @"debug_overlay")];
    }
    return [self saveJSON:json artifactEntries:artifactEntries error:error];
}

// ── face-landmarks (VNDetectFaceLandmarksRequest) ─────────────────────────────

- (BOOL)runFaceLandmarks:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
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
    NSMutableArray *artifactEntries = [NSMutableArray array];
    if (self.debug && (debugBoxes.count > 0 || debugPoints.count > 0)) {
        NSString *dbgPath = [self debugOutputPath:imagePath base:base suffix:@"face_landmarks"];
        if ([self drawDebug:imagePath boxes:debugBoxes points:debugPoints toPath:dbgPath error:nil])
            [artifactEntries addObject:MVArtifactEntry(dbgPath, @"debug_overlay")];
    }
    return [self saveJSON:json artifactEntries:artifactEntries error:error];
}

// ── face-quality (VNDetectFaceCaptureQualityRequest) ──────────────────────────

- (BOOL)runFaceQuality:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
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
    NSMutableArray *artifactEntries = [NSMutableArray array];
    if (self.debug && debugBoxes.count > 0) {
        NSString *dbgPath = [self debugOutputPath:imagePath base:base suffix:@"face_quality"];
        if ([self drawDebug:imagePath boxes:debugBoxes points:@[] toPath:dbgPath error:nil])
            [artifactEntries addObject:MVArtifactEntry(dbgPath, @"debug_overlay")];
    }
    return [self saveJSON:json artifactEntries:artifactEntries error:error];
}

// ── human-rectangles (VNDetectHumanRectanglesRequest, macOS 11+) ──────────────

- (BOOL)runHumanRectangles:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
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
        NSMutableArray *artifactEntries = [NSMutableArray array];
        if (self.debug && debugBoxes.count > 0) {
            NSString *dbgPath = [self debugOutputPath:imagePath base:base suffix:@"human_rectangles"];
            if ([self drawDebug:imagePath boxes:debugBoxes points:@[] toPath:dbgPath error:nil])
                [artifactEntries addObject:MVArtifactEntry(dbgPath, @"debug_overlay")];
        }
        return [self saveJSON:json artifactEntries:artifactEntries error:error];
    } else {
        if (error) *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"human-rectangles requires macOS 12.0+"}];
        return NO;
    }
}

// ── body-pose (VNDetectHumanBodyPoseRequest, macOS 11+) ───────────────────────

- (BOOL)runBodyPose:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
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
        NSMutableArray *artifactEntries = [NSMutableArray array];
        if (self.debug && debugPoints.count > 0) {
            NSString *dbgPath = [self debugOutputPath:imagePath base:base suffix:@"body_pose"];
            if ([self drawDebug:imagePath boxes:@[] points:debugPoints toPath:dbgPath error:nil])
                [artifactEntries addObject:MVArtifactEntry(dbgPath, @"debug_overlay")];
        }
        return [self saveJSON:json artifactEntries:artifactEntries error:error];
    } else {
        if (error) *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"body-pose requires macOS 11.0+"}];
        return NO;
    }
}

// ── hand-pose (VNDetectHumanHandPoseRequest, macOS 11+) ───────────────────────

- (BOOL)runHandPose:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
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
        NSMutableArray *artifactEntries = [NSMutableArray array];
        if (self.debug && debugPoints.count > 0) {
            NSString *dbgPath = [self debugOutputPath:imagePath base:base suffix:@"hand_pose"];
            if ([self drawDebug:imagePath boxes:@[] points:debugPoints toPath:dbgPath error:nil])
                [artifactEntries addObject:MVArtifactEntry(dbgPath, @"debug_overlay")];
        }
        return [self saveJSON:json artifactEntries:artifactEntries error:error];
    } else {
        if (error) *error = [NSError errorWithDomain:FaceErrorDomain code:FaceErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"hand-pose requires macOS 11.0+"}];
        return NO;
    }
}

// ── animal-pose (VNDetectAnimalBodyPoseRequest, macOS 14+) ────────────────────

- (BOOL)runAnimalPose:(NSString *)imagePath base:(NSString *)base error:(NSError **)error {
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
        NSMutableArray *artifactEntries = [NSMutableArray array];
        if (self.debug && debugPoints.count > 0) {
            NSString *dbgPath = [self debugOutputPath:imagePath base:base suffix:@"animal_pose"];
            if ([self drawDebug:imagePath boxes:@[] points:debugPoints toPath:dbgPath error:nil])
                [artifactEntries addObject:MVArtifactEntry(dbgPath, @"debug_overlay")];
        }
        return [self saveJSON:json artifactEntries:artifactEntries error:error];
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
    NSString *op = json[@"operation"] ?: @"face";
    NSDictionary *merged = MVResultByMergingArtifacts(json, artifactEntries ?: @[]);
    NSDictionary *envelope = MVMakeEnvelope(@"face", op, self.inputPath, merged);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// boxes: NSRect values in top-left normalized coords; points: NSPoint values in top-left normalized coords
- (BOOL)drawDebug:(NSString *)imagePath
            boxes:(NSArray<NSValue *> *)boxes
           points:(NSArray<NSValue *> *)points
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
