#import "main.h"
#import "common/MVJsonEmit.h"
#import <Cocoa/Cocoa.h>
#import <Vision/Vision.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreMedia/CoreMedia.h>
#import <CoreImage/CoreImage.h>

static NSString * const TrackErrorDomain = @"TrackError";
typedef NS_ENUM(NSInteger, TrackErrorCode) {
    TrackErrorMissingInput    = 1,
    TrackErrorImageLoadFailed = 2,
    TrackErrorRequestFailed   = 3,
    TrackErrorEncodeFailed    = 4,
    TrackErrorUnsupportedOS   = 5,
    TrackErrorVideoLoadFailed = 6,
};

@implementation TrackProcessor

// ── public entry point ────────────────────────────────────────────────────────

- (BOOL)runWithError:(NSError **)error {
    NSString *op = self.operation.length ? self.operation : @"homographic";
    if (!self.inputPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorMissingInput
                                    userInfo:@{NSLocalizedDescriptionKey: @"Provide --input <video.mp4> or --input <frames-dir>"}];
        }
        return NO;
    }
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:self.inputPath isDirectory:&isDir]) {
        if (error) {
            *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorVideoLoadFailed
                                    userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:@"Path not found: %@", self.inputPath]}];
        }
        return NO;
    }
    if (isDir) {
        return [self processImageSequence:self.inputPath operation:op error:error];
    }
    return [self processVideo:self.inputPath operation:op error:error];
}

// ── image-sequence mode (VNSequenceRequestHandler) ────────────────────────────

- (BOOL)processImageSequence:(NSString *)imgDir operation:(NSString *)op error:(NSError **)error {
    if (@available(macOS 11.0, *)) {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (self.artifactsDir.length && ![fm fileExistsAtPath:self.artifactsDir]) {
            if (![fm createDirectoryAtPath:self.artifactsDir withIntermediateDirectories:YES attributes:nil error:error]) return NO;
        }

        // Collect sorted image files
        NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:imgDir];
        NSMutableArray<NSString *> *imageFiles = [NSMutableArray array];
        NSString *filePath;
        while ((filePath = [enumerator nextObject])) {
            if ([self isImageFile:filePath]) [imageFiles addObject:filePath];
        }
        [imageFiles sortUsingSelector:@selector(compare:)];

        if (imageFiles.count < 2) {
            if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorMissingInput
                                                userInfo:@{NSLocalizedDescriptionKey: @"At least 2 image frames required for tracking"}];
            return NO;
        }

        if ([op isEqualToString:@"homographic"])
            return [self runHomographicSequence:imageFiles imgDir:imgDir error:error];
        if ([op isEqualToString:@"translational"])
            return [self runTranslationalSequence:imageFiles imgDir:imgDir error:error];
        if ([op isEqualToString:@"optical-flow"])
            return [self runOpticalFlowSequence:imageFiles imgDir:imgDir error:error];
        if ([op isEqualToString:@"trajectories"])
            return [self runTrajectoriesSequence:imageFiles imgDir:imgDir error:error];

        if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorMissingInput
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Unknown operation '%@'. Supported: homographic, translational, optical-flow, trajectories", op]}];
        return NO;
    } else {
        if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"track requires macOS 11.0+"}];
        return NO;
    }
}

// ── video mode (VNVideoProcessor) ─────────────────────────────────────────────

