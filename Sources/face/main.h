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
// Supports comma-separated values (e.g. "face-rectangles,face-landmarks")
@property (nonatomic, copy) NSString *operation;
/// Read MJPEG from stdin (S→S / S→F). Active when stdin piped and no --input given.
@property (nonatomic, assign) BOOL stream;
/// Write MJPEG to stdout (F→S / S→S). Active when stdout piped.
@property (nonatomic, assign) BOOL streamOut;
/// When set in stream mode, dual-write NDJSON lines to this file alongside MJPEG stdout.
@property (nonatomic, copy, nullable) NSString *ndjsonOutput;
/// Max queued frames before dropping (stream mode). Default 1, 0 = no dropping.
@property (nonatomic, assign) NSInteger maxLag;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchFace(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
