#import "main.h"
#import "common/MVJsonEmit.h"
#import "common/MVMjpegStream.h"
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
    if (self.stream)    return [self runStreamWithError:error];      // S→S or S→F
    if (self.streamOut) return [self runFileToStreamWithError:error]; // F→S
    NSString *op = self.operation.length ? self.operation : @"foreground-mask";
    if (!self.inputPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:SegmentErrorDomain
                                         code:SegmentErrorMissingInput
                                     userInfo:@{NSLocalizedDescriptionKey: @"Provide --input <image>"}];
        }
        return NO;
    }
    return [self processImage:self.inputPath operation:op error:error];
}

// ── stream helpers ────────────────────────────────────────────────────────────

static CIImage *SGScaleToExtent(CIImage *img, CGRect extent) {
    if (CGSizeEqualToSize(img.extent.size, extent.size)) return img;
    CGFloat sx = extent.size.width  / img.extent.size.width;
    CGFloat sy = extent.size.height / img.extent.size.height;
    return [img imageByApplyingTransform:CGAffineTransformMakeScale(sx, sy)];
}

static CIImage *SGComposeOverBlack(CIImage *image, CGRect extent) {
    CIImage *black = [[CIImage imageWithColor:[CIColor blackColor]] imageByCroppingToRect:extent];
    CIFilter *f = [CIFilter filterWithName:@"CISourceOverCompositing"];
    [f setValue:image forKey:kCIInputImageKey];
    [f setValue:black forKey:kCIInputBackgroundImageKey];
    return f.outputImage;
}

// Returns array of output CIImages for a single input frame.
// Empty array = drop frame (e.g. person-mask with no detections).
- (NSArray<CIImage *> *)streamProcessCGImage:(CGImageRef)cg operation:(NSString *)op {
    CIImage *original = [CIImage imageWithCGImage:cg];
    CGRect extent = original.extent;
    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];

    if ([op isEqualToString:@"foreground-mask"]) {
        if (@available(macOS 14.0, *)) {
            VNGenerateForegroundInstanceMaskRequest *req = [[VNGenerateForegroundInstanceMaskRequest alloc] init];
            if (![handler performRequests:@[req] error:nil] || !req.results.firstObject) return @[];
            VNInstanceMaskObservation *obs = req.results.firstObject;
            CVPixelBufferRef pb = [obs generateMaskedImageOfInstances:obs.allInstances
                                                    fromRequestHandler:handler
                                               croppedToInstancesExtent:NO error:nil];
            if (!pb) return @[];
            CIImage *masked = SGScaleToExtent([CIImage imageWithCVPixelBuffer:pb], extent);
            CVPixelBufferRelease(pb);
            return @[SGComposeOverBlack(masked, extent)];
        }
        return @[];
    }

    if ([op isEqualToString:@"person-segment"]) {
        if (@available(macOS 12.0, *)) {
            VNGeneratePersonSegmentationRequest *req = [[VNGeneratePersonSegmentationRequest alloc] init];
            req.qualityLevel = VNGeneratePersonSegmentationRequestQualityLevelAccurate;
            if (![handler performRequests:@[req] error:nil] || !req.results.firstObject) return @[];
            VNPixelBufferObservation *obs = req.results.firstObject;
            CIImage *mask = SGScaleToExtent([CIImage imageWithCVPixelBuffer:obs.pixelBuffer], extent);
            CIImage *black = [[CIImage imageWithColor:[CIColor blackColor]] imageByCroppingToRect:extent];
            CIFilter *blend = [CIFilter filterWithName:@"CIBlendWithMask"];
            [blend setValue:original forKey:kCIInputImageKey];
            [blend setValue:black    forKey:kCIInputBackgroundImageKey];
            [blend setValue:mask     forKey:kCIInputMaskImageKey];
            return @[blend.outputImage];
        }
        return @[];
    }

    if ([op isEqualToString:@"person-mask"]) {
        if (@available(macOS 14.0, *)) {
            VNGeneratePersonInstanceMaskRequest *req = [[VNGeneratePersonInstanceMaskRequest alloc] init];
            if (![handler performRequests:@[req] error:nil] || !req.results.firstObject) return @[];
            VNInstanceMaskObservation *obs = req.results.firstObject;
            NSMutableArray<CIImage *> *frames = [NSMutableArray array];
            [obs.allInstances enumerateIndexesUsingBlock:^(NSUInteger instance, BOOL *stop) {
                NSIndexSet *single = [NSIndexSet indexSetWithIndex:instance];
                CVPixelBufferRef pb = [obs generateMaskedImageOfInstances:single
                                                        fromRequestHandler:handler
                                                   croppedToInstancesExtent:NO error:nil];
                if (!pb) return;
                CIImage *masked = SGScaleToExtent([CIImage imageWithCVPixelBuffer:pb], extent);
                CVPixelBufferRelease(pb);
                CIImage *out = SGComposeOverBlack(masked, extent);
                if (out) [frames addObject:out];
            }];
            return frames;
        }
        return @[];
    }

    if ([op isEqualToString:@"attention-saliency"] || [op isEqualToString:@"objectness-saliency"]) {
        VNRequest *req = [op isEqualToString:@"attention-saliency"]
            ? [[VNGenerateAttentionBasedSaliencyImageRequest alloc] init]
            : [[VNGenerateObjectnessBasedSaliencyImageRequest alloc] init];
        if (![handler performRequests:@[req] error:nil] || !req.results.firstObject) return @[original];
        VNSaliencyImageObservation *obs = (VNSaliencyImageObservation *)req.results.firstObject;
        CIImage *heatmap = SGScaleToExtent([CIImage imageWithCVPixelBuffer:obs.pixelBuffer], extent);
        // Composite red tint over original using heatmap as mask
        CIImage *red = [[CIImage imageWithColor:[CIColor colorWithRed:1 green:0.2 blue:0 alpha:1]]
                        imageByCroppingToRect:extent];
        CIFilter *blend = [CIFilter filterWithName:@"CIBlendWithMask"];
        [blend setValue:red      forKey:kCIInputImageKey];
        [blend setValue:original forKey:kCIInputBackgroundImageKey];
        [blend setValue:heatmap  forKey:kCIInputMaskImageKey];
        return @[blend.outputImage];
    }

    return @[original]; // unknown op: pass through
}

