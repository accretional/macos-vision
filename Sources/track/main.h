#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TrackProcessor : NSObject

/// Video file path, or a directory of ordered image frames (for sequence mode).
@property (nonatomic, copy, nullable) NSString *inputPath;
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// Directory for optical-flow PNG frames. Falls back to the current working directory when unset.
@property (nonatomic, copy, nullable) NSString *artifactsDir;
// homographic (default) | translational | optical-flow | trajectories
@property (nonatomic, copy) NSString *operation;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchTrack(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