- (BOOL)processVideo:(NSString *)videoPath operation:(NSString *)op error:(NSError **)error {
    if (@available(macOS 11.0, *)) {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (self.artifactsDir.length && ![fm fileExistsAtPath:self.artifactsDir]) {
            if (![fm createDirectoryAtPath:self.artifactsDir withIntermediateDirectories:YES attributes:nil error:error]) return NO;
        }

        NSURL *videoURL = [NSURL fileURLWithPath:videoPath];
        if (![fm fileExistsAtPath:videoPath]) {
            if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorVideoLoadFailed
                                                userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Video file not found: %@", videoPath]}];
            return NO;
        }

        VNVideoProcessor *processor = [[VNVideoProcessor alloc] initWithURL:videoURL];
        NSString *videoName = [[videoPath lastPathComponent] stringByDeletingPathExtension];

        if ([op isEqualToString:@"trajectories"])
            return [self runTrajectoriesVideo:processor videoName:videoName error:error];
        if (@available(macOS 14.0, *)) {
            if ([op isEqualToString:@"homographic"])
                return [self runHomographicVideo:processor videoName:videoName error:error];
            if ([op isEqualToString:@"translational"])
                return [self runTranslationalVideo:processor videoName:videoName error:error];
            if ([op isEqualToString:@"optical-flow"])
                return [self runOpticalFlowVideo:processor videoName:videoName error:error];
        } else {
            if ([op isEqualToString:@"homographic"] || [op isEqualToString:@"translational"] || [op isEqualToString:@"optical-flow"]) {
                if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorUnsupportedOS
                                                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"%@ requires macOS 14.0+", op]}];
                return NO;
            }
        }

        if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorMissingInput
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Unknown operation '%@'. Supported: homographic, translational, optical-flow, trajectories", op]}];
        return NO;
    } else {
        if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"track requires macOS 11.0+"}];
        return NO;
    }
}

// ── homographic image sequence ────────────────────────────────────────────────

- (BOOL)runHomographicSequence:(NSArray<NSString *> *)imageFiles imgDir:(NSString *)imgDir error:(NSError **)error {
    if (@available(macOS 14.0, *)) {
        VNSequenceRequestHandler *seqHandler = [[VNSequenceRequestHandler alloc] init];
        NSMutableArray *frames = [NSMutableArray array];
        __block NSUInteger frameIndex = 0;

        VNTrackHomographicImageRegistrationRequest *req = [[VNTrackHomographicImageRegistrationRequest alloc]
            initWithCompletionHandler:^(VNRequest *r, NSError *e) {
                VNImageHomographicAlignmentObservation *obs = (VNImageHomographicAlignmentObservation *)r.results.firstObject;
                if (obs) {
                    simd_float3x3 m = obs.warpTransform;
                    [frames addObject:@{
                        @"frameIndex": @(frameIndex),
                        @"confidence": @(obs.confidence),
                        @"warpTransform": @[
                            @[@(m.columns[0][0]), @(m.columns[1][0]), @(m.columns[2][0])],
                            @[@(m.columns[0][1]), @(m.columns[1][1]), @(m.columns[2][1])],
                            @[@(m.columns[0][2]), @(m.columns[1][2]), @(m.columns[2][2])],
                        ],
                    }];
                }
                frameIndex++;
            }];

        for (NSString *relativePath in imageFiles) {
            NSString *fullPath = [imgDir stringByAppendingPathComponent:relativePath];
            CGImageRef cg = [self loadCGImage:fullPath error:error];
            if (!cg) return NO;
            NSError *seqErr = nil;
            [seqHandler performRequests:@[req] onCGImage:cg error:&seqErr];
            CGImageRelease(cg);
        }

        NSDictionary *json = @{
            @"operation": @"homographic",
            @"frameCount": @(imageFiles.count),
            @"frames":     frames,
        };
        return [self saveJSON:json error:error];
    } else {
        if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"homographic requires macOS 14.0+"}];
        return NO;
    }
}

// ── translational image sequence ──────────────────────────────────────────────

