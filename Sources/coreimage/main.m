#import "main.h"
#import "common/MVJsonEmit.h"
#import "common/MVMjpegStream.h"
#import <CoreImage/CoreImage.h>
#import <Cocoa/Cocoa.h>

static NSString * const CIProcessorErrorDomain = @"CIProcessorError";
typedef NS_ENUM(NSInteger, CIProcessorErrorCode) {
    CIProcessorErrorUnknownOperation  = 1,
    CIProcessorErrorMissingInput      = 2,
    CIProcessorErrorMissingFilter     = 3,
    CIProcessorErrorImageLoadFailed   = 10,
    CIProcessorErrorUnknownFilter     = 11,
    CIProcessorErrorBadParams         = 12,
    CIProcessorErrorNoOutputImage     = 13,
    CIProcessorErrorEncodeFailed      = 14,
    CIProcessorErrorBadFormat         = 15,
};

@implementation CIProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation    = @"apply-filter";
        _outputFormat = @"png";
    }
    return self;
}

// ── Public entry point ────────────────────────────────────────────────────────

- (BOOL)runWithError:(NSError **)error {
    if (self.stream)    return [self runStreamWithError:error];      // S→S or S→F
    if (self.streamOut) return [self runFileToStreamWithError:error]; // F→S
    NSArray *validOps = @[@"apply-filter", @"suggest-filters", @"list-filters", @"auto-adjust"];
    if (![validOps containsObject:self.operation]) {
        if (error) {
            *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                         code:CIProcessorErrorUnknownOperation
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Unknown operation '%@'. Valid: %@",
                                                     self.operation, [validOps componentsJoinedByString:@", "]]}];
        }
        return NO;
    }

    // Validate --format early
    NSString *fmt = self.outputFormat.lowercaseString;
    NSArray *validFormats = @[@"png", @"jpg", @"jpeg", @"heif", @"tiff"];
    if (![validFormats containsObject:fmt]) {
        if (error) {
            *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                         code:CIProcessorErrorBadFormat
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:
                                                     @"Unknown --format '%@'. Valid: png, jpg, heif, tiff.",
                                                     self.outputFormat]}];
        }
        return NO;
    }

    if ([self.operation isEqualToString:@"list-filters"]) {
        NSDictionary *result = [self listFiltersWithError:error];
        if (!result) return NO;
        NSDictionary *envelope = MVMakeEnvelope(@"coreimage", self.operation, nil, result);
        return MVEmitEnvelope(envelope, self.jsonOutput, error);
    }

    if ([self.operation isEqualToString:@"suggest-filters"]) {
        NSDictionary *result = [self suggestFiltersWithError:error];
        if (!result) return NO;
        NSDictionary *envelope = MVMakeEnvelope(@"coreimage", self.operation, self.inputPath, result);
        return MVEmitEnvelope(envelope, self.jsonOutput, error);
    }

    if ([self.operation isEqualToString:@"auto-adjust"]) {
        NSDictionary *result = [self autoAdjustWithError:error];
        if (!result) return NO;
        NSDictionary *envelope = MVMakeEnvelope(@"coreimage", self.operation, self.inputPath, result);
        return MVEmitEnvelope(envelope, self.jsonOutput, error);
    }

    // apply-filter
    if (!self.filterName.length) {
        if (error) {
            *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                         code:CIProcessorErrorMissingFilter
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Provide --filter-name <CIFilterName>, e.g. CISepiaTone. "
                                                    @"Use --operation list-filters to browse available filters."}];
        }
        return NO;
    }

    NSDictionary *result = [self applyFilterWithError:error];
    if (!result) return NO;
    NSDictionary *envelope = MVMakeEnvelope(@"coreimage", self.operation, self.inputPath, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── S→S / S→F stream mode ─────────────────────────────────────────────────────

- (BOOL)runStreamWithError:(NSError **)error {
    NSString *op = self.operation.length ? self.operation : @"apply-filter";

    // list-filters has no pixel transform; suggest-filters only streams when --apply is set
    if ([op isEqualToString:@"list-filters"] ||
        ([op isEqualToString:@"suggest-filters"] && !self.applyFilters)) {
        if (error) *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                               code:CIProcessorErrorUnknownOperation
                             userInfo:@{NSLocalizedDescriptionKey:
                                 [NSString stringWithFormat:@"coreimage '%@' has no stream mode; omit --no-stream or use a different operation%@",
                                  op, [op isEqualToString:@"suggest-filters"] ? @" (or add --apply to render the suggested filters)" : @""]}];
        return NO;
    }

    if ([op isEqualToString:@"apply-filter"] && !self.filterName.length) {
        if (error) *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                               code:CIProcessorErrorMissingFilter
                             userInfo:@{NSLocalizedDescriptionKey:
                                 @"Provide --filter-name <CIFilterName>"}];
        return NO;
    }

    // Create filter once; update kCIInputImageKey per frame (apply-filter only)
    CIFilter *filter = nil;
    BOOL filterNeedsImage = NO;
    if ([op isEqualToString:@"apply-filter"]) {
        filter = [CIFilter filterWithName:self.filterName];
        if (!filter) {
            if (error) *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                                   code:CIProcessorErrorUnknownFilter
                                 userInfo:@{NSLocalizedDescriptionKey:
                                     [NSString stringWithFormat:@"Unknown filter '%@'", self.filterName]}];
            return NO;
        }
        [filter setDefaults];
        // Apply scalar params once
        if (self.filterParamsJSON.length) {
            NSData *d = [self.filterParamsJSON dataUsingEncoding:NSUTF8StringEncoding];
            NSDictionary *params = d ? [NSJSONSerialization JSONObjectWithData:d options:0 error:nil] : nil;
            if ([params isKindOfClass:[NSDictionary class]]) {
                [params enumerateKeysAndObjectsUsingBlock:^(NSString *key, id val, BOOL *stop) {
                    if ([val isKindOfClass:[NSNumber class]]) [filter setValue:val forKey:key];
                }];
            }
        }
        filterNeedsImage = [filter.inputKeys containsObject:kCIInputImageKey];
    }

    MVMjpegReader *reader = [[MVMjpegReader alloc] initWithFileDescriptor:STDIN_FILENO];
    MVMjpegWriter *writer = [[MVMjpegWriter alloc] initWithFileDescriptor:STDOUT_FILENO];
    writer.ndjsonOutputPath = self.ndjsonOutput;

    CIContext *ctx = [CIContext contextWithOptions:nil];
    CGColorSpaceRef sRGB = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);

    [reader readFramesWithHandler:^(NSData *jpeg, NSDictionary<NSString *, NSString *> *inHeaders) {
        NSMutableDictionary *outHeaders = [NSMutableDictionary dictionaryWithDictionary:inHeaders];
        [outHeaders removeObjectForKey:@"Content-Type"];
        [outHeaders removeObjectForKey:@"Content-Length"];

        // Decode JPEG → CIImage
        CIImage *frameCI = [CIImage imageWithData:jpeg];
        if (!frameCI) { [writer writeFrame:jpeg extraHeaders:outHeaders]; return; }

        CIImage *outputCI = nil;

        if ([op isEqualToString:@"apply-filter"]) {
            if (filterNeedsImage) [filter setValue:frameCI forKey:kCIInputImageKey];
            outputCI = filter.outputImage;
            // Clamp infinite extent (generators)
            if (outputCI && (isinf(outputCI.extent.size.width) || isinf(outputCI.extent.size.height))) {
                outputCI = [outputCI imageByCroppingToRect:frameCI.extent];
            }
        } else if ([op isEqualToString:@"auto-adjust"] ||
                   [op isEqualToString:@"suggest-filters"]) {
            NSArray<CIFilter *> *adjustFilters = [frameCI autoAdjustmentFiltersWithOptions:nil];
            CIImage *current = frameCI;
            for (CIFilter *f in adjustFilters) {
                [f setValue:current forKey:kCIInputImageKey];
                CIImage *out = f.outputImage;
                if (out) current = out;
            }
            outputCI = current;
        }

        if (!outputCI) { [writer writeFrame:jpeg extraHeaders:outHeaders]; return; }

        NSData *outJpeg = [ctx JPEGRepresentationOfImage:outputCI colorSpace:sRGB options:@{}];
        [writer writeFrame:(outJpeg ?: jpeg) extraHeaders:outHeaders];
    }];

    CGColorSpaceRelease(sRGB);
    return YES;
}

