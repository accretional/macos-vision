#import "main.h"
#import <Cocoa/Cocoa.h>

static NSString * const DebugErrorDomain = @"DebugError";
typedef NS_ENUM(NSInteger, DebugErrorCode) {
    DebugErrorMissingInput    = 1,
    DebugErrorImageLoadFailed = 2,
    DebugErrorWriteFailed     = 3,
};

@implementation DebugProcessor

// ── public entry point ────────────────────────────────────────────────────────

- (BOOL)runWithError:(NSError **)error {
    if (self.img) {
        return [self processImage:self.img outputDir:self.output error:error];
    } else if (self.imgDir) {
        return [self processBatch:self.imgDir outputDir:self.outputDir error:error];
    } else {
        if (error) {
            *error = [NSError errorWithDomain:DebugErrorDomain
                                         code:DebugErrorMissingInput
                                     userInfo:@{NSLocalizedDescriptionKey: @"Either --img or --img-dir must be provided"}];
        }
        return NO;
    }
}

// ── single image ──────────────────────────────────────────────────────────────

- (BOOL)processImage:(NSString *)imagePath outputDir:(nullable NSString *)outputDir error:(NSError **)error {
    NSString *jsonResult = [self imageMetadataJSON:imagePath error:error];
    if (!jsonResult) return NO;

    if (outputDir) {
        NSFileManager *fm = [NSFileManager defaultManager];
        if (![fm fileExistsAtPath:outputDir]) {
            if (![fm createDirectoryAtPath:outputDir withIntermediateDirectories:YES attributes:nil error:error]) {
                return NO;
            }
        }
        NSString *outputFileName = [[[imagePath lastPathComponent] stringByDeletingPathExtension]
                                    stringByAppendingPathExtension:@"json"];
        NSString *outputPath = [outputDir stringByAppendingPathComponent:outputFileName];
        if (![jsonResult writeToFile:outputPath atomically:YES encoding:NSUTF8StringEncoding error:error]) {
            return NO;
        }
        printf("Debug info saved to: %s\n", outputPath.UTF8String);
    } else {
        printf("%s\n", jsonResult.UTF8String);
    }
    return YES;
}

// ── batch mode ────────────────────────────────────────────────────────────────

- (BOOL)processBatch:(NSString *)imgDir outputDir:(nullable NSString *)outputDir error:(NSError **)error {
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

    for (NSString *imagePath in imageFiles) {
        NSString *fullPath = [imgDir stringByAppendingPathComponent:imagePath];
        NSString *jsonResult = [self imageMetadataJSON:fullPath error:error];
        if (!jsonResult) return NO;

        if (outputDir) {
            NSString *outputFileName = [[imagePath lastPathComponent] stringByAppendingString:@".json"];
            NSString *outputPath = [outputDir stringByAppendingPathComponent:outputFileName];
            if (![jsonResult writeToFile:outputPath atomically:YES encoding:NSUTF8StringEncoding error:error]) {
                return NO;
            }
        }
    }
    return YES;
}

// ── metadata extraction ───────────────────────────────────────────────────────

- (nullable NSString *)imageMetadataJSON:(NSString *)imagePath error:(NSError **)error {
    NSFileManager *fm = [NSFileManager defaultManager];
    NSString *absolutePath = [imagePath isAbsolutePath]
        ? imagePath
        : [fm.currentDirectoryPath stringByAppendingPathComponent:imagePath];

    NSImage *image = [[NSImage alloc] initByReferencingFile:absolutePath];
    if (!image) {
        if (error) {
            *error = [NSError errorWithDomain:DebugErrorDomain
                                         code:DebugErrorImageLoadFailed
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Failed to load image: %@", absolutePath]}];
        }
        return nil;
    }
    NSDictionary *attrs = [fm attributesOfItemAtPath:absolutePath error:error];
    if (!attrs) return nil;

    CGImageRef cgImage = [image CGImageForProposedRect:nil context:nil hints:nil];
    NSDictionary *result = @{
        @"filename": [imagePath lastPathComponent],
        @"filepath": absolutePath,
        @"width":    @(CGImageGetWidth(cgImage)),
        @"height":   @(CGImageGetHeight(cgImage)),
        @"filesize": attrs[NSFileSize],
    };

    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result
                                                       options:NSJSONWritingPrettyPrinted
                                                         error:error];
    if (!jsonData) return nil;
    return [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
}

// ── helpers ───────────────────────────────────────────────────────────────────

- (BOOL)isImageFile:(NSString *)filePath {
    NSArray<NSString *> *extensions = @[@"jpg", @"jpeg", @"png", @"webp"];
    return [extensions containsObject:[filePath.pathExtension lowercaseString]];
}

@end
