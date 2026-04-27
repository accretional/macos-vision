#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCRProcessor : NSObject

/// Image file path (required unless --lang).
@property (nonatomic, copy, nullable) NSString *inputPath;
/// If set, write JSON envelope to this file; otherwise print JSON to stdout.
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// If set with --debug, write overlay image under this directory.
@property (nonatomic, copy, nullable) NSString *artifactsDir;
@property (nonatomic, assign) BOOL debug;
@property (nonatomic, assign) BOOL lang;
@property (nonatomic, copy, nullable) NSString *recLangs;
@property (nonatomic, copy) NSString *boxesFormat; // png | jpg | tiff | bmp | gif  (default: png)
/// Read MJPEG from stdin (S→S / S→F). Active when stdin piped and no --input given.
@property (nonatomic, assign) BOOL stream;
/// Write MJPEG to stdout (F→S / S→S). Active when stdout piped.
@property (nonatomic, assign) BOOL streamOut;
/// When set in stream mode, dual-write NDJSON lines to this file alongside MJPEG stdout.
@property (nonatomic, copy, nullable) NSString *ndjsonOutput;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchOCR(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
