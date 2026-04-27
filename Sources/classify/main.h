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
/// Read MJPEG from stdin (S→S / S→F). Active when stdin piped and no --input given.
@property (nonatomic, assign) BOOL stream;
/// Write MJPEG to stdout (F→S / S→S). Active when stdout piped.
@property (nonatomic, assign) BOOL streamOut;
/// When set in stream mode, dual-write NDJSON lines to this file alongside MJPEG stdout.
@property (nonatomic, copy, nullable) NSString *ndjsonOutput;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchClassify(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
