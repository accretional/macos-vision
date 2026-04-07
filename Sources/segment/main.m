#import "main.h"
#import <Cocoa/Cocoa.h>
#import <Vision/Vision.h>
#import <CoreImage/CoreImage.h>
#import <CoreVideo/CoreVideo.h>

static NSString * const SegmentErrorDomain = @"SegmentError";
typedef NS_ENUM(NSInteger, SegmentErrorCode) {
    SegmentErrorMissingInput    = 1,
    SegmentErrorImageLoadFailed = 2,
    SegmentErrorRequestFailed   = 3,
    SegmentErrorNoResults       = 4,
    SegmentErrorEncodeFailed    = 5,
    SegmentErrorUnsupportedOS   = 6,
};

@implementation SegmentProcessor

// ── public entry point ────────────────────────────────────────────────────────

- (BOOL)runWithError:(NSError **)error {
    NSString *op = self.operation.length ? self.operation : @"foreground-mask";

    if (self.img) {
        return [self processImage:self.img outputDir:self.output operation:op error:error];
    } else if (self.imgDir) {
        return [self processBatch:self.imgDir outputDir:self.outputDir operation:op error:error];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:SegmentErrorDomain
                                         code:SegmentErrorMissingInput
                                     userInfo:@{NSLocalizedDescriptionKey: @"Either --img or --img-dir must be provided"}];
        }
        return NO;
    }
}

// ── single image ──────────────────────────────────────────────────────────────

- (BOOL)processImage:(NSString *)imagePath outputDir:(nullable NSString *)outputDir operation:(NSString *)op error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (outputDir && ![fm fileExistsAtPath:outputDir]) {
        if (![fm createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:error]) {
            return NO;
        }
    }

    NSString *base = [[imagePath lastPathComponent] stringByDeletingPathExtension];

    if ([op isEqualToString:@"foreground-mask"]) {
        return [self runForegroundMask:imagePath base:base outputDir:outputDir error:error];
    } else if ([op isEqualToString:@"person-mask"]) {
        return [self runPersonMask:imagePath base:base outputDir:outputDir error:error];
    } else if ([op isEqualToString:@"person-segment"]) {
        return [self runPersonSegment:imagePath base:base outputDir:outputDir error:error];
    } else if ([op isEqualToString:@"attention-saliency"]) {
        return [self runAttentionSaliency:imagePath base:base outputDir:outputDir error:error];
    } else if ([op isEqualToString:@"objectness-saliency"]) {
        return [self runObjectnessSaliency:imagePath base:base outputDir:outputDir error:error];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:SegmentErrorDomain
                                         code:SegmentErrorMissingInput
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Unknown operation '%@'. Supported: foreground-mask, person-segment, person-mask, attention-saliency, objectness-saliency", op]}];
        }
        return NO;
    }
}

// ── batch mode ────────────────────────────────────────────────────────────────

- (BOOL)processBatch:(NSString *)imgDir outputDir:(nullable NSString *)outputDir operation:(NSString *)op error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (outputDir && ![fm fileExistsAtPath:outputDir]) {
        if (![fm createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:error]) {
            return NO;
        }
    }

    NSDirectoryEnumerator *enumerator = [fm enumeratorAtPath:imgDir];
    NSMutableArray<NSString *> *imageFiles = [NSMutableArray array];
    NSString *filePath;
    while ((filePath = [enumerator nextObject])) {
        if ([self isImageFile:filePath]) {
            [imageFiles addObject:filePath];
        }
    }
    [imageFiles sortUsingSelector:@selector(compare:)];

    for (NSString *relativePath in imageFiles) {
        NSString *fullPath = [imgDir stringByAppendingPathComponent:relativePath];
        if (![self processImage:fullPath outputDir:outputDir operation:op error:error]) return NO;
    }
    return YES;
}

// ── VNGenerateForegroundInstanceMaskRequest (macOS 14+) ───────────────────────

- (BOOL)runForegroundMask:(NSString *)imagePath base:(NSString *)base outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    if (@available(macOS 14.0, *)) {
        CGImageRef cgImage = [self loadCGImage:imagePath error:error];
        if (!cgImage) return NO;

        VNGenerateForegroundInstanceMaskRequest *request = [[VNGenerateForegroundInstanceMaskRequest alloc] init];
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];

        if (![handler performRequests:@[request] error:error]) {
            CGImageRelease(cgImage);
            return NO;
        }
        CGImageRelease(cgImage);

        VNInstanceMaskObservation *obs = request.results.firstObject;
        if (!obs) {
            if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorNoResults
                                                userInfo:@{NSLocalizedDescriptionKey: @"No foreground instances found"}];
            return NO;
        }

        NSError *maskError = nil;
        CVPixelBufferRef pixelBuffer = [obs generateMaskedImageOfInstances:obs.allInstances
                                                         fromRequestHandler:handler
                                                    croppedToInstancesExtent:NO
                                                                       error:&maskError];
        if (!pixelBuffer) {
            if (error) *error = maskError ?: [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorRequestFailed
                                                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to generate masked image"}];
            return NO;
        }

        NSString *outPath = [self outputPathForBase:base suffix:@"foreground" outputDir:outputDir inputPath:imagePath];
        BOOL ok = [self savePixelBuffer:pixelBuffer toPath:outPath error:error];
        CVPixelBufferRelease(pixelBuffer);
        if (ok) printf("Saved: %s\n", outPath.UTF8String);
        return ok;
    } else {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"foreground-mask requires macOS 14.0+"}];
        return NO;
    }
}

