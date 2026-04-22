#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Operations: screenshot | photo | mic | video | screen-record | barcode | list-devices
@interface CaptureProcessor : NSObject

@property (nonatomic, copy) NSString *operation;
/// Explicit output file path for captured media.
@property (nonatomic, copy, nullable) NSString *mediaOutput;
/// Directory used when mediaOutput is not set.
@property (nonatomic, copy, nullable) NSString *artifactsDir;
/// JSON envelope output path, or stdout when omitted.
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// Display index for screenshot / screen-record (default: 0).
@property (nonatomic, assign) NSInteger displayIndex;
/// Camera or microphone device index for photo / video / mic / barcode (default: 0).
@property (nonatomic, assign) NSInteger deviceIndex;
/// Maximum recording duration in seconds; 0 = run until SIGINT (video, mic, screen-record).
@property (nonatomic, assign) NSTimeInterval duration;
/// Output container format for video / screen-record: mp4 (default), mov.
@property (nonatomic, copy) NSString *format;
/// Skip microphone input when recording video (default: NO — audio is included).
@property (nonatomic, assign) BOOL noAudio;
/// Comma-separated barcode type names to scan for (default: all supported types).
/// Recognised names: qr, ean13, ean8, upce, code128, code39, code93, pdf417, aztec, datamatrix, itf14, i2of5
@property (nonatomic, copy, nullable) NSString *types;
/// Show a live preview window before capture (photo, video, screen-record).
@property (nonatomic, assign) BOOL preview;
@property (nonatomic, assign) BOOL debug;
/// Stream frames as MJPEG (video) or MVAU (audio) to stdout.
/// Auto-detected when stdout is piped; set by dispatch.m.
@property (nonatomic, assign) BOOL stream;
/// Target frames per second for MJPEG video stream (default: 30).
@property (nonatomic, assign) NSInteger fps;
/// JPEG quality for MJPEG stream (default: 0.85).
@property (nonatomic, assign) double jpegQuality;
/// Audio sample rate for MVAU audio stream (default: 16000).
@property (nonatomic, assign) uint32_t audioSampleRate;
/// Audio channel count for MVAU audio stream (default: 1).
@property (nonatomic, assign) uint8_t audioChannels;
/// Audio bit depth for MVAU audio stream (default: 16).
@property (nonatomic, assign) uint8_t audioBitDepth;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchStreamCapture(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