// ── F→S mode: file input → single MJPEG frame out ────────────────────────────

- (BOOL)runFileToStreamWithError:(NSError **)error {
    NSString *op = self.operation.length ? self.operation : @"apply-filter";

    // list-filters has no image input; fall through to file mode
    if ([op isEqualToString:@"list-filters"]) {
        self.streamOut = NO;
        return [self runWithError:error];
    }

    NSDictionary *result = nil;
    NSData *frameJpeg = nil;

    if ([op isEqualToString:@"apply-filter"]) {
        // applyFilterWithError: saves the filtered image and returns result dict
        result = [self applyFilterWithError:error];
        if (!result) return NO;

        // Use the filtered image file as the MJPEG frame
        NSString *outPath = result[@"output"];
        if (outPath.length) {
            // Resolve relative path
            if (![outPath hasPrefix:@"/"]) {
                outPath = [[[NSFileManager defaultManager] currentDirectoryPath]
                           stringByAppendingPathComponent:outPath];
            }
            CIImage *ciImg = [CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:outPath]];
            if (ciImg) {
                CIContext *ctx = [CIContext contextWithOptions:nil];
                CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                frameJpeg = [ctx JPEGRepresentationOfImage:ciImg colorSpace:cs options:@{}];
                CGColorSpaceRelease(cs);
            }
        }
    } else if ([op isEqualToString:@"suggest-filters"] || [op isEqualToString:@"auto-adjust"]) {
        result = [op isEqualToString:@"suggest-filters"]
            ? [self suggestFiltersWithError:error]
            : [self autoAdjustWithError:error];
        if (!result) return NO;

        // When suggest-filters --apply rendered an output, use it as the stream frame
        NSString *outPath = result[@"output"];
        if (outPath.length) {
            if (![outPath hasPrefix:@"/"]) {
                outPath = [[[NSFileManager defaultManager] currentDirectoryPath]
                           stringByAppendingPathComponent:outPath];
            }
            CIImage *ciImg = [CIImage imageWithContentsOfURL:[NSURL fileURLWithPath:outPath]];
            if (ciImg) {
                CIContext *ctx = [CIContext contextWithOptions:nil];
                CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
                frameJpeg = [ctx JPEGRepresentationOfImage:ciImg colorSpace:cs options:@{}];
                CGColorSpaceRelease(cs);
            }
        }
    }

    // Fall back to original image as JPEG frame
    if (!frameJpeg && self.inputPath.length) {
        NSString *ext = self.inputPath.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"jpg"] || [ext isEqualToString:@"jpeg"])
            frameJpeg = [NSData dataWithContentsOfFile:self.inputPath];
        if (!frameJpeg) {
            NSImage *img = [[NSImage alloc] initWithContentsOfFile:self.inputPath];
            NSBitmapImageRep *rep = img ? [[NSBitmapImageRep alloc] initWithData:[img TIFFRepresentation]] : nil;
            frameJpeg = [rep representationUsingType:NSBitmapImageFileTypeJPEG
                                          properties:@{NSImageCompressionFactor: @0.85}];
        }
    }

    if (!frameJpeg) {
        NSString *detail = (!self.inputPath.length && [op isEqualToString:@"apply-filter"])
            ? @"Generator/gradient filters have no source image; provide --input <image> to supply the MJPEG frame"
            : @"Failed to encode image as JPEG for stream output";
        if (error) *error = [NSError errorWithDomain:CIProcessorErrorDomain code:CIProcessorErrorEncodeFailed
                            userInfo:@{NSLocalizedDescriptionKey: detail}];
        return NO;
    }

    NSDictionary *envelope = MVMakeEnvelope(@"coreimage", op, self.inputPath, result ?: @{});
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:envelope options:0 error:nil];
    NSString *jsonStr = jsonData ? [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding] : @"{}";
    if (self.jsonOutput.length) MVEmitEnvelope(envelope, self.jsonOutput, nil);

    MVMjpegWriter *writer = [[MVMjpegWriter alloc] initWithFileDescriptor:STDOUT_FILENO];
    writer.ndjsonOutputPath = self.ndjsonOutput;
    [writer writeFrame:frameJpeg extraHeaders:@{ [NSString stringWithFormat:@"X-MV-coreimage-%@", op]: jsonStr }];
    return YES;
}

