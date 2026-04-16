#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Operations: screenshot | camera | mic | list-devices
@interface CaptureProcessor : NSObject

@property (nonatomic, copy) NSString *operation;
/// Optional explicit path for captured media (PNG, JPG, M4A).
@property (nonatomic, copy, nullable) NSString *mediaOutput;
/// Directory used when `mediaOutput` is not set (default: current working directory).
@property (nonatomic, copy, nullable) NSString *artifactsDir;
/// JSON envelope path, or stdout when omitted.
@property (nonatomic, copy, nullable) NSString *jsonOutput;
@property (nonatomic, assign) NSInteger displayIndex;
@property (nonatomic, assign) BOOL debug;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
