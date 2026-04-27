#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ShazamProcessor : NSObject

/// Audio file path, or a directory for `build` only.
@property (nonatomic, copy, nullable) NSString *inputPath;
/// JSON envelope output path, or stdout when omitted.
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// Directory for catalog output (`build`), or catalog file for `match-custom`.
@property (nonatomic, copy, nullable) NSString *artifactsDir;
/// Operation: match | match-custom | build
@property (nonatomic, copy) NSString *operation;
/// Path to a .shazamcatalog file for match-custom.
@property (nonatomic, copy, nullable) NSString *catalog;
@property (nonatomic, assign) BOOL debug;
/// Read MVAU or raw PCM audio from stdin and match (auto-detected when stdin is piped).
@property (nonatomic, assign) BOOL streamIn;
/// Sample rate for raw PCM fallback (default: 16000).
@property (nonatomic, assign) uint32_t sampleRate;
/// Channel count for raw PCM fallback (default: 1).
@property (nonatomic, assign) uint8_t  channels;
/// Bit depth for raw PCM fallback (default: 16).
@property (nonatomic, assign) uint8_t  bitDepth;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchShazam(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