// ── apply-filter ──────────────────────────────────────────────────────────────

- (nullable NSDictionary *)applyFilterWithError:(NSError **)error {
    CIFilter *filter = [CIFilter filterWithName:self.filterName];
    if (!filter) {
        if (error) {
            *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                         code:CIProcessorErrorUnknownFilter
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:
                                                     @"Unknown filter '%@'. Use --operation list-filters to browse available filters.",
                                                     self.filterName]}];
        }
        return nil;
    }

    [filter setDefaults];

    CIImage *ciImage = nil;
    BOOL filterNeedsImage = [filter.inputKeys containsObject:kCIInputImageKey];
    if (filterNeedsImage) {
        if (!self.inputPath.length) {
            if (error) {
                *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                             code:CIProcessorErrorMissingInput
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:
                                                         @"Filter '%@' requires an input image. Provide --input <image>.",
                                                         self.filterName]}];
            }
            return nil;
        }
        NSURL *inputURL = [NSURL fileURLWithPath:self.inputPath];
        ciImage = [CIImage imageWithContentsOfURL:inputURL];
        if (!ciImage) {
            if (error) {
                *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                             code:CIProcessorErrorImageLoadFailed
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"Failed to load image: %@",
                                                         self.inputPath]}];
            }
            return nil;
        }
        [filter setValue:ciImage forKey:kCIInputImageKey];
    }

    // Parse and apply scalar params from JSON
    NSMutableDictionary *appliedParams = [NSMutableDictionary dictionary];
    if (self.filterParamsJSON.length) {
        NSData *paramsData = [self.filterParamsJSON dataUsingEncoding:NSUTF8StringEncoding];
        NSError *jsonError = nil;
        id parsed = [NSJSONSerialization JSONObjectWithData:paramsData options:0 error:&jsonError];
        if (!parsed || ![parsed isKindOfClass:[NSDictionary class]]) {
            if (error) {
                *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                             code:CIProcessorErrorBadParams
                                         userInfo:@{NSLocalizedDescriptionKey:
                                                        [NSString stringWithFormat:@"Invalid --filter-params JSON: %@",
                                                         jsonError.localizedDescription ?: @"must be a JSON object"]}];
            }
            return nil;
        }
        NSDictionary *params = (NSDictionary *)parsed;
        [params enumerateKeysAndObjectsUsingBlock:^(NSString *key, id value, BOOL *stop) {
            if ([value isKindOfClass:[NSNumber class]]) {
                [filter setValue:value forKey:key];
                appliedParams[key] = value;
            }
        }];
    }

    CIImage *outputImage = filter.outputImage;
    if (!outputImage) {
        if (error) {
            *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                         code:CIProcessorErrorNoOutputImage
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:
                                                     @"Filter '%@' produced no output image.", self.filterName]}];
        }
        return nil;
    }

    // Clamp infinite extent (generators, gradients)
    CGRect renderRect = outputImage.extent;
    if (isinf(renderRect.size.width) || isinf(renderRect.size.height) ||
        isinf(renderRect.origin.x) || isinf(renderRect.origin.y)) {
        renderRect = ciImage ? ciImage.extent : CGRectMake(0, 0, 1024, 1024);
        outputImage = [outputImage imageByCroppingToRect:renderRect];
    }

    NSDate *start = self.debug ? [NSDate date] : nil;

    NSString *outPath = [self resolveOutputPathForInput:self.inputPath filter:self.filterName];
    if (![self ensureDirectory:outPath.stringByDeletingLastPathComponent error:error]) return nil;

    NSData *imgData = [self renderImage:outputImage error:error];
    if (!imgData) return nil;
    if (![imgData writeToFile:outPath options:NSDataWritingAtomic error:error]) return nil;

    NSMutableDictionary *result = [@{
        @"filter":    self.filterName,
        @"input":     self.inputPath.length ? MVRelativePath(self.inputPath) : @"",
        @"output":    MVRelativePath(outPath),
        @"format":    [self outputExtension],
        @"artifacts": @[MVArtifactEntry(outPath, @"filtered_image")],
    } mutableCopy];

    if (appliedParams.count > 0) result[@"params"] = [appliedParams copy];

    if (self.debug && start) {
        result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    return result;
}

