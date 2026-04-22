#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// The MJPEG multipart boundary used by all macos-vision streaming stages.
extern NSString * const MVMjpegBoundary;

/// Invoked once per frame. `jpeg` is the raw JPEG bytes (never nil).
/// `headers` contains all MIME headers from the frame, including any X-MV-* headers
/// added by prior pipeline stages.
typedef void (^MVMjpegFrameHandler)(NSData *jpeg, NSDictionary<NSString *, NSString *> *headers);

// ─────────────────────────────────────────────────────────────────────────────
// MVMjpegWriter — writes MJPEG multipart frames to a file descriptor.
// Thread-safe: concurrent -writeFrame:extraHeaders: calls are serialized.
// ─────────────────────────────────────────────────────────────────────────────

@interface MVMjpegWriter : NSObject

/// fd is typically STDOUT_FILENO (1).
- (instancetype)initWithFileDescriptor:(int)fd;

/// Write one JPEG frame. Content-Type and Content-Length are added automatically.
/// Pass any X-MV-* or other headers in extraHeaders (nil or empty is fine).
- (void)writeFrame:(NSData *)jpeg
      extraHeaders:(nullable NSDictionary<NSString *, NSString *> *)extraHeaders;

@end

// ─────────────────────────────────────────────────────────────────────────────
// MVMjpegReader — reads MJPEG frames from a file descriptor, blocking.
// ─────────────────────────────────────────────────────────────────────────────

@interface MVMjpegReader : NSObject

/// fd is typically STDIN_FILENO (0).
- (instancetype)initWithFileDescriptor:(int)fd;

/// Blocking read loop. Calls handler synchronously for each complete frame.
/// Returns when EOF or a read error is encountered.
- (void)readFramesWithHandler:(MVMjpegFrameHandler)handler;

@end

NS_ASSUME_NONNULL_END
