#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// MVAU wire format: 8-byte header + raw signed little-endian PCM samples.
/// Header layout:
///   Bytes 0-1: Magic 0x4D 0x56 ("MV")
///   Bytes 2-5: Sample rate, uint32 little-endian
///   Byte    6: Channel count, uint8
///   Byte    7: Bit depth, uint8 (8, 16, 24, or 32)

extern const uint8_t MVAudioMagic[2];  // { 0x4D, 0x56 }

typedef struct {
    uint32_t sampleRate;
    uint8_t  channels;
    uint8_t  bitDepth;
} MVAudioFormat;

/// Returns YES if the first 2 bytes of data match the MVAU magic bytes.
BOOL MVAudioIsMVAU(NSData *data);

// ─────────────────────────────────────────────────────────────────────────────
// MVAudioWriter — writes MVAU stream to a file descriptor.
// ─────────────────────────────────────────────────────────────────────────────

@interface MVAudioWriter : NSObject

- (instancetype)initWithFileDescriptor:(int)fd format:(MVAudioFormat)fmt;

/// Write the 8-byte MVAU header. Call once before any writeSamples: calls.
- (void)writeHeader;

/// Write raw PCM sample bytes.
- (void)writeSamples:(NSData *)pcmData;

@end

// ─────────────────────────────────────────────────────────────────────────────
// MVAudioReader — reads MVAU or raw PCM from a file descriptor.
// ─────────────────────────────────────────────────────────────────────────────

@interface MVAudioReader : NSObject

/// fd is typically STDIN_FILENO.
/// If the stream starts with MVAU magic, the header is parsed automatically.
/// If not, fallbackFormat is used and the stream is treated as raw PCM.
- (instancetype)initWithFileDescriptor:(int)fd
                         fallbackFormat:(MVAudioFormat)fallbackFormat;

/// The format detected from the header (or fallbackFormat if raw PCM).
@property (nonatomic, readonly) MVAudioFormat format;

/// YES if the stream had an MVAU header; NO if using fallback format.
@property (nonatomic, readonly) BOOL hasMVAUHeader;

/// Blocking read. Calls handler repeatedly with chunks of raw PCM data until EOF.
/// chunkSize is the preferred read size in bytes (e.g. 4096 or one second of audio).
- (void)readChunksOfSize:(NSUInteger)chunkSize
                 handler:(void (^)(NSData *pcmChunk))handler;

/// Read all audio data at once (for short clips like shazam matching).
- (nullable NSData *)readAllData:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