// ── S→S / S→F stream mode ─────────────────────────────────────────────────────

- (BOOL)runStreamWithError:(NSError **)error {
    NSString *op = self.operation.length ? self.operation : @"foreground-mask";

    MVMjpegReader *reader = [[MVMjpegReader alloc] initWithFileDescriptor:STDIN_FILENO];
    MVMjpegWriter *writer = [[MVMjpegWriter alloc] initWithFileDescriptor:STDOUT_FILENO];
    writer.ndjsonOutputPath = self.ndjsonOutput;

    CIContext *ctx = [CIContext contextWithOptions:nil];
    CGColorSpaceRef sRGB = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);

    [reader readFramesWithHandler:^(NSData *jpeg, NSDictionary<NSString *, NSString *> *inHeaders) {
        CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)jpeg, nil);
        CGImageRef cg = src ? CGImageSourceCreateImageAtIndex(src, 0, nil) : NULL;
        if (src) CFRelease(src);
        if (!cg) { [writer writeFrame:jpeg extraHeaders:nil]; return; }

        NSMutableDictionary *outHeaders = [NSMutableDictionary dictionaryWithDictionary:inHeaders];
        [outHeaders removeObjectForKey:@"Content-Type"];
        [outHeaders removeObjectForKey:@"Content-Length"];

        NSArray<CIImage *> *outputs = [self streamProcessCGImage:cg operation:op];
        CGImageRelease(cg);

        for (CIImage *outCI in outputs) {
            NSData *outJpeg = [ctx JPEGRepresentationOfImage:outCI colorSpace:sRGB options:@{}];
            if (outJpeg) [writer writeFrame:outJpeg extraHeaders:outHeaders];
        }
        // If outputs is empty (e.g. person-mask with no detections), frame is dropped — intentional.
    }];

    CGColorSpaceRelease(sRGB);
    return YES;
}

// ── F→S mode: file input → single MJPEG frame out ────────────────────────────

