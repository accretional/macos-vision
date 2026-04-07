#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SegmentProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *img;
@property (nonatomic, copy, nullable) NSString *output;
@property (nonatomic, copy, nullable) NSString *imgDir;
@property (nonatomic, copy, nullable) NSString *outputDir;
// foreground-mask | person-segment | person-mask | attention-saliency | objectness-saliency
@property (nonatomic, copy) NSString *operation;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
