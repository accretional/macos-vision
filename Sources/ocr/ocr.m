#import "ocr.h"
#import <Cocoa/Cocoa.h>
#import <Vision/Vision.h>

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
    if (self.lang) {
        NSArray<NSString *> *languages = [self supportedLanguages];
        printf("Supported recognition languages:\n");
        for (NSString *l in languages) {
            printf("- %s\n", l.UTF8String);
        }
        return YES;
    }

    if (self.img) {
        return [self processSingleImage:self.img outputDir:self.output error:error];
    } else if (self.imgDir) {
        return [self processBatchImages:self.imgDir outputDir:self.outputDir error:error];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:OCRErrorDomain
                                         code:OCRErrorMissingInput
                                     userInfo:@{NSLocalizedDescriptionKey: @"Either --img or --img-dir must be provided"}];
        }
        return NO;
    }
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

// ── single image ──────────────────────────────────────────────────────────────

- (BOOL)processSingleImage:(NSString *)imagePath outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    NSString *jsonResult = [self extractTextFromImage:imagePath error:error];
    if (!jsonResult) return NO;

    if (outputDir) {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:outputDir]) {
            if (![fm createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:error]) {
                return NO;
            }
        }
        NSString *inputFileName = [imagePath lastPathComponent];
        NSString *outputFileName = [[inputFileName stringByDeletingPathExtension] stringByAppendingPathExtension:@"json"];
        NSString *outputPath = [outputDir stringByAppendingPathComponent:outputFileName];
        if (![jsonResult writeToFile:outputPath atomically:YES encoding:NSUTF8StringEncoding error:error]) {
            return NO;
        }
        printf("OCR result saved to: %s\n", outputPath.UTF8String);
    } else {
        printf("%s\n", jsonResult.UTF8String);
    }

    if (self.debug) {
        return [self drawDebugImage:imagePath jsonResult:jsonResult error:error];
    }
    return YES;
}

// ── batch mode ────────────────────────────────────────────────────────────────

- (BOOL)processBatchImages:(NSString *)imgDir outputDir:(nullable NSString *)outputDir error:(NSError **)error {
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

    NSMutableString *mergedText = [NSMutableString string];

    for (NSString *imagePath in imageFiles) {
        NSString *fullImagePath = [imgDir stringByAppendingPathComponent:imagePath];
        NSString *jsonResult = [self extractTextFromImage:fullImagePath error:error];
        if (!jsonResult) return NO;

        if (outputDir) {
            NSString *outputFileName = [[imagePath lastPathComponent] stringByAppendingString:@".json"];
            NSString *outputPath = [outputDir stringByAppendingPathComponent:outputFileName];
            if (![jsonResult writeToFile:outputPath atomically:YES encoding:NSUTF8StringEncoding error:error]) {
                return NO;
            }
        }

        if (self.merge) {
            NSData *data = [jsonResult dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
            NSString *texts = json[@"texts"];
            if (texts) {
                [mergedText appendString:texts];
                [mergedText appendString:@"\n\n"];
            }
        }

        if (self.debug) {
            if (![self drawDebugImage:fullImagePath jsonResult:jsonResult error:error]) return NO;
        }
    }

    if (self.merge && outputDir) {
        NSString *mergedPath = [outputDir stringByAppendingPathComponent:@"merged_output.txt"];
        if (![mergedText writeToFile:mergedPath atomically:YES encoding:NSUTF8StringEncoding error:error]) {
            return NO;
        }
    }
    return YES;
}

// ── OCR core ──────────────────────────────────────────────────────────────────

- (nullable NSString *)extractTextFromImage:(NSString *)imagePath error:(NSError **)error {
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

    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *absolutePath = [fm.currentDirectoryPath stringByAppendingPathComponent:imagePath];

    NSDictionary *info = @{
        @"filename": [imagePath lastPathComponent],
        @"filepath": absolutePath,
        @"width":    @(CGImageGetWidth(cgImage)),
        @"height":   @(CGImageGetHeight(cgImage)),
    };

    NSDictionary *result = @{
        @"info":         info,
        @"observations": positionalJson,
        @"texts":        [fullText componentsJoinedByString:@"\n"],
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:error];
    if (!jsonData) return nil;
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

// ── debug image ───────────────────────────────────────────────────────────────

- (BOOL)drawDebugImage:(NSString *)imagePath jsonResult:(NSString *)jsonResult error:(NSError **)error {
    NSImage *image = [[NSImage alloc] initWithContentsOfFile:imagePath];
    if (!image) {
        if (error) {
            *error = [NSError errorWithDomain:OCRErrorDomain
                                         code:OCRErrorImageLoadFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to load image: %@", imagePath]}];
        }
        return NO;
    }

    NSSize size = image.size;
    NSImage *newImage = [[NSImage alloc] initWithSize:size];
    [newImage lockFocus];
    [image drawInRect:NSMakeRect(0, 0, size.width, size.height)];

    NSData *data = [jsonResult dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *json = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if (!json) { [newImage unlockFocus]; return NO; }
    NSArray<NSDictionary *> *observations = json[@"observations"];
    if (!observations) {
        [newImage unlockFocus];
        if (error) {
            *error = [NSError errorWithDomain:OCRErrorDomain
                                         code:OCRErrorJSONParsingFailed
                                     userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse observations from JSON"}];
        }
        return NO;
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

    NSString *outputFileName = [[imagePath stringByDeletingPathExtension]
                                stringByAppendingString:@"_boxes.png"];
    NSData *tiff = [newImage TIFFRepresentation];
    NSBitmapImageRep *bitmap = [NSBitmapImageRep imageRepWithData:tiff];
    NSData *pngData = [bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (!pngData) {
        if (error) {
            *error = [NSError errorWithDomain:OCRErrorDomain
                                         code:OCRErrorImageConversionFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to encode PNG: %@", outputFileName]}];
        }
        return NO;
    }
    if (![pngData writeToFile:outputFileName options:NSDataWritingAtomic error:error]) return NO;
    printf("Debug image saved to: %s\n", outputFileName.UTF8String);
    return YES;
}

// ── helpers ───────────────────────────────────────────────────────────────────

- (BOOL)isImageFile:(NSString *)filePath {
    NSArray<NSString *> *extensions = @[@"jpg", @"jpeg", @"png", @"webp"];
    return [extensions containsObject:[filePath.pathExtension lowercaseString]];
}

@end
