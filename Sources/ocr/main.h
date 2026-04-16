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

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
