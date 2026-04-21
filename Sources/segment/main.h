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

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchSegment(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
