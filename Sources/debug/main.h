#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DebugProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *inputPath;
@property (nonatomic, copy, nullable) NSString *jsonOutput;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
