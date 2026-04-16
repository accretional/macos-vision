#import "main.h"
#import "common/MVJsonEmit.h"
#import <Cocoa/Cocoa.h>

static NSString * const DebugErrorDomain = @"DebugError";
typedef NS_ENUM(NSInteger, DebugErrorCode) {
    DebugErrorMissingInput    = 1,
    DebugErrorImageLoadFailed = 2,
};

@implementation DebugProcessor

- (BOOL)runWithError:(NSError **)error {
    if (!self.inputPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:DebugErrorDomain
                                         code:DebugErrorMissingInput
                                     userInfo:@{NSLocalizedDescriptionKey: @"Provide --input <image>"}];
        }
        return NO;
    }
    NSDictionary *inner = [self imageMetadataDict:self.inputPath error:error];
    if (!inner) return NO;
    NSDictionary *envelope = MVMakeEnvelope(@"debug", @"metadata", self.inputPath, inner);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

- (nullable NSDictionary *)imageMetadataDict:(NSString *)imagePath error:(NSError **)error {
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
    return @{
        @"filename": [imagePath lastPathComponent],
        @"filepath": absolutePath,
        @"width":    @(CGImageGetWidth(cgImage)),
        @"height":   @(CGImageGetHeight(cgImage)),
        @"filesize": attrs[NSFileSize],
    };
}

@end
