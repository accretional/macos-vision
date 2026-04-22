#import "common/MVMjpegStream.h"
#include <unistd.h>
#include <string.h>

NSString * const MVMjpegBoundary = @"mvboundary";

// ── Internal byte-pattern search ──────────────────────────────────────────────

/// Returns the range of `needle` in `haystack` starting at `from`, or {NSNotFound,0}.
static NSRange MVFindData(NSData *haystack, NSData *needle, NSUInteger from) {
    NSUInteger hlen = haystack.length;
    NSUInteger nlen = needle.length;
    if (nlen == 0 || hlen < nlen + from) return NSMakeRange(NSNotFound, 0);
    const uint8_t *h = (const uint8_t *)haystack.bytes;
    const uint8_t *n = (const uint8_t *)needle.bytes;
    for (NSUInteger i = from; i + nlen <= hlen; i++) {
        if (memcmp(h + i, n, nlen) == 0) return NSMakeRange(i, nlen);
    }
    return NSMakeRange(NSNotFound, 0);
}

static NSData *MVBoundaryLine(void) {
    static NSData *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [@"--mvboundary\r\n" dataUsingEncoding:NSUTF8StringEncoding]; });
    return d;
}

static NSData *MVBoundaryTerminator(void) {
    static NSData *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [@"--mvboundary--\r\n" dataUsingEncoding:NSUTF8StringEncoding]; });
    return d;
}

static NSData *MVHeaderSeparator(void) {
    static NSData *d;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ d = [@"\r\n\r\n" dataUsingEncoding:NSUTF8StringEncoding]; });
    return d;
}

// ─────────────────────────────────────────────────────────────────────────────
// MVMjpegWriter
// ─────────────────────────────────────────────────────────────────────────────

@implementation MVMjpegWriter {
    int     _fd;
    NSLock *_lock;
}

- (instancetype)initWithFileDescriptor:(int)fd {
    if ((self = [super init])) {
        _fd   = fd;
        _lock = [[NSLock alloc] init];
    }
    return self;
}

- (void)writeFrame:(NSData *)jpeg
      extraHeaders:(NSDictionary<NSString *, NSString *> *)extraHeaders {
    NSMutableString *hdr = [NSMutableString stringWithCapacity:256];
    [hdr appendString:@"--mvboundary\r\n"];
    [hdr appendString:@"Content-Type: image/jpeg\r\n"];
    [hdr appendFormat:@"Content-Length: %lu\r\n", (unsigned long)jpeg.length];
    for (NSString *key in extraHeaders) {
        [hdr appendFormat:@"%@: %@\r\n", key, extraHeaders[key]];
    }
    [hdr appendString:@"\r\n"];

    NSData *hdrData = [hdr dataUsingEncoding:NSUTF8StringEncoding];
    [_lock lock];
    write(_fd, hdrData.bytes, hdrData.length);
    write(_fd, jpeg.bytes,    jpeg.length);
    [_lock unlock];
}

@end

// ─────────────────────────────────────────────────────────────────────────────
// MVMjpegReader
// ─────────────────────────────────────────────────────────────────────────────

@implementation MVMjpegReader {
    int _fd;
}

- (instancetype)initWithFileDescriptor:(int)fd {
    if ((self = [super init])) { _fd = fd; }
    return self;
}

- (void)readFramesWithHandler:(MVMjpegFrameHandler)handler {
    NSMutableData *buf     = [NSMutableData dataWithCapacity:256 * 1024];
    uint8_t        chunk[65536];

    for (;;) {
        // ── find the start boundary ────────────────────────────────────────
        NSRange bRange = MVFindData(buf, MVBoundaryLine(), 0);

        if (bRange.location == NSNotFound) {
            // Check for terminal boundary before reading more
            if (MVFindData(buf, MVBoundaryTerminator(), 0).location != NSNotFound) break;

            ssize_t n = read(_fd, chunk, sizeof(chunk));
            if (n <= 0) break;
            [buf appendBytes:chunk length:(NSUInteger)n];
            continue;
        }

        // ── find end of headers ────────────────────────────────────────────
        NSUInteger hdrsStart = bRange.location + bRange.length;
        NSRange    sepRange  = MVFindData(buf, MVHeaderSeparator(), hdrsStart);

        if (sepRange.location == NSNotFound) {
            ssize_t n = read(_fd, chunk, sizeof(chunk));
            if (n <= 0) break;
            [buf appendBytes:chunk length:(NSUInteger)n];
            continue;
        }

        // ── parse headers ──────────────────────────────────────────────────
        NSData   *hdrData = [buf subdataWithRange:NSMakeRange(hdrsStart, sepRange.location - hdrsStart)];
        NSString *hdrStr  = [[NSString alloc] initWithData:hdrData encoding:NSUTF8StringEncoding] ?: @"";

        NSMutableDictionary<NSString *, NSString *> *headers = [NSMutableDictionary dictionary];
        NSInteger contentLength = -1;

        for (NSString *line in [hdrStr componentsSeparatedByString:@"\r\n"]) {
            NSRange colon = [line rangeOfString:@":"];
            if (colon.location == NSNotFound) continue;
            NSString *key = [[line substringToIndex:colon.location]
                             stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            NSString *val = [[line substringFromIndex:colon.location + 1]
                             stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
            headers[key] = val;
            if ([key caseInsensitiveCompare:@"Content-Length"] == NSOrderedSame)
                contentLength = val.integerValue;
        }

        if (contentLength < 0) {
            // Malformed frame — skip past this boundary and try again
            [buf replaceBytesInRange:NSMakeRange(0, sepRange.location + sepRange.length)
                           withBytes:NULL length:0];
            continue;
        }

        // ── wait for enough JPEG bytes ─────────────────────────────────────
        NSUInteger jpegStart = sepRange.location + sepRange.length;
        NSUInteger jpegEnd   = jpegStart + (NSUInteger)contentLength;

        while (buf.length < jpegEnd) {
            ssize_t n = read(_fd, chunk, sizeof(chunk));
            if (n <= 0) return; // EOF mid-frame
            [buf appendBytes:chunk length:(NSUInteger)n];
        }

        // ── deliver frame ──────────────────────────────────────────────────
        NSData *jpeg = [buf subdataWithRange:NSMakeRange(jpegStart, (NSUInteger)contentLength)];
        handler(jpeg, headers);

        // Consume processed bytes
        [buf replaceBytesInRange:NSMakeRange(0, jpegEnd) withBytes:NULL length:0];
    }
}

@end