- (BOOL)runTranslationalSequence:(NSArray<NSString *> *)imageFiles imgDir:(NSString *)imgDir error:(NSError **)error {
    if (@available(macOS 14.0, *)) {
        VNSequenceRequestHandler *seqHandler = [[VNSequenceRequestHandler alloc] init];
        NSMutableArray *frames = [NSMutableArray array];
        __block NSUInteger frameIndex = 0;

        VNTrackTranslationalImageRegistrationRequest *req = [[VNTrackTranslationalImageRegistrationRequest alloc]
            initWithCompletionHandler:^(VNRequest *r, NSError *e) {
                VNImageTranslationAlignmentObservation *obs = (VNImageTranslationAlignmentObservation *)r.results.firstObject;
                if (obs) {
                    CGAffineTransform t = obs.alignmentTransform;
                    [frames addObject:@{
                        @"frameIndex": @(frameIndex),
                        @"confidence": @(obs.confidence),
                        @"alignmentTransform": @{
                            @"tx": @(t.tx),
                            @"ty": @(t.ty),
                            @"a":  @(t.a),  @"b": @(t.b),
                            @"c":  @(t.c),  @"d": @(t.d),
                        },
                    }];
                }
                frameIndex++;
            }];

        for (NSString *relativePath in imageFiles) {
            NSString *fullPath = [imgDir stringByAppendingPathComponent:relativePath];
            CGImageRef cg = [self loadCGImage:fullPath error:error];
            if (!cg) return NO;
            NSError *seqErr = nil;
            [seqHandler performRequests:@[req] onCGImage:cg error:&seqErr];
            CGImageRelease(cg);
        }

        NSDictionary *json = @{
            @"operation": @"translational",
            @"frameCount": @(imageFiles.count),
            @"frames":     frames,
        };
        return [self saveJSON:json error:error];
    } else {
        if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"translational requires macOS 14.0+"}];
        return NO;
    }
}

// ── optical-flow image sequence (macOS 14+) ───────────────────────────────────

- (BOOL)runOpticalFlowSequence:(NSArray<NSString *> *)imageFiles imgDir:(NSString *)imgDir error:(NSError **)error {
    if (@available(macOS 14.0, *)) {
        if (!self.artifactsDir.length) {
            if (error) {
                *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorMissingInput
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                       @"optical-flow requires --artifacts-dir (directory for flow PNG frames)"}];
            }
            return NO;
        }
        VNSequenceRequestHandler *seqHandler = [[VNSequenceRequestHandler alloc] init];
        NSMutableArray *frames = [NSMutableArray array];
        __block NSUInteger frameIndex = 0;
        __block NSUInteger flowFramesSaved = 0;
        NSString *outDir = self.artifactsDir;

        VNTrackOpticalFlowRequest *req = [[VNTrackOpticalFlowRequest alloc]
            initWithFrameAnalysisSpacing:CMTimeMake(1, 30)
            completionHandler:^(VNRequest *r, NSError *e) {
                VNPixelBufferObservation *obs = (VNPixelBufferObservation *)r.results.firstObject;
                if (obs && outDir) {
                    // Save the flow pixel buffer as PNG via CIImage
                    CIImage *flowImage = [CIImage imageWithCVPixelBuffer:obs.pixelBuffer];
                    CIContext *ctx = [CIContext contextWithOptions:nil];
                    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                    NSString *filename = [NSString stringWithFormat:@"flow_%04lu.png", (unsigned long)flowFramesSaved];
                    NSString *path = [outDir stringByAppendingPathComponent:filename];
                    [ctx writePNGRepresentationOfImage:flowImage toURL:[NSURL fileURLWithPath:path]
                                               format:kCIFormatRGBA8 colorSpace:cs options:@{} error:nil];
                    CGColorSpaceRelease(cs);
                    flowFramesSaved++;
                }
                [frames addObject:@{@"frameIndex": @(frameIndex), @"hasFlow": @(obs != nil)}];
                frameIndex++;
            }];

        for (NSString *relativePath in imageFiles) {
            NSString *fullPath = [imgDir stringByAppendingPathComponent:relativePath];
            CGImageRef cg = [self loadCGImage:fullPath error:error];
            if (!cg) return NO;
            NSError *seqErr = nil;
            [seqHandler performRequests:@[req] onCGImage:cg error:&seqErr];
            CGImageRelease(cg);
        }

        NSDictionary *json = @{
            @"operation":   @"optical-flow",
            @"frameCount":  @(imageFiles.count),
            @"flowsSaved":  @(flowFramesSaved),
            @"frames":      frames,
        };
        return [self saveJSON:json error:error];
    } else {
        if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"optical-flow requires macOS 14.0+"}];
        return NO;
    }
}

