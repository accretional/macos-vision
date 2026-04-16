#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TrackProcessor : NSObject

/// Video file path, or a directory of ordered image frames (for sequence mode).
@property (nonatomic, copy, nullable) NSString *inputPath;
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// Required for optical-flow when saving flow PNG frames; otherwise ignored.
@property (nonatomic, copy, nullable) NSString *artifactsDir;
// homographic (default) | translational | optical-flow | trajectories
@property (nonatomic, copy) NSString *operation;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