// ── auto-adjust ───────────────────────────────────────────────────────────────

- (nullable NSDictionary *)autoAdjustWithError:(NSError **)error {
    if (!self.inputPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                         code:CIProcessorErrorMissingInput
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"auto-adjust requires an input image. Provide --input <image>."}];
        }
        return nil;
    }
    NSURL *inputURL = [NSURL fileURLWithPath:self.inputPath];
    CIImage *image = [CIImage imageWithContentsOfURL:inputURL];
    if (!image) {
        if (error) {
            *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                         code:CIProcessorErrorImageLoadFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to load image: %@",
                                                     self.inputPath]}];
        }
        return nil;
    }

    NSDate *start = self.debug ? [NSDate date] : nil;

    NSArray<CIFilter *> *filters = [image autoAdjustmentFiltersWithOptions:nil];

    // Apply all filters in sequence
    CIImage *current = image;
    NSMutableArray<NSDictionary *> *filterEntries = [NSMutableArray arrayWithCapacity:filters.count];
    for (CIFilter *f in filters) {
        [f setValue:current forKey:kCIInputImageKey];
        CIImage *out = f.outputImage;
        if (out) current = out;
        [filterEntries addObject:@{ @"name": f.name }];
    }

    // Clamp infinite extent
    CGRect renderRect = current.extent;
    if (isinf(renderRect.size.width) || isinf(renderRect.size.height) ||
        isinf(renderRect.origin.x) || isinf(renderRect.origin.y)) {
        renderRect = image.extent;
        current = [current imageByCroppingToRect:renderRect];
    }

    NSString *outPath = [self resolveOutputPathForInput:self.inputPath filter:@"auto_adjust"];
    if (![self ensureDirectory:outPath.stringByDeletingLastPathComponent error:error]) return nil;

    NSData *imgData = [self renderImage:current error:error];
    if (!imgData) return nil;
    if (![imgData writeToFile:outPath options:NSDataWritingAtomic error:error]) return nil;

    NSMutableDictionary *result = [@{
        @"input":     MVRelativePath(self.inputPath),
        @"output":    MVRelativePath(outPath),
        @"format":    [self outputExtension],
        @"filters":   [filterEntries copy],
        @"artifacts": @[MVArtifactEntry(outPath, @"adjusted_image")],
    } mutableCopy];

    if (self.debug && start) {
        result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    return result;
}