// ── trajectories image sequence (macOS 11+) ───────────────────────────────────

- (BOOL)runTrajectoriesSequence:(NSArray<NSString *> *)imageFiles imgDir:(NSString *)imgDir error:(NSError **)error {
    if (@available(macOS 11.0, *)) {
        VNSequenceRequestHandler *seqHandler = [[VNSequenceRequestHandler alloc] init];
        NSMutableArray *allTrajectories = [NSMutableArray array];

        VNDetectTrajectoriesRequest *req = [[VNDetectTrajectoriesRequest alloc]
            initWithFrameAnalysisSpacing:CMTimeMake(1, 30)
            trajectoryLength:5
            completionHandler:^(VNRequest *r, NSError *e) {
                for (VNTrajectoryObservation *obs in r.results) {
                    NSMutableArray *detectedPts = [NSMutableArray array];
                    for (VNPoint *pt in obs.detectedPoints) {
                        [detectedPts addObject:@{@"x": @(pt.x), @"y": @(1.0 - pt.y)}];
                    }
                    NSMutableArray *projectedPts = [NSMutableArray array];
                    for (VNPoint *pt in obs.projectedPoints) {
                        [projectedPts addObject:@{@"x": @(pt.x), @"y": @(1.0 - pt.y)}];
                    }
                    simd_float3 c = obs.equationCoefficients;
                    [allTrajectories addObject:@{
                        @"confidence":           @(obs.confidence),
                        @"detectedPoints":       detectedPts,
                        @"projectedPoints":      projectedPts,
                        @"equationCoefficients": @[@(c.x), @(c.y), @(c.z)],
                    }];
                }
            }];

        for (NSString *relativePath in imageFiles) {
            NSString *fullPath = [imgDir stringByAppendingPathComponent:relativePath];
            CGImageRef cg = [self loadCGImage:fullPath error:error];
            if (!cg) return NO;
            NSError *seqErr = nil;
            [seqHandler performRequests:@[req] onCGImage:cg error:&seqErr];
            CGImageRelease(cg);
        }

        NSDictionary *json = @{
            @"operation":    @"trajectories",
            @"frameCount":   @(imageFiles.count),
            @"trajectories": allTrajectories,
        };
        return [self saveJSON:json error:error];
    } else {
        if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"trajectories requires macOS 11.0+"}];
        return NO;
    }
}

// ── video: trajectories ───────────────────────────────────────────────────────

- (BOOL)runTrajectoriesVideo:(VNVideoProcessor *)processor videoName:(NSString *)videoName error:(NSError **)error API_AVAILABLE(macos(11.0)) {
    NSMutableArray *allTrajectories = [NSMutableArray array];

    VNDetectTrajectoriesRequest *req = [[VNDetectTrajectoriesRequest alloc]
        initWithFrameAnalysisSpacing:CMTimeMake(1, 30)
        trajectoryLength:5
        completionHandler:^(VNRequest *r, NSError *e) {
            for (VNTrajectoryObservation *obs in r.results) {
                NSMutableArray *pts = [NSMutableArray array];
                for (VNPoint *pt in obs.detectedPoints) {
                    [pts addObject:@{@"x": @(pt.x), @"y": @(1.0 - pt.y)}];
                }
                simd_float3 c = obs.equationCoefficients;
                [allTrajectories addObject:@{
                    @"confidence":           @(obs.confidence),
                    @"detectedPoints":       pts,
                    @"equationCoefficients": @[@(c.x), @(c.y), @(c.z)],
                }];
            }
        }];

    NSError *addErr = nil;
    if (![processor addRequest:req withProcessingOptions:@{} error:&addErr]) {
        if (error) *error = addErr;
        return NO;
    }
    if (![processor analyzeTimeRange:CMTimeRangeMake(kCMTimeZero, kCMTimePositiveInfinity) error:error]) return NO;

    NSDictionary *json = @{@"operation": @"trajectories", @"video": videoName, @"trajectories": allTrajectories};
    return [self saveJSON:json error:error];
}

