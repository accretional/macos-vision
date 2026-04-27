#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DebugProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *inputPath;
@property (nonatomic, copy, nullable) NSString *jsonOutput;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchDebug(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
