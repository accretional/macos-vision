#import "main.h"
#import "common/MVJsonEmit.h"
#import "common/MVMjpegStream.h"
#import <Cocoa/Cocoa.h>
#import <Vision/Vision.h>
#import <ImageIO/ImageIO.h>

static NSString * const OCRErrorDomain = @"OCRError";

static inline CGFloat norm(CGFloat v) { return MAX(0.0, MIN(1.0, v)); }
typedef NS_ENUM(NSInteger, OCRErrorCode) {
    OCRErrorImageLoadFailed      = 1,
    OCRErrorImageConversionFailed = 2,
    OCRErrorJSONParsingFailed    = 3,
    OCRErrorNoTextFound          = 4,
    OCRErrorMissingInput         = 5,
};

@implementation OCRProcessor

// ── public entry point ────────────────────────────────────────────────────────

- (BOOL)runWithError:(NSError **)error {
    if (self.stream) return [self runStreamWithError:error];
    if (self.lang) {
        NSArray<NSString *> *languages = [self supportedLanguages];
        fprintf(stderr, "Supported recognition languages:\n");
        for (NSString *l in languages) {
            fprintf(stderr, "- %s\n", l.UTF8String);
        }
        return YES;
    }

    if (!self.inputPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:OCRErrorDomain
                                         code:OCRErrorMissingInput
                                     userInfo:@{NSLocalizedDescriptionKey: @"Provide --input <image.png>"}];
        }
        return NO;
    }

    NSDictionary *inner = [self recognitionResultFromImage:self.inputPath error:error];
    if (!inner) return NO;

    NSMutableArray *artifactEntries = [NSMutableArray array];
    if (self.debug) {
        NSString *dbgPath = [self drawDebugImage:self.inputPath observations:inner[@"observations"] error:error];
        if (!dbgPath) return NO;
        [artifactEntries addObject:MVArtifactEntry(dbgPath, @"debug_overlay")];
    }
    NSDictionary *merged = MVResultByMergingArtifacts(inner, artifactEntries);
    NSDictionary *envelope = MVMakeEnvelope(@"ocr", @"recognize", self.inputPath, merged);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── stream mode ───────────────────────────────────────────────────────────────

- (BOOL)runStreamWithError:(NSError **)error {
    MVMjpegReader *reader = [[MVMjpegReader alloc] initWithFileDescriptor:STDIN_FILENO];
    MVMjpegWriter *writer = [[MVMjpegWriter alloc] initWithFileDescriptor:STDOUT_FILENO];

    [reader readFramesWithHandler:^(NSData *jpeg, NSDictionary<NSString *, NSString *> *inHeaders) {
        CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)jpeg, nil);
        CGImageRef cg = src ? CGImageSourceCreateImageAtIndex(src, 0, nil) : NULL;
        if (src) CFRelease(src);

        NSMutableDictionary<NSString *, NSString *> *outHeaders = [NSMutableDictionary dictionaryWithDictionary:inHeaders];
        [outHeaders removeObjectForKey:@"Content-Type"];
        [outHeaders removeObjectForKey:@"Content-Length"];

        if (cg) {
            NSDictionary *result = [self recognizeFromCGImage:cg error:nil];
            CGImageRelease(cg);
            if (result) {
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
                if (jsonData)
                    outHeaders[@"X-MV-ocr-recognize"] = [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            }
        }

        [writer writeFrame:jpeg extraHeaders:outHeaders];
    }];

    return YES;
}

/// Run OCR on a CGImageRef and return the result dict, or nil on failure.
- (nullable NSDictionary *)recognizeFromCGImage:(CGImageRef)cgImage error:(NSError **)error {
    __block NSArray<VNRecognizedTextObservation *> *observations = nil;
    __block NSError *vnError = nil;

    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc]
        initWithCompletionHandler:^(VNRequest *req, NSError *err) {
            vnError = err;
            observations = req.results;
        }];

    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = YES;
    request.minimumTextHeight = 0.01;

    if (@available(macOS 13.0, *)) {
        request.revision = VNRecognizeTextRequestRevision3;
    } else if (@available(macOS 11.0, *)) {
        request.revision = VNRecognizeTextRequestRevision2;
    } else {
        request.revision = VNRecognizeTextRequestRevision1;
    }

    if (self.recLangs) {
        NSMutableArray<NSString *> *langs = [NSMutableArray array];
        for (NSString *l in [self.recLangs componentsSeparatedByString:@","]) {
            NSString *trimmed = [l stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (trimmed.length > 0) [langs addObject:trimmed];
        }
        request.recognitionLanguages = langs;
    } else {
        request.recognitionLanguages = [self supportedLanguages];
    }

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
    if (![handler performRequests:@[request] error:error]) return nil;
    if (vnError) { if (error) *error = vnError; return nil; }

    NSMutableArray<NSDictionary *> *positionalJson = [NSMutableArray array];
    NSMutableArray<NSString *> *fullText = [NSMutableArray array];

    for (VNRecognizedTextObservation *obs in observations) {
        VNRecognizedText *candidate = [[obs topCandidates:1] firstObject];
        if (!candidate) continue;

        [fullText addObject:candidate.string];

        NSDictionary *quad = @{
            @"topLeft":     @{@"x": @(norm(obs.topLeft.x)),     @"y": @(norm(1 - obs.topLeft.y))},
            @"topRight":    @{@"x": @(norm(obs.topRight.x)),    @"y": @(norm(1 - obs.topRight.y))},
            @"bottomRight": @{@"x": @(norm(obs.bottomRight.x)), @"y": @(norm(1 - obs.bottomRight.y))},
            @"bottomLeft":  @{@"x": @(norm(obs.bottomLeft.x)),  @"y": @(norm(1 - obs.bottomLeft.y))},
        };

        [positionalJson addObject:@{
            @"text":       candidate.string,
            @"confidence": @(obs.confidence),
            @"quad":       quad,
        }];
    }

    return @{
        @"operation":    @"ocr",
        @"observations": positionalJson,
        @"texts":        [fullText componentsJoinedByString:@"\n"],
    };
}