// ── VNGeneratePersonInstanceMaskRequest (macOS 14+) ───────────────────────────

- (BOOL)runPersonMask:(NSString *)imagePath base:(NSString *)base outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    if (@available(macOS 14.0, *)) {
        CGImageRef cgImage = [self loadCGImage:imagePath error:error];
        if (!cgImage) return NO;

        VNGeneratePersonInstanceMaskRequest *request = [[VNGeneratePersonInstanceMaskRequest alloc] init];
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];

        if (![handler performRequests:@[request] error:error]) {
            CGImageRelease(cgImage);
            return NO;
        }
        CGImageRelease(cgImage);

        VNInstanceMaskObservation *obs = request.results.firstObject;
        if (!obs) {
            if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorNoResults
                                                userInfo:@{NSLocalizedDescriptionKey: @"No person instances found"}];
            return NO;
        }

        __block BOOL success = YES;
        __block NSUInteger idx = 0;
        __block NSError *blockError = nil;
        [obs.allInstances enumerateIndexesUsingBlock:^(NSUInteger instance, BOOL *stop) {
            NSIndexSet *single = [NSIndexSet indexSetWithIndex:instance];
            NSError *maskError = nil;
            CVPixelBufferRef pb = [obs generateMaskedImageOfInstances:single
                                                    fromRequestHandler:handler
                                               croppedToInstancesExtent:NO
                                                                  error:&maskError];
            if (!pb) {
                blockError = maskError;
                success = NO;
                *stop = YES;
                return;
            }
            NSString *suffix = [NSString stringWithFormat:@"person_%lu", (unsigned long)idx];
            NSString *outPath = [self outputPathForBase:base suffix:suffix outputDir:outputDir inputPath:imagePath];
            NSError *saveError = nil;
            if ([self savePixelBuffer:pb toPath:outPath error:&saveError]) {
                printf("Saved: %s\n", outPath.UTF8String);
                idx++;
            } else {
                blockError = saveError;
                success = NO;
                *stop = YES;
            }
            CVPixelBufferRelease(pb);
        }];
        if (!success && error) *error = blockError;
        return success;
    } else {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"person-mask requires macOS 14.0+"}];
        return NO;
    }
}

// ── VNGeneratePersonSegmentationRequest (macOS 12+) ───────────────────────────

- (BOOL)runPersonSegment:(NSString *)imagePath base:(NSString *)base outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    if (@available(macOS 12.0, *)) {
        CGImageRef cgImage = [self loadCGImage:imagePath error:error];
        if (!cgImage) return NO;

        VNGeneratePersonSegmentationRequest *request = [[VNGeneratePersonSegmentationRequest alloc] init];
        request.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelAccurate;

        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
        if (![handler performRequests:@[request] error:error]) {
            CGImageRelease(cgImage);
            return NO;
        }

        VNPixelBufferObservation *obs = request.results.firstObject;
        if (!obs) {
            CGImageRelease(cgImage);
            if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorNoResults
                                                userInfo:@{NSLocalizedDescriptionKey: @"No person segmentation results"}];
            return NO;
        }

        // Apply the grayscale mask to the original image to produce a transparent PNG
        CIImage *original = [CIImage imageWithCGImage:cgImage];
        CGImageRelease(cgImage);

        CIImage *mask = [CIImage imageWithCVPixelBuffer:obs.pixelBuffer];
        // Scale mask to match original dimensions
        CGFloat sx = original.extent.size.width  / mask.extent.size.width;
        CGFloat sy = original.extent.size.height / mask.extent.size.height;
        mask = [mask imageByApplyingTransform:CGAffineTransformMakeScale(sx, sy)];

        CIImage *clearBg = [[CIImage imageWithColor:[CIColor clearColor]]
                            imageByCroppingToRect:original.extent];
        CIFilter *blend = [CIFilter filterWithName:@"CIBlendWithMask"];
        [blend setValue:original  forKey:kCIInputImageKey];
        [blend setValue:clearBg   forKey:kCIInputBackgroundImageKey];
        [blend setValue:mask      forKey:kCIInputMaskImageKey];

        CIImage *result = blend.outputImage;
        NSString *outPath = [self outputPathForBase:base suffix:@"person_segment" outputDir:outputDir inputPath:imagePath];
        BOOL ok = [self saveCIImage:result toPath:outPath error:error];
        if (ok) printf("Saved: %s\n", outPath.UTF8String);
        return ok;
    } else {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"person-segment requires macOS 12.0+"}];
        return NO;
    }
}

