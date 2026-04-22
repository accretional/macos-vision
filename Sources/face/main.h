#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FaceProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *inputPath;
@property (nonatomic, copy, nullable) NSString *jsonOutput;
@property (nonatomic, copy, nullable) NSString *artifactsDir;
@property (nonatomic, assign) BOOL debug;
@property (nonatomic, copy) NSString *boxesFormat;
// face-rectangles (default) | face-landmarks | face-quality |
// human-rectangles | body-pose | hand-pose | animal-pose
@property (nonatomic, copy) NSString *operation;
/// Read MJPEG from stdin, add X-MV-face-<op> header per frame, write MJPEG to stdout.
@property (nonatomic, assign) BOOL stream;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchFace(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
