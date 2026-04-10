#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioProcessor : NSObject

// Input
@property (nonatomic, copy, nullable) NSString *audio;
@property (nonatomic, copy, nullable) NSString *audioDir;
// Operation: transcribe | classify | shazam | detect | noise | pitch | isolate | shazam-custom | shazam-build
@property (nonatomic, copy) NSString *operation;
// Output
@property (nonatomic, copy, nullable) NSString *output;
@property (nonatomic, copy, nullable) NSString *outputDir;
// Options
@property (nonatomic, copy) NSString *lang;         // e.g. en-US (default)
@property (nonatomic, assign) BOOL offline;          // force on-device recognition
@property (nonatomic, assign) NSInteger topk;        // top-K results for classify (default 3)
@property (nonatomic, assign) BOOL merge;            // merge directory results into one JSON
@property (nonatomic, assign) BOOL debug;            // emit processing_ms in output
// shazam-custom: path to a .shazamcatalog file built with shazam-build
@property (nonatomic, copy, nullable) NSString *catalog;
// Streaming modes
@property (nonatomic, assign) BOOL mic;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