- (BOOL)runFileToStreamWithError:(NSError **)error {
    NSString *op = self.operation.length ? self.operation : @"foreground-mask";
    if (!self.inputPath.length) {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorMissingInput
                            userInfo:@{NSLocalizedDescriptionKey: @"Provide --input <image>"}];
        return NO;
    }

    NSFileManager *fm = [NSFileManager defaultManager];
    if (self.artifactsDir.length && ![fm fileExistsAtPath:self.artifactsDir]) {
        if (![fm createDirectoryAtPath:self.artifactsDir withIntermediateDirectories:YES attributes:nil error:error])
            return NO;
    }

    NSString *base = [self.inputPath.lastPathComponent stringByDeletingPathExtension];
    NSMutableArray<NSDictionary *> *artifactPaths = [NSMutableArray array];
    BOOL ok = NO;
    if ([op isEqualToString:@"foreground-mask"])
        ok = [self runForegroundMask:self.inputPath base:base artifactPaths:artifactPaths error:error];
    else if ([op isEqualToString:@"person-mask"])
        ok = [self runPersonMask:self.inputPath base:base artifactPaths:artifactPaths error:error];
    else if ([op isEqualToString:@"person-segment"])
        ok = [self runPersonSegment:self.inputPath base:base artifactPaths:artifactPaths error:error];
    else if ([op isEqualToString:@"attention-saliency"])
        ok = [self runAttentionSaliency:self.inputPath base:base artifactPaths:artifactPaths error:error];
    else if ([op isEqualToString:@"objectness-saliency"])
        ok = [self runObjectnessSaliency:self.inputPath base:base artifactPaths:artifactPaths error:error];
    else {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorMissingInput
                            userInfo:@{NSLocalizedDescriptionKey:
                                           [NSString stringWithFormat:@"Unknown operation '%@'", op]}];
        return NO;
    }
    if (!ok) return NO;

    NSDictionary *result = @{ @"operation": op, @"artifacts": artifactPaths };
    NSDictionary *envelope = MVMakeEnvelope(@"segment", op, self.inputPath, result);
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:nil];
    NSString *jsonStr = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";

    if (self.jsonOutput.length) MVEmitEnvelope(envelope, self.jsonOutput, nil);

    // Encode original image as JPEG for the MJPEG frame
    NSData *jpegData = nil;
    NSString *ext = self.inputPath.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"])
        jpegData = [NSData dataWithContentsOfFile:self.inputPath];
    if (!jpegData) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:self.inputPath];
        NSBitmapImageRep *rep = img ? [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]] : nil;
        jpegData = [rep representationUsingType:NSBitmapImageFileTypeJPEG
                                     properties:@{NSImageCompressionFactor: @0.85}];
    }
    if (!jpegData) {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorEncodeFailed
                            userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode image as JPEG for stream"}];
        return NO;
    }

    MVMjpegWriter *writer = [[MVMjpegWriter alloc] initWithFileDescriptor:STDOUT_FILENO];
    writer.ndjsonOutputPath = self.ndjsonOutput;
    [writer writeFrame:jpegData extraHeaders:@{ [NSString stringWithFormat:@"X-MV-segment-%@", op]: jsonStr }];
    return YES;
}

- (BOOL)processImage:(NSString *)imagePath operation:(NSString *)op error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    if (self.artifactsDir.length && ![fm fileExistsAtPath:self.artifactsDir]) {
        if (![fm createDirectoryAtPath:self.artifactsDir withIntermediateDirectories:YES attributes:nil error:error]) {
            return NO;
        }
    }

    NSString *base = [[imagePath lastPathComponent] stringByDeletingPathExtension];
    NSMutableArray<NSDictionary *> *artifactPaths = [NSMutableArray array];
    BOOL ok = NO;
    if ([op isEqualToString:@"foreground-mask"]) {
        ok = [self runForegroundMask:imagePath base:base artifactPaths:artifactPaths error:error];
    } else if ([op isEqualToString:@"person-mask"]) {
        ok = [self runPersonMask:imagePath base:base artifactPaths:artifactPaths error:error];
    } else if ([op isEqualToString:@"person-segment"]) {
        ok = [self runPersonSegment:imagePath base:base artifactPaths:artifactPaths error:error];
    } else if ([op isEqualToString:@"attention-saliency"]) {
        ok = [self runAttentionSaliency:imagePath base:base artifactPaths:artifactPaths error:error];
    } else if ([op isEqualToString:@"objectness-saliency"]) {
        ok = [self runObjectnessSaliency:imagePath base:base artifactPaths:artifactPaths error:error];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:SegmentErrorDomain
                                         code:SegmentErrorMissingInput
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Unknown operation '%@'. Supported: foreground-mask, person-segment, person-mask, attention-saliency, objectness-saliency", op]}];
        }
        return NO;
    }
    if (!ok) return NO;
    NSDictionary *result = @{ @"operation": op, @"artifacts": artifactPaths };
    NSDictionary *envelope = MVMakeEnvelope(@"segment", op, self.inputPath, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── VNGenerateForegroundInstanceMaskRequest (macOS 14+) ───────────────────────

- (BOOL)runForegroundMask:(NSString *)imagePath base:(NSString *)base artifactPaths:(NSMutableArray<NSDictionary *> *)artifactPaths error:(NSError **)error {
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

        NSString *outPath = [self singleOutputPathForOperation:@"foreground-mask"];
        BOOL ok = [self savePixelBuffer:pixelBuffer toPath:outPath error:error];
        CVPixelBufferRelease(pixelBuffer);
        if (ok) [artifactPaths addObject:MVArtifactEntry(outPath, @"foreground_mask")];
        return ok;
    } else {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"foreground-mask requires macOS 14.0+"}];
        return NO;
    }
}

