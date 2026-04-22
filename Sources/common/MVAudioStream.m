#import "common/MVAudioStream.h"
#include <unistd.h>
#include <string.h>

// ── Magic bytes ───────────────────────────────────────────────────────────────

const uint8_t MVAudioMagic[2] = { 0x4D, 0x56 };

BOOL MVAudioIsMVAU(NSData *data) {
    if (data.length < 2) return NO;
    const uint8_t *bytes = (const uint8_t *)data.bytes;
    return bytes[0] == MVAudioMagic[0] && bytes[1] == MVAudioMagic[1];
}

// ─────────────────────────────────────────────────────────────────────────────
// MVAudioWriter
// ─────────────────────────────────────────────────────────────────────────────

@implementation MVAudioWriter {
    int           _fd;
    MVAudioFormat _fmt;
}

- (instancetype)initWithFileDescriptor:(int)fd format:(MVAudioFormat)fmt {
    if ((self = [super init])) {
        _fd  = fd;
        _fmt = fmt;
    }
    return self;
}

- (void)writeHeader {
    // 8-byte MVAU header:
    //   [0-1]: Magic "MV" (0x4D 0x56)
    //   [2-5]: Sample rate, uint32 little-endian
    //   [6]:   Channel count, uint8
    //   [7]:   Bit depth, uint8
    uint8_t header[8];
    header[0] = MVAudioMagic[0];
    header[1] = MVAudioMagic[1];
    // Sample rate in little-endian
    uint32_t sr = _fmt.sampleRate;
    header[2] = (uint8_t)(sr & 0xFF);
    header[3] = (uint8_t)((sr >> 8) & 0xFF);
    header[4] = (uint8_t)((sr >> 16) & 0xFF);
    header[5] = (uint8_t)((sr >> 24) & 0xFF);
    header[6] = _fmt.channels;
    header[7] = _fmt.bitDepth;
    write(_fd, header, 8);
}

- (void)writeSamples:(NSData *)pcmData {
    if (!pcmData.length) return;
    write(_fd, pcmData.bytes, pcmData.length);
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// MVAudioReader
// ─────────────────────────────────────────────────────────────────────────────

@implementation MVAudioReader {
    int           _fd;
    MVAudioFormat _format;
    BOOL          _hasMVAUHeader;
    // Buffered bytes read during header detection that are raw PCM (no header case)
    NSMutableData *_prefetchedData;
}

@synthesize format = _format;
@synthesize hasMVAUHeader = _hasMVAUHeader;

- (instancetype)initWithFileDescriptor:(int)fd fallbackFormat:(MVAudioFormat)fallbackFormat {
    if ((self = [super init])) {
        _fd             = fd;
        _format         = fallbackFormat;
        _hasMVAUHeader  = NO;
        _prefetchedData = [NSMutableData data];

        // Read first 8 bytes to check for MVAU header
        uint8_t header[8];
        ssize_t n = read(fd, header, 8);
        if (n < 2) {
            // Very short or empty stream — treat as raw PCM
            if (n > 0) [_prefetchedData appendBytes:header length:(NSUInteger)n];
            return self;
        }

        if (header[0] == MVAudioMagic[0] && header[1] == MVAudioMagic[1] && n >= 8) {
            // Parse MVAU header
            _hasMVAUHeader = YES;
            uint32_t sr = (uint32_t)header[2]
                        | ((uint32_t)header[3] << 8)
                        | ((uint32_t)header[4] << 16)
                        | ((uint32_t)header[5] << 24);
            _format.sampleRate = sr;
            _format.channels   = header[6];
            _format.bitDepth   = header[7];
            // No prefetched data — the 8 bytes were the header
        } else {
            // Not MVAU — treat all read bytes as PCM data, put them in prefetch buffer
            [_prefetchedData appendBytes:header length:(NSUInteger)n];
        }
    }
    return self;
}

- (void)readChunksOfSize:(NSUInteger)chunkSize handler:(void (^)(NSData *pcmChunk))handler {
    // Deliver any prefetched data first
    if (_prefetchedData.length > 0) {
        handler([_prefetchedData copy]);
        _prefetchedData = [NSMutableData data];
    }

    uint8_t *buf = (uint8_t *)malloc(chunkSize);
    if (!buf) return;

    for (;;) {
        ssize_t n = read(_fd, buf, chunkSize);
        if (n <= 0) break;
        NSData *chunk = [NSData dataWithBytes:buf length:(NSUInteger)n];
        handler(chunk);
    }
    free(buf);
}

- (nullable NSData *)readAllData:(NSError **)error {
    NSMutableData *all = [NSMutableData data];

    // Include any prefetched data
    if (_prefetchedData.length > 0) {
        [all appendData:_prefetchedData];
        _prefetchedData = [NSMutableData data];
    }

    uint8_t buf[65536];
    for (;;) {
        ssize_t n = read(_fd, buf, sizeof(buf));
        if (n < 0) {
            if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
                                   userInfo:@{NSLocalizedDescriptionKey: @"Error reading audio data from stdin"}];
            return nil;
        }
        if (n == 0) break;
        [all appendBytes:buf length:(NSUInteger)n];
    }

    return all;
}

@end