// ── suggest-filters ───────────────────────────────────────────────────────────

- (nullable NSDictionary *)suggestFiltersWithError:(NSError **)error {
    if (!self.inputPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                         code:CIProcessorErrorMissingInput
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"suggest-filters requires --input <image>."}];
        }
        return nil;
    }
    NSURL *inputURL = [NSURL fileURLWithPath:self.inputPath];
    CIImage *image = [CIImage imageWithContentsOfURL:inputURL];
    if (!image) {
        if (error) {
            *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                         code:CIProcessorErrorImageLoadFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to load image: %@",
                                                     self.inputPath]}];
        }
        return nil;
    }

    NSArray<CIFilter *> *filters = [image autoAdjustmentFiltersWithOptions:nil];

    NSDate *start = self.debug ? [NSDate date] : nil;

    // Build filter detail list and optionally chain outputs for --apply
    NSMutableArray<NSDictionary *> *filterEntries = [NSMutableArray arrayWithCapacity:filters.count];
    CIImage *current = image;

    for (CIFilter *f in filters) {
        [f setValue:current forKey:kCIInputImageKey];
        CIImage *out = f.outputImage;
        if (out) current = out;

        // Collect all non-image input key values
        NSMutableDictionary *params = [NSMutableDictionary dictionary];
        for (NSString *key in f.inputKeys) {
            if ([key isEqualToString:kCIInputImageKey]) continue;
            id val = [f valueForKey:key];
            if (!val) continue;
            if ([val isKindOfClass:[NSNumber class]] || [val isKindOfClass:[NSString class]]) {
                params[key] = val;
            } else {
                params[key] = [val description];
            }
        }

        NSMutableDictionary *entry = [@{ @"name": f.name } mutableCopy];
        if (params.count > 0) entry[@"params"] = [params copy];
        [filterEntries addObject:[entry copy]];
    }

    NSMutableDictionary *result = [@{
        @"input":        MVRelativePath(self.inputPath),
        @"filter_count": @(filterEntries.count),
        @"filters":      [filterEntries copy],
    } mutableCopy];

    if (self.applyFilters) {
        // Clamp infinite extent
        CGRect renderRect = current.extent;
        if (isinf(renderRect.size.width) || isinf(renderRect.size.height) ||
            isinf(renderRect.origin.x) || isinf(renderRect.origin.y)) {
            renderRect = image.extent;
            current = [current imageByCroppingToRect:renderRect];
        }

        NSString *outPath = [self resolveOutputPathForInput:self.inputPath filter:@"suggest_filters"];
        if (![self ensureDirectory:outPath.stringByDeletingLastPathComponent error:error]) return nil;

        NSData *imgData = [self renderImage:current error:error];
        if (!imgData) return nil;
        if (![imgData writeToFile:outPath options:NSDataWritingAtomic error:error]) return nil;

        result[@"output"]    = MVRelativePath(outPath);
        result[@"format"]    = [self outputExtension];
        result[@"artifacts"] = @[MVArtifactEntry(outPath, @"adjusted_image")];
    }

    if (self.debug && start) {
        result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    return result;
}