// ── language support ──────────────────────────────────────────────────────────

- (NSArray<NSString *> *)supportedLanguages {
    if (@available(macOS 13.0, *)) {
        VNRecognizeTextRequest *req = [[VNRecognizeTextRequest alloc] init];
        NSError *err = nil;
        NSArray<NSString *> *langs = [req supportedRecognitionLanguagesAndReturnError:&err];
        if (langs && !err) {
            return langs;
        }
    }
    return @[@"zh-Hans", @"zh-Hant", @"en-US", @"ja-JP"];
}

// ── OCR core ──────────────────────────────────────────────────────────────────

- (nullable NSDictionary *)recognitionResultFromImage:(NSString *)imagePath error:(NSError **)error {
    NSImage *image = [[NSImage alloc] initByReferencingFile:imagePath];
    if (!image) {
        if (error) {
            *error = [NSError errorWithDomain:OCRErrorDomain
                                         code:OCRErrorImageLoadFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to load image: %@", imagePath]}];
        }
        return nil;
    }

    CGImageRef cgImage = [image CGImageForProposedRect:nil context:nil hints:nil];
    if (!cgImage) {
        if (error) {
            *error = [NSError errorWithDomain:OCRErrorDomain
                                         code:OCRErrorImageConversionFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to convert image: %@", imagePath]}];
        }
        return nil;
    }

    __block NSArray<VNRecognizedTextObservation *> *observations = nil;
    __block NSError *vnError = nil;

    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc]
        initWithCompletionHandler:^(VNRequest *req, NSError *err) {
            vnError = err;
            observations = req.results;
        }];

    request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = YES;
    request.minimumTextHeight = 0.01;

    if (@available(macOS 13.0, *)) {
        request.revision = VNRecognizeTextRequestRevision3;
    } else if (@available(macOS 11.0, *)) {
        request.revision = VNRecognizeTextRequestRevision2;
    } else {
        request.revision = VNRecognizeTextRequestRevision1;
    }

    if (self.recLangs) {
        NSMutableArray<NSString *> *langs = [NSMutableArray array];
        for (NSString *l in [self.recLangs componentsSeparatedByString:@","]) {
            NSString *trimmed = [l stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (trimmed.length > 0) [langs addObject:trimmed];
        }
        request.recognitionLanguages = langs;
    } else {
        request.recognitionLanguages = [self supportedLanguages];
    }

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cgImage options:@{}];
    if (![handler performRequests:@[request] error:error]) return nil;
    if (vnError) { if (error) *error = vnError; return nil; }

    NSMutableArray<NSDictionary *> *positionalJson = [NSMutableArray array];
    NSMutableArray<NSString *> *fullText = [NSMutableArray array];

    for (VNRecognizedTextObservation *obs in observations) {
        VNRecognizedText *candidate = [[obs topCandidates:1] firstObject];
        if (!candidate) continue;

        [fullText addObject:candidate.string];

        NSDictionary *quad = @{
            @"topLeft":     @{@"x": @(norm(obs.topLeft.x)),     @"y": @(norm(1 - obs.topLeft.y))},
            @"topRight":    @{@"x": @(norm(obs.topRight.x)),    @"y": @(norm(1 - obs.topRight.y))},
            @"bottomRight": @{@"x": @(norm(obs.bottomRight.x)), @"y": @(norm(1 - obs.bottomRight.y))},
            @"bottomLeft":  @{@"x": @(norm(obs.bottomLeft.x)),  @"y": @(norm(1 - obs.bottomLeft.y))},
        };

        [positionalJson addObject:@{
            @"text":       candidate.string,
            @"confidence": @(obs.confidence),
            @"quad":       quad,
        }];
    }

    NSDictionary *info = @{
        @"filename": [imagePath lastPathComponent],
        @"filepath": MVRelativePath(imagePath),
        @"width":    @(CGImageGetWidth(cgImage)),
        @"height":   @(CGImageGetHeight(cgImage)),
    };

    NSDictionary *result = @{
        @"operation":    @"ocr",
        @"info":         info,
        @"observations": positionalJson,
        @"texts":        [fullText componentsJoinedByString:@"\n"],
    };
    return result;
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

// Canonical file extension for each format (jpeg→jpg, tif→tiff, etc.)
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

// ── debug image ───────────────────────────────────────────────────────────────

/// Returns the written image path, or nil on failure.
- (nullable NSString *)drawDebugImage:(NSString *)imagePath observations:(NSArray *)observations error:(NSError **)error {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
    if (!image) {
        if (error) {
            *error = [NSError errorWithDomain:OCRErrorDomain
                                         code:OCRErrorImageLoadFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to load image: %@", imagePath]}];
        }
        return nil;
    }

    NSSize size = image.size;
    NSImage *newImage = [[NSImage alloc] initWithSize:size];
    [newImage lockFocus];
    [image drawInRect:NSMakeRect(0, 0, size.width, size.height)];

    if (!observations) {
        [newImage unlockFocus];
        if (error) {
            *error = [NSError errorWithDomain:OCRErrorDomain
                                         code:OCRErrorJSONParsingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Missing observations for debug overlay"}];
        }
        return nil;
    }

    [[NSColor redColor] setStroke];

    for (NSDictionary *obs in observations) {
        NSDictionary<NSString *, NSDictionary<NSString *, NSNumber *> *> *quad = obs[@"quad"];
        if (!quad) continue;

        NSPoint tl = NSMakePoint([quad[@"topLeft"][@"x"]     doubleValue] * size.width,
                                 (1 - [quad[@"topLeft"][@"y"]     doubleValue]) * size.height);
        NSPoint tr = NSMakePoint([quad[@"topRight"][@"x"]    doubleValue] * size.width,
                                 (1 - [quad[@"topRight"][@"y"]    doubleValue]) * size.height);
        NSPoint br = NSMakePoint([quad[@"bottomRight"][@"x"] doubleValue] * size.width,
                                 (1 - [quad[@"bottomRight"][@"y"] doubleValue]) * size.height);
        NSPoint bl = NSMakePoint([quad[@"bottomLeft"][@"x"]  doubleValue] * size.width,
                                 (1 - [quad[@"bottomLeft"][@"y"]  doubleValue]) * size.height);

        NSBezierPath *path = [NSBezierPath bezierPath];
        path.lineWidth = 1.0;
        [path moveToPoint:tl];
        [path lineToPoint:tr];
        [path lineToPoint:br];
        [path lineToPoint:bl];
        [path closePath];
        [path stroke];
    }

    [newImage unlockFocus];

    NSString *fmt = self.boxesFormat.length ? self.boxesFormat : @"png";
    NSBitmapImageFileType bitmapType = bitmapTypeForFormat(fmt);
    NSString *ext = extensionForFormat(fmt);
    NSDictionary *props = (bitmapType == NSBitmapImageFileTypeJPEG)
        ? @{NSImageCompressionFactor: @(0.85)}
        : @{};

    NSString *baseName = [[[imagePath lastPathComponent] stringByDeletingPathExtension]
                          stringByAppendingString:@"_boxes"];
    NSString *outputFileName = [baseName stringByAppendingPathExtension:ext];
    NSString *dir = self.artifactsDir.length ? self.artifactsDir : [imagePath stringByDeletingLastPathComponent];
    NSFileManager *fm = [NSFileManager defaultManager];
    if (self.artifactsDir.length && ![fm fileExistsAtPath:self.artifactsDir]) {
        if (![fm createDirectoryAtPath:self.artifactsDir withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    }
    NSString *fullOut = [dir stringByAppendingPathComponent:outputFileName];
    NSData *tiff = [newImage TIFFRepresentation];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiff];
    NSData *imgData = [bitmap representationUsingType:bitmapType properties:props];
    if (!imgData) {
        if (error) {
            *error = [NSError errorWithDomain:OCRErrorDomain
                                         code:OCRErrorImageConversionFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to encode %@: %@", ext, fullOut]}];
        }
        return nil;
    }
    if (![imgData writeToFile:fullOut options:NSDataWritingAtomic error:error]) return nil;
    fprintf(stderr, "Debug image saved to: %s\n", fullOut.UTF8String);
    return fullOut;
}

@end
