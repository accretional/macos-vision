#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ClassifyProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *inputPath;
@property (nonatomic, copy, nullable) NSString *jsonOutput;
@property (nonatomic, copy, nullable) NSString *artifactsDir;
@property (nonatomic, assign) BOOL debug;
@property (nonatomic, copy) NSString *boxesFormat;
// classify (default) | animals | rectangles | horizon | contours | aesthetics | feature-print
@property (nonatomic, copy) NSString *operation;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