// ── list-filters ──────────────────────────────────────────────────────────────

- (nullable NSDictionary *)listFiltersWithError:(NSError **)error {
    NSArray<NSString *> *categories = [self primaryCategoryNames];

    if (self.categoryOnly) {
        NSMutableArray<NSDictionary *> *entries = [NSMutableArray arrayWithCapacity:categories.count];
        for (NSString *cat in categories) {
            NSString *displayName = [CIFilter localizedNameForCategory:cat] ?: cat;
            NSInteger count = (NSInteger)[[CIFilter filterNamesInCategory:cat] count];
            [entries addObject:@{
                @"name":         cat,
                @"display_name": displayName,
                @"filter_count": @(count),
            }];
        }
        return @{
            @"count":      @(entries.count),
            @"categories": [entries copy],
        };
    }

    NSMutableDictionary<NSString *, NSArray *> *byCategory = [NSMutableDictionary dictionary];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];

    for (NSString *cat in categories) {
        NSArray<NSString *> *names = [[CIFilter filterNamesInCategory:cat]
                                      sortedArrayUsingSelector:@selector(compare:)];
        if (names.count > 0) {
            byCategory[cat] = names;
            [seen addObjectsFromArray:names];
        }
    }

    NSArray<NSString *> *all = [[seen allObjects] sortedArrayUsingSelector:@selector(compare:)];

    return @{
        @"count":       @(all.count),
        @"filters":     all,
        @"by_category": [byCategory copy],
    };
}

