#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface TrackProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *video;    // path to a video file
@property (nonatomic, copy, nullable) NSString *imgDir;   // directory of image frames (sorted)
@property (nonatomic, copy, nullable) NSString *output;   // output directory
@property (nonatomic, copy, nullable) NSString *outputDir;
// homographic (default) | translational | optical-flow | trajectories
@property (nonatomic, copy) NSString *operation;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
