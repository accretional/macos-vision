#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SNAProcessor : NSObject

/// Audio file path (required for classify and detect; omit for list-labels).
@property (nonatomic, copy, nullable) NSString *inputPath;
/// JSON envelope output path, or stdout when omitted.
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// Operation: classify | detect | list-labels
@property (nonatomic, copy) NSString *operation;
/// Top-K results per classification window (default 5).
@property (nonatomic, assign) NSInteger topk;
/// Override analysis window duration in seconds (macOS 12+; 0 = use model default).
@property (nonatomic, assign) NSTimeInterval windowDuration;
@property (nonatomic, assign) BOOL windowDurationSet;
/// Overlap factor between consecutive analysis windows, [0.0, 1.0) (default: model default).
@property (nonatomic, assign) double overlapFactor;
@property (nonatomic, assign) BOOL overlapFactorSet;
@property (nonatomic, assign) BOOL debug;
/// Read MVAU or raw PCM audio from stdin and classify (auto-detected when stdin is piped).
@property (nonatomic, assign) BOOL streamIn;
/// Sample rate for raw PCM fallback (default: 16000).
@property (nonatomic, assign) uint32_t sampleRate;
/// Channel count for raw PCM fallback (default: 1).
@property (nonatomic, assign) uint8_t  channels;
/// Bit depth for raw PCM fallback (default: 16).
@property (nonatomic, assign) uint8_t  bitDepth;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchSNA(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
