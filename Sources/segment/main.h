#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SegmentProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *inputPath;
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// Exact output path for single-file operations (highest priority, overrides artifactsDir).
@property (nonatomic, copy, nullable) NSString *outputPath;
/// Directory for PNG masks. Falls back to the current working directory when unset.
@property (nonatomic, copy, nullable) NSString *artifactsDir;
// foreground-mask | person-segment | person-mask | attention-saliency | objectness-saliency
@property (nonatomic, copy) NSString *operation;
/// Read MJPEG from stdin (S→S / S→F). Active when stdin piped and no --input given.
@property (nonatomic, assign) BOOL stream;
/// Write MJPEG to stdout (F→S / S→S). Active when stdout piped.
@property (nonatomic, assign) BOOL streamOut;
/// When set in stream mode, dual-write NDJSON lines to this file alongside MJPEG stdout.
@property (nonatomic, copy, nullable) NSString *ndjsonOutput;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchSegment(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
