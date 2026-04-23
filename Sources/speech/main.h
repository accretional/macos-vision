#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SpeechProcessor : NSObject

/// Audio file path (required for transcribe and voice-analytics, or use streamIn).
@property (nonatomic, copy, nullable) NSString *inputPath;
/// JSON envelope output path, or stdout when omitted.
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// Operation: transcribe | voice-analytics | list-locales
@property (nonatomic, copy) NSString *operation;
@property (nonatomic, copy) NSString *lang;
@property (nonatomic, assign) BOOL offline;
@property (nonatomic, assign) BOOL debug;
/// Read raw PCM/MVAU audio from stdin and transcribe (auto-detected when stdin is piped).
@property (nonatomic, assign) BOOL streamIn;
/// Sample rate for raw PCM fallback when no MVAU header detected (default: 16000).
@property (nonatomic, assign) uint32_t sampleRate;
/// Channel count for raw PCM fallback (default: 1).
@property (nonatomic, assign) uint8_t  channels;
/// Bit depth for raw PCM fallback (default: 16).
@property (nonatomic, assign) uint8_t  bitDepth;
/// Force raw PCM mode, ignoring any MVAU header (default: NO).
@property (nonatomic, assign) BOOL     noHeader;
/// Set by dispatch when the binary is relaunched via `open` (launchd context).
@property (nonatomic, assign) BOOL     appContext;
/// Named pipe path the child reads audio from (stream-input mode).
@property (nonatomic, copy, nullable) NSString *audioPipe;
/// Named pipe path the child writes JSON result lines to.
@property (nonatomic, copy, nullable) NSString *resultPipe;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchSpeech(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