// ── video: homographic ────────────────────────────────────────────────────────

- (BOOL)runHomographicVideo:(VNVideoProcessor *)processor videoName:(NSString *)videoName error:(NSError **)error API_AVAILABLE(macos(14.0)) {
    NSMutableArray *frames = [NSMutableArray array];
    __block NSUInteger frameIndex = 0;

    VNTrackHomographicImageRegistrationRequest *req = [[VNTrackHomographicImageRegistrationRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) {
            VNImageHomographicAlignmentObservation *obs = (VNImageHomographicAlignmentObservation *)r.results.firstObject;
            if (obs) {
                simd_float3x3 m = obs.warpTransform;
                [frames addObject:@{
                    @"frameIndex": @(frameIndex),
                    @"confidence": @(obs.confidence),
                    @"warpTransform": @[
                        @[@(m.columns[0][0]), @(m.columns[1][0]), @(m.columns[2][0])],
                        @[@(m.columns[0][1]), @(m.columns[1][1]), @(m.columns[2][1])],
                        @[@(m.columns[0][2]), @(m.columns[1][2]), @(m.columns[2][2])],
                    ],
                }];
            }
            frameIndex++;
        }];

    NSError *addErr = nil;
    if (![processor addRequest:req withProcessingOptions:@{} error:&addErr]) {
        if (error) *error = addErr;
        return NO;
    }
    if (![processor analyzeTimeRange:CMTimeRangeMake(kCMTimeZero, kCMTimePositiveInfinity) error:error]) return NO;

    NSDictionary *json = @{@"operation": @"homographic", @"video": videoName, @"frameCount": @(frameIndex), @"frames": frames};
    return [self saveJSON:json error:error];
}

// ── video: translational ──────────────────────────────────────────────────────

- (BOOL)runTranslationalVideo:(VNVideoProcessor *)processor videoName:(NSString *)videoName error:(NSError **)error API_AVAILABLE(macos(14.0)) {
    NSMutableArray *frames = [NSMutableArray array];
    __block NSUInteger frameIndex = 0;

    VNTrackTranslationalImageRegistrationRequest *req = [[VNTrackTranslationalImageRegistrationRequest alloc]
        initWithCompletionHandler:^(VNRequest *r, NSError *e) {
            VNImageTranslationAlignmentObservation *obs = (VNImageTranslationAlignmentObservation *)r.results.firstObject;
            if (obs) {
                CGAffineTransform t = obs.alignmentTransform;
                [frames addObject:@{
                    @"frameIndex": @(frameIndex),
                    @"confidence": @(obs.confidence),
                    @"alignmentTransform": @{
                        @"tx": @(t.tx), @"ty": @(t.ty),
                        @"a":  @(t.a),  @"b":  @(t.b),
                        @"c":  @(t.c),  @"d":  @(t.d),
                    },
                }];
            }
            frameIndex++;
        }];

    NSError *addErr = nil;
    if (![processor addRequest:req withProcessingOptions:@{} error:&addErr]) {
        if (error) *error = addErr;
        return NO;
    }
    if (![processor analyzeTimeRange:CMTimeRangeMake(kCMTimeZero, kCMTimePositiveInfinity) error:error]) return NO;

    NSDictionary *json = @{@"operation": @"translational", @"video": videoName, @"frameCount": @(frameIndex), @"frames": frames};
    return [self saveJSON:json error:error];
}

// ── video: optical-flow (macOS 14+) ───────────────────────────────────────────