// ── helpers ───────────────────────────────────────────────────────────────────

- (nullable NSData *)renderImage:(CIImage *)image error:(NSError **)error {
    CIContext *ctx = [CIContext contextWithOptions:nil];
    CGColorSpaceRef cs = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    NSData *data = nil;
    NSString *fmt = self.outputFormat.lowercaseString;

    if ([fmt isEqualToString:@"jpg"] || [fmt isEqualToString:@"jpeg"]) {
        data = [ctx JPEGRepresentationOfImage:image colorSpace:cs options:@{}];
    } else if ([fmt isEqualToString:@"heif"]) {
        data = [ctx HEIFRepresentationOfImage:image format:kCIFormatRGBA8 colorSpace:cs options:@{}];
    } else if ([fmt isEqualToString:@"tiff"]) {
        data = [ctx TIFFRepresentationOfImage:image format:kCIFormatRGBA8 colorSpace:cs options:@{}];
    } else {
        data = [ctx PNGRepresentationOfImage:image format:kCIFormatRGBA8 colorSpace:cs options:@{}];
    }
    CGColorSpaceRelease(cs);

    if (!data && error) {
        *error = [NSError errorWithDomain:CIProcessorErrorDomain
                                     code:CIProcessorErrorEncodeFailed
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Failed to encode output image as %@",
                                                 self.outputFormat.uppercaseString]}];
    }
    return data;
}

- (NSString *)outputExtension {
    NSString *fmt = self.outputFormat.lowercaseString;
    if ([fmt isEqualToString:@"jpg"] || [fmt isEqualToString:@"jpeg"]) return @"jpg";
    if ([fmt isEqualToString:@"heif"]) return @"heif";
    if ([fmt isEqualToString:@"tiff"]) return @"tiff";
    return @"png";
}

- (BOOL)ensureDirectory:(NSString *)dir error:(NSError **)error {
    if (!dir.length) return YES;
    NSFileManager *fm = [NSFileManager defaultManager];
    if ([fm fileExistsAtPath:dir]) return YES;
    return [fm createDirectoryAtPath:dir withIntermediateDirectories:YES attributes:nil error:error];
}

/// The 14 primary filter-type categories (excludes use-type tags like kCICategoryBuiltIn).
- (NSArray<NSString *> *)primaryCategoryNames {
    return @[
        kCICategoryDistortionEffect,
        kCICategoryGeometryAdjustment,
        kCICategoryCompositeOperation,
        kCICategoryHalftoneEffect,
        kCICategoryColorAdjustment,
        kCICategoryColorEffect,
        kCICategoryTransition,
        kCICategoryTileEffect,
        kCICategoryGenerator,
        kCICategoryReduction,
        kCICategoryGradient,
        kCICategoryStylize,
        kCICategorySharpen,
        kCICategoryBlur,
    ];
}

- (NSString *)resolveOutputPathForInput:(nullable NSString *)inputPath filter:(NSString *)filterName {
    NSString *ext = [self outputExtension];
    if (self.outputPath.length) return self.outputPath;
    NSString *base = inputPath.length
        ? [[inputPath lastPathComponent] stringByDeletingPathExtension]
        : @"output";
    NSString *filename = [NSString stringWithFormat:@"%@_%@.%@", base, filterName, ext];
    if (self.artifactsDir.length) {
        return [self.artifactsDir stringByAppendingPathComponent:filename];
    }
    if (inputPath.length) {
        return [[inputPath stringByDeletingLastPathComponent] stringByAppendingPathComponent:filename];
    }
    return filename;
}

@end