// ── VNGeneratePersonInstanceMaskRequest (macOS 14+) ───────────────────────────

- (BOOL)runPersonMask:(NSString *)imagePath base:(NSString *)base artifactPaths:(NSMutableArray<NSDictionary *> *)artifactPaths error:(NSError **)error {
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
            NSString *outPath = [self multiOutputPathForPersonMaskIndex:idx];
            NSError *saveError = nil;
            if ([self savePixelBuffer:pb toPath:outPath error:&saveError]) {
                [artifactPaths addObject:MVArtifactEntry(outPath, @"person_mask")];
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

- (BOOL)runPersonSegment:(NSString *)imagePath base:(NSString *)base artifactPaths:(NSMutableArray<NSDictionary *> *)artifactPaths error:(NSError **)error {
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
        NSString *outPath = [self singleOutputPathForOperation:@"person-segment"];
        BOOL ok = [self saveCIImage:result toPath:outPath error:error];
        if (ok) [artifactPaths addObject:MVArtifactEntry(outPath, @"person_segment")];
        return ok;
    } else {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorUnsupportedOS
                                            userInfo:@{NSLocalizedDescriptionKey: @"person-segment requires macOS 12.0+"}];
        return NO;
    }
}

// ── VNGenerateAttentionBasedSaliencyImageRequest (macOS 10.15+) ───────────────

- (BOOL)runAttentionSaliency:(NSString *)imagePath base:(NSString *)base artifactPaths:(NSMutableArray<NSDictionary *> *)artifactPaths error:(NSError **)error {
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
    NSString *outPath = [self singleOutputPathForOperation:@"attention-saliency"];
    BOOL ok = [self saveCIImage:heatmap toPath:outPath error:error];
    if (ok) [artifactPaths addObject:MVArtifactEntry(outPath, @"attention_saliency")];
    return ok;
}

// ── VNGenerateObjectnessBasedSaliencyImageRequest (macOS 10.15+) ──────────────

- (BOOL)runObjectnessSaliency:(NSString *)imagePath base:(NSString *)base artifactPaths:(NSMutableArray<NSDictionary *> *)artifactPaths error:(NSError **)error {
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
    NSString *outPath = [self singleOutputPathForOperation:@"objectness-saliency"];
    BOOL ok = [self saveCIImage:heatmap toPath:outPath error:error];
    if (ok) [artifactPaths addObject:MVArtifactEntry(outPath, @"objectness_saliency")];
    return ok;
}

// ── helpers ───────────────────────────────────────────────────────────────────

- (nullable CGImageRef)loadCGImage:(NSString *)imagePath error:(NSError **)error {
    if (![[NSFileManager defaultManager] fileExistsAtPath:imagePath]) {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorImageLoadFailed
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"File not found: %@", imagePath]}];
        return NULL;
    }
    NSImage *image = [[NSImage alloc] initByReferencingFile:imagePath];
    CGImageRef cg = image ? [image CGImageForProposedRect:nil context:nil hints:nil] : NULL;
    if (!cg) {
        if (error) *error = [NSError errorWithDomain:SegmentErrorDomain code:SegmentErrorImageLoadFailed
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                           [NSString stringWithFormat:@"Failed to load image (unsupported format?): %@", imagePath]}];
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

/// Single-file output path: --output exact > artifactsDir/segment_<op>.png > CWD/segment_<op>.png
- (NSString *)singleOutputPathForOperation:(NSString *)op {
    if (self.outputPath.length) return self.outputPath;
    NSString *safeOp = [op stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    NSString *filename = [NSString stringWithFormat:@"segment_%@.png", safeOp];
    NSString *dir = self.artifactsDir.length
        ? self.artifactsDir
        : [[NSFileManager defaultManager] currentDirectoryPath];
    return [dir stringByAppendingPathComponent:filename];
}

/// Multi-file output path (person-mask): artifactsDir/segment_person_mask_NNN.png or CWD/...
/// No --output flag for multi-file operations.
- (NSString *)multiOutputPathForPersonMaskIndex:(NSUInteger)idx {
    NSString *filename = [NSString stringWithFormat:@"segment_person_mask_%03lu.png", (unsigned long)(idx + 1)];
    NSString *dir = self.artifactsDir.length
        ? self.artifactsDir
        : [[NSFileManager defaultManager] currentDirectoryPath];
    return [dir stringByAppendingPathComponent:filename];
}

@end