// ── VNGenerateAttentionBasedSaliencyImageRequest (macOS 10.15+) ───────────────

- (BOOL)runAttentionSaliency:(NSString *)imagePath base:(NSString *)base outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    CGImageRef cgImage = [self loadCGImage:imagePath error:error];
    if (!cgImage) return NO;

    VNGenerateAttentionBasedSaliencyImageRequest *request = [[VNGenerateAttentionBasedSaliencyImageRequest alloc] init];
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
    if (![handler performRequests:@[request] error:error]) {
        CGImageRelease(cgImage);
        return NO;
    }
    CGImageRelease(cgImage);

    VNSaliencyImageObservation *obs = (VNSaliencyImageObservation *)request.results.firstObject;
    if (!obs) {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorNoResults
                                            userInfo:@{NSLocalizedDescriptionKey: @"No saliency results"}];
        return NO;
    }

    CIImage *heatmap = [CIImage imageWithCVPixelBuffer:obs.pixelBuffer];
    NSString *outPath = [self outputPathForBase:base suffix:@"attention_saliency" outputDir:outputDir inputPath:imagePath];
    BOOL ok = [self saveCIImage:heatmap toPath:outPath error:error];
    if (ok) printf("Saved: %s\n", outPath.UTF8String);
    return ok;
}

// ── VNGenerateObjectnessBasedSaliencyImageRequest (macOS 10.15+) ──────────────

- (BOOL)runObjectnessSaliency:(NSString *)imagePath base:(NSString *)base outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    CGImageRef cgImage = [self loadCGImage:imagePath error:error];
    if (!cgImage) return NO;

    VNGenerateObjectnessBasedSaliencyImageRequest *request = [[VNGenerateObjectnessBasedSaliencyImageRequest alloc] init];
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
    if (![handler performRequests:@[request] error:error]) {
        CGImageRelease(cgImage);
        return NO;
    }
    CGImageRelease(cgImage);

    VNSaliencyImageObservation *obs = (VNSaliencyImageObservation *)request.results.firstObject;
    if (!obs) {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorNoResults
                                            userInfo:@{NSLocalizedDescriptionKey: @"No saliency results"}];
        return NO;
    }

    CIImage *heatmap = [CIImage imageWithCVPixelBuffer:obs.pixelBuffer];
    NSString *outPath = [self outputPathForBase:base suffix:@"objectness_saliency" outputDir:outputDir inputPath:imagePath];
    BOOL ok = [self saveCIImage:heatmap toPath:outPath error:error];
    if (ok) printf("Saved: %s\n", outPath.UTF8String);
    return ok;
}

// ── helpers ───────────────────────────────────────────────────────────────────

- (nullable CGImageRef)loadCGImage:(NSString *)imagePath error:(NSError **)error {
    NSImage *image = [[NSImage alloc] initByReferencingFile:imagePath];
    if (!image) {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorImageLoadFailed
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Failed to load image: %@", imagePath]}];
        return NULL;
    }
    CGImageRef cg = [image CGImageForProposedRect:nil context:nil hints:nil];
    if (!cg) {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorImageLoadFailed
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Failed to convert image: %@", imagePath]}];
        return NULL;
    }
    CGImageRetain(cg);
    return cg;
}

- (BOOL)savePixelBuffer:(CVPixelBufferRef)pixelBuffer toPath:(NSString *)path error:(NSError **)error {
    CIImage *ciImage = [CIImage imageWithCVPixelBuffer:pixelBuffer];
    return [self saveCIImage:ciImage toPath:path error:error];
}

- (BOOL)saveCIImage:(CIImage *)ciImage toPath:(NSString *)path error:(NSError **)error {
    CIContext *ctx = [CIContext contextWithOptions:nil];
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    NSData *pngData = [ctx PNGRepresentationOfImage:ciImage
                                              format:kCIFormatRGBA8
                                          colorSpace:cs
                                             options:@{}];
    CGColorSpaceRelease(cs);
    if (!pngData) {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorEncodeFailed
                                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode image as PNG"}];
        return NO;
    }
    return [pngData writeToFile:path options:NSDataWritingAtomic error:error];
}

- (NSString *)outputPathForBase:(NSString *)base suffix:(NSString *)suffix outputDir:(nullable NSString *)outputDir inputPath:(NSString *)inputPath {
    NSString *filename = [NSString stringWithFormat:@"%@_%@.png", base, suffix];
    if (outputDir) {
        return [outputDir stringByAppendingPathComponent:filename];
    }
    // Same directory as input
    return [[inputPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:filename];
}

- (BOOL)isImageFile:(NSString *)filePath {
    NSArray<NSString *> *extensions = @[@"jpg", @"jpeg", @"png", @"webp"];
    return [extensions containsObject:[filePath.pathExtension lowercaseString]];
}

@end
