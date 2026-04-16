#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SegmentProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *inputPath;
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// Directory for PNG masks; if unset, files are written next to the input image.
@property (nonatomic, copy, nullable) NSString *artifactsDir;
// foreground-mask | person-segment | person-mask | attention-saliency | objectness-saliency
@property (nonatomic, copy) NSString *operation;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
