#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AudioProcessor : NSObject

/// Audio file path, or a directory for `shazam-build` only.
@property (nonatomic, copy, nullable) NSString *inputPath;
/// JSON envelope output path, or stdout when omitted.
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// Directory for `isolate` output audio, optional Shazam catalog parent, etc.
@property (nonatomic, copy, nullable) NSString *artifactsDir;
// Operation: transcribe | classify | shazam | detect | noise | pitch | isolate | shazam-custom | shazam-build
@property (nonatomic, copy) NSString *operation;
@property (nonatomic, copy) NSString *lang;
@property (nonatomic, assign) BOOL offline;
@property (nonatomic, assign) NSInteger topk;
@property (nonatomic, assign) BOOL classifyWindowDurationSet;
@property (nonatomic, assign) NSTimeInterval classifyWindowDuration;
@property (nonatomic, assign) BOOL classifyOverlapFactorSet;
@property (nonatomic, assign) double classifyOverlapFactor;
@property (nonatomic, assign) NSInteger pitchHopFrames;
@property (nonatomic, assign) BOOL debug;
@property (nonatomic, copy, nullable) NSString *catalog;
@property (nonatomic, assign) BOOL mic;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
