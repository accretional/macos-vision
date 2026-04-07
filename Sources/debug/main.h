#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DebugProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *img;
@property (nonatomic, copy, nullable) NSString *output;
@property (nonatomic, copy, nullable) NSString *imgDir;
@property (nonatomic, copy, nullable) NSString *outputDir;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
