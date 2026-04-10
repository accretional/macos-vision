#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *video;
@property (nonatomic, copy, nullable) NSString *img;
@property (nonatomic, copy) NSString *operation;
@property (nonatomic, copy, nullable) NSString *output;
@property (nonatomic, copy, nullable) NSString *outputDir;
@property (nonatomic, copy, nullable) NSString *preset;
@property (nonatomic, copy, nullable) NSString *timeStr;
@property (nonatomic, copy, nullable) NSString *timesStr;
@property (nonatomic, copy, nullable) NSString *timeRangeStr;
@property (nonatomic, copy, nullable) NSString *metaKey;
@property (nonatomic, assign) BOOL debug;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