- (BOOL)runOpticalFlowVideo:(VNVideoProcessor *)processor videoName:(NSString *)videoName error:(NSError **)error API_AVAILABLE(macos(14.0)) {
    if (@available(macOS 14.0, *)) {
        if (!self.artifactsDir.length) {
            if (error) {
                *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorMissingInput
                                        userInfo:@{NSLocalizedDescriptionKey:
                                                       @"optical-flow requires --artifacts-dir (directory for flow PNG frames)"}];
            }
            return NO;
        }
        __block NSUInteger frameIndex = 0;
        __block NSUInteger flowsSaved = 0;
        NSString *outDir = self.artifactsDir;

        VNTrackOpticalFlowRequest *req = [[VNTrackOpticalFlowRequest alloc]
            initWithFrameAnalysisSpacing:CMTimeMake(1, 30)
            completionHandler:^(VNRequest *r, NSError *e) {
                VNPixelBufferObservation *obs = (VNPixelBufferObservation *)r.results.firstObject;
                if (obs && outDir) {
                    CIImage *flowImage = [CIImage imageWithCVPixelBuffer:obs.pixelBuffer];
                    CIContext *ctx = [CIContext contextWithOptions:nil];
                    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                    NSString *filename = [NSString stringWithFormat:@"%@_flow_%04lu.png", videoName, (unsigned long)flowsSaved];
                    NSString *path = [outDir stringByAppendingPathComponent:filename];
                    [ctx writePNGRepresentationOfImage:flowImage toURL:[NSURL fileURLWithPath:path]
                                               format:kCIFormatRGBA8 colorSpace:cs options:@{} error:nil];
                    CGColorSpaceRelease(cs);
                    flowsSaved++;
                }
                frameIndex++;
            }];

        NSError *addErr = nil;
        if (![processor addRequest:req withProcessingOptions:@{} error:&addErr]) {
            if (error) *error = addErr;
            return NO;
        }
        if (![processor analyzeTimeRange:CMTimeRangeMake(kCMTimeZero, kCMTimePositiveInfinity) error:error]) return NO;

        NSDictionary *json = @{
            @"operation":  @"optical-flow",
            @"video":      videoName,
            @"frameCount": @(frameIndex),
            @"flowsSaved": @(flowsSaved),
        };
        return [self saveJSON:json error:error];
    } else {
        if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"optical-flow requires macOS 14.0+"}];
        return NO;
    }
}

// ── helpers ───────────────────────────────────────────────────────────────────

- (nullable CGImageRef)loadCGImage:(NSString *)imagePath error:(NSError **)error {
    NSImage *image = [[NSImage alloc] initByReferencingFile:imagePath];
    if (!image) {
        if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorImageLoadFailed
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Failed to load image: %@", imagePath]}];
        return NULL;
    }
    CGImageRef cg = [image CGImageForProposedRect:nil context:nil hints:nil];
    if (!cg) {
        if (error) *error = [NSError errorWithDomain:TrackErrorDomain code:TrackErrorImageLoadFailed
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Failed to convert image: %@", imagePath]}];
        return NULL;
    }
    CGImageRetain(cg);
    return cg;
}

- (BOOL)saveJSON:(NSDictionary *)json error:(NSError **)error {
    NSString *op = json[@"operation"] ?: @"track";
    NSMutableArray *extra = [NSMutableArray array];
    if ([op isEqualToString:@"optical-flow"] && self.artifactsDir.length) {
        [extra addObject:MVArtifactEntry(self.artifactsDir, @"optical_flow_frames")];
    }
    NSDictionary *merged = MVResultByMergingArtifacts(json, extra);
    NSDictionary *envelope = MVMakeEnvelope(@"track", op, self.inputPath, merged);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

- (BOOL)isImageFile:(NSString *)filePath {
    NSArray<NSString *> *extensions = @[@"jpg", @"jpeg", @"png", @"webp"];
    return [extensions containsObject:[filePath.pathExtension lowercaseString]];
}

@end
