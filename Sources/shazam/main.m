#import "main.h"
#import "common/MVJsonEmit.h"
#import "common/MVAudioStream.h"
#import <ShazamKit/ShazamKit.h>
#import <AVFoundation/AVFoundation.h>

static NSString * const ShazamErrorDomain = @"ShazamProcessorError";

// ── ShazamKit session delegate ────────────────────────────────────────────────

API_AVAILABLE(macos(12.0))
@interface SHAZDelegate : NSObject <SHSessionDelegate>
@property (nonatomic, strong) NSDictionary *result;
@property (nonatomic, strong) NSError      *matchError;
@property (nonatomic)         dispatch_semaphore_t semaphore;
- (instancetype)initWithSemaphore:(dispatch_semaphore_t)sem;
@end

API_AVAILABLE(macos(12.0))
@implementation SHAZDelegate

- (instancetype)initWithSemaphore:(dispatch_semaphore_t)sem {
    if (self = [super init]) {
        _semaphore = sem;
        _result    = @{@"matched": @NO};
    }
    return self;
}

- (void)session:(SHSession *)session didFindMatch:(SHMatch *)match {
    SHMatchedMediaItem *item = match.mediaItems.firstObject;
    if (item) {
        self.result = @{
            @"matched":      @YES,
            @"title":        item.title        ?: @"",
            @"artist":       item.artist       ?: @"",
            @"subtitle":     item.subtitle     ?: @"",
            @"appleMusicID": item.appleMusicID ?: @"",
            @"isrc":         item.isrc         ?: @"",
            @"genres":       item.genres       ?: @[]
        };
    }
    dispatch_semaphore_signal(self.semaphore);
}

- (void)session:(SHSession *)session didNotFindMatchForSignature:(SHSignature *)signature error:(NSError *)error {
    if (error) self.matchError = error;
    dispatch_semaphore_signal(self.semaphore);
}

@end

// ── ShazamProcessor ───────────────────────────────────────────────────────────

@implementation ShazamProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation  = @"match";
        _sampleRate = 16000;
        _channels   = 1;
        _bitDepth   = 16;
    }
    return self;
}

- (BOOL)runWithError:(NSError **)error {
    // Stream-in mode: read audio from stdin
    if (self.streamIn) return [self runAudioStreamWithError:error];

    NSArray *validOps = @[@"match", @"match-custom", @"build"];
    if (![validOps containsObject:self.operation]) {
        if (error) {
            *error = [NSError errorWithDomain:ShazamErrorDomain code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Unknown operation '%@'. Valid: %@",
                                                     self.operation, [validOps componentsJoinedByString:@", "]]}];
        }
        return NO;
    }

    if (!self.inputPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:ShazamErrorDomain code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Provide --input <audio_file> (or directory for build)"}];
        }
        return NO;
    }

    NSURL *inputURL = [NSURL fileURLWithPath:self.inputPath];
    NSDate *start = self.debug ? [NSDate date] : nil;

    NSDictionary *result = nil;
    if ([self.operation isEqualToString:@"match"]) {
        result = [self matchURL:inputURL error:error];
    } else if ([self.operation isEqualToString:@"match-custom"]) {
        result = [self matchCustomURL:inputURL error:error];
    } else if ([self.operation isEqualToString:@"build"]) {
        result = [self buildCatalogFromURL:inputURL error:error];
    }
    if (!result) return NO;

    NSMutableDictionary *envelope_result = [result mutableCopy];
    if (self.debug && start) {
        envelope_result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    NSArray<NSDictionary *> *artifactEntries = [self artifactEntriesForResult:envelope_result];
    NSDictionary *merged = MVResultByMergingArtifacts(envelope_result, artifactEntries);
    NSDictionary *envelope = MVMakeEnvelope(@"shazam", self.operation, self.inputPath, merged);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

- (NSArray<NSDictionary *> *)artifactEntriesForResult:(NSDictionary *)result {
    NSMutableArray *a = [NSMutableArray array];
    NSString *cat = result[@"catalog"];
    if ([cat isKindOfClass:[NSString class]] && cat.length)
        [a addObject:MVArtifactEntry(cat, @"shazam_catalog")];
    return a;
}

// ── match (SHSession against default Shazam catalog, macOS 12+) ──────────────

- (nullable NSDictionary *)matchURL:(NSURL *)url error:(NSError **)error {
    if (@available(macOS 12.0, *)) {
        SHSignature *sig = [self generateSignatureFromURL:url error:error];
        if (!sig) return nil;

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        SHAZDelegate *delegate = [[SHAZDelegate alloc] initWithSemaphore:sem];
        SHSession *session = [[SHSession alloc] init];
        session.delegate = delegate;
        [session matchSignature:sig];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        (void)session; // keep session alive until semaphore returns; ARC would otherwise
                       // release it after matchSignature:, cancelling the pending match
        if (delegate.matchError) {
            NSError *e = delegate.matchError;
            if ([e.domain isEqualToString:@"com.apple.ShazamKit"] && e.code == 201) {
                e = [NSError errorWithDomain:e.domain code:e.code userInfo:@{
                    NSLocalizedDescriptionKey:
                        @"ShazamKit cloud matching requires the com.apple.developer.shazamkit "
                        @"entitlement signed with a real Apple Developer identity and provisioning "
                        @"profile. Ad-hoc signing is not sufficient. Use 'match-custom' with a "
                        @"local .shazamcatalog for offline matching without entitlements."
                }];
            }
            if (error) *error = e;
            return nil;
        }
        return delegate.result;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:ShazamErrorDomain code:10
                                     userInfo:@{NSLocalizedDescriptionKey: @"ShazamKit requires macOS 12.0+"}];
        }
        return nil;
    }
}

// ── match-custom (against a custom .shazamcatalog, macOS 12+) ────────────────

- (nullable NSDictionary *)matchCustomURL:(NSURL *)url error:(NSError **)error {
    if (@available(macOS 12.0, *)) {
        SHSignature *sig = [self generateSignatureFromURL:url error:error];
        if (!sig) return nil;

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        SHAZDelegate *delegate = [[SHAZDelegate alloc] initWithSemaphore:sem];
        SHSession *session;

        if (self.catalog.length) {
            SHCustomCatalog *catalog = [[SHCustomCatalog alloc] init];
            if (![catalog addCustomCatalogFromURL:[NSURL fileURLWithPath:self.catalog] error:error]) {
                return nil;
            }
            session = [[SHSession alloc] initWithCatalog:catalog];
        } else {
            session = [[SHSession alloc] init];
        }

        session.delegate = delegate;
        [session matchSignature:sig];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
        (void)session;
        if (delegate.matchError) {
            if (error) *error = delegate.matchError;
            return nil;
        }
        NSMutableDictionary *result = [delegate.result mutableCopy];
        if (self.catalog.length) {
            result[@"catalog"] = MVRelativePath(self.catalog);
        } else {
            result[@"note"] = @"No --catalog provided; matched against default Shazam catalog";
        }
        return result;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:ShazamErrorDomain code:11
                                     userInfo:@{NSLocalizedDescriptionKey: @"ShazamKit requires macOS 12.0+"}];
        }
        return nil;
    }
}

// ── build (SHCustomCatalog from directory of audio files, macOS 12+) ─────────

- (nullable NSDictionary *)buildCatalogFromURL:(NSURL *)url error:(NSError **)error {
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir] || !isDir) {
        if (error) {
            *error = [NSError errorWithDomain:ShazamErrorDomain code:20
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"build requires a directory path (--input)"}];
        }
        return nil;
    }

    NSArray<NSURL *> *files = [self listAudioFilesInDirectory:url.path error:error];
    if (!files) return nil;

    if (@available(macOS 12.0, *)) {
        SHCustomCatalog *catalog = [[SHCustomCatalog alloc] init];
        NSMutableArray<NSString *>     *indexed = [NSMutableArray array];
        NSMutableArray<NSDictionary *> *failed  = [NSMutableArray array];

        for (NSURL *fileURL in files) {
            NSError *sigErr = nil;
            SHSignature *sig = [self generateSignatureFromURL:fileURL error:&sigErr];
            if (!sig) {
                [failed addObject:@{
                    @"file":  fileURL.lastPathComponent,
                    @"error": sigErr.localizedDescription ?: @"failed to generate signature"
                }];
                continue;
            }
            NSString *title = [fileURL.lastPathComponent stringByDeletingPathExtension];
            SHMediaItem *item = [SHMediaItem mediaItemWithProperties:@{ SHMediaItemTitle: title }];
            NSError *addErr = nil;
            if (![catalog addReferenceSignature:sig representingMediaItems:@[item] error:&addErr]) {
                [failed addObject:@{
                    @"file":  fileURL.lastPathComponent,
                    @"error": addErr.localizedDescription ?: @"failed to add signature"
                }];
            } else {
                [indexed addObject:title];
            }
        }

        NSURL *catalogURL;
        if (self.artifactsDir.length) {
            NSString *name = [url.lastPathComponent stringByAppendingPathExtension:@"shazamcatalog"];
            catalogURL = [[NSURL fileURLWithPath:self.artifactsDir] URLByAppendingPathComponent:name];
        } else {
            NSString *name = [url.lastPathComponent stringByAppendingPathExtension:@"shazamcatalog"];
            catalogURL = [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:name];
        }
        [[NSFileManager defaultManager] createDirectoryAtURL:catalogURL.URLByDeletingLastPathComponent
                                 withIntermediateDirectories:YES attributes:nil error:nil];
        if (![catalog writeToURL:catalogURL error:error]) return nil;

        NSMutableDictionary *result = [@{
            @"catalog": MVRelativePath(catalogURL.path),
            @"indexed": @(indexed.count),
            @"tracks":  indexed,
        } mutableCopy];
        if (failed.count > 0) result[@"failed"] = failed;
        return result;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:ShazamErrorDomain code:21
                                     userInfo:@{NSLocalizedDescriptionKey: @"SHCustomCatalog requires macOS 12.0+"}];
        }
        return nil;
    }
}

// ── Signature generator (AVFoundation reads audio into SHSignatureGenerator) ──

- (nullable SHSignature *)generateSignatureFromURL:(NSURL *)url error:(NSError **)error
    API_AVAILABLE(macos(12.0)) {
    AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:url error:error];
    if (!audioFile) return nil;

    AVAudioFormat *srcFormat = audioFile.processingFormat;

    // SHSignatureGenerator works best with mono Float32 PCM at 44100 Hz.
    // Read up to 20 s of source frames, convert in one shot, then feed to the generator.
    AVAudioFramePosition maxSrcFrames = (AVAudioFramePosition)(srcFormat.sampleRate * 20.0);
    AVAudioFrameCount    toRead       = (AVAudioFrameCount)MIN(audioFile.length, maxSrcFrames);

    AVAudioPCMBuffer *srcBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:srcFormat frameCapacity:toRead];
    if (!srcBuf) {
        if (error) *error = [NSError errorWithDomain:ShazamErrorDomain code:30 userInfo:nil];
        return nil;
    }
    if (![audioFile readIntoBuffer:srcBuf frameCount:toRead error:error]) return nil;

    // Convert to 44100 Hz mono Float32 if the source format differs.
    AVAudioFormat *shazamFormat = [[AVAudioFormat alloc]
        initWithCommonFormat:AVAudioPCMFormatFloat32
                  sampleRate:44100.0
                    channels:1
                 interleaved:NO];

    AVAudioPCMBuffer *feedBuf;
    if (srcFormat.sampleRate == 44100.0 && srcFormat.channelCount == 1
            && srcFormat.commonFormat == AVAudioPCMFormatFloat32) {
        feedBuf = srcBuf;  // already in the right format
    } else {
        AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:srcFormat toFormat:shazamFormat];
        if (!converter) {
            if (error) *error = [NSError errorWithDomain:ShazamErrorDomain code:31
                                                 userInfo:@{NSLocalizedDescriptionKey: @"Could not create audio format converter for ShazamKit"}];
            return nil;
        }
        AVAudioFrameCount outCap = (AVAudioFrameCount)ceil((double)toRead * 44100.0 / srcFormat.sampleRate) + 512;
        feedBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:shazamFormat frameCapacity:outCap];
        if (!feedBuf) {
            if (error) *error = [NSError errorWithDomain:ShazamErrorDomain code:32 userInfo:nil];
            return nil;
        }
        // Single-shot convert: the source buffer is fully loaded, so we signal EndOfStream after
        // providing it once.
        __block BOOL provided = NO;
        AVAudioConverterOutputStatus status = [converter convertToBuffer:feedBuf error:error
            withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNumberOfPackets, AVAudioConverterInputStatus *outStatus) {
                if (provided) {
                    *outStatus = AVAudioConverterInputStatus_EndOfStream;
                    return nil;
                }
                provided     = YES;
                *outStatus   = AVAudioConverterInputStatus_HaveData;
                return srcBuf;
            }];
        if (status == AVAudioConverterOutputStatus_Error) return nil;
    }

    // Feed converted audio to the generator in 8 k-frame chunks.
    SHSignatureGenerator *gen = [[SHSignatureGenerator alloc] init];
    AVAudioFrameCount     cap = 8192;
    AVAudioFrameCount     total = feedBuf.frameLength;
    AVAudioFrameCount     pos   = 0;

    while (pos < total) {
        AVAudioFrameCount chunkSize = MIN(cap, total - pos);
        // Sub-buffer pointing into feedBuf's channel data at the current offset.
        AVAudioPCMBuffer *chunk = [[AVAudioPCMBuffer alloc] initWithPCMFormat:shazamFormat frameCapacity:chunkSize];
        if (!chunk) break;
        chunk.frameLength = chunkSize;
        memcpy(chunk.floatChannelData[0],
               feedBuf.floatChannelData[0] + pos,
               chunkSize * sizeof(float));
        if (![gen appendBuffer:chunk atTime:nil error:error]) return nil;
        pos += chunkSize;
    }
    return [gen signature];
}

// ── Audio file listing ────────────────────────────────────────────────────────

- (nullable NSArray<NSURL *> *)listAudioFilesInDirectory:(NSString *)dir error:(NSError **)error {
    NSURL *dirURL = [NSURL fileURLWithPath:dir];
    NSArray<NSURL *> *contents =
        [[NSFileManager defaultManager] contentsOfDirectoryAtURL:dirURL
                                      includingPropertiesForKeys:nil
                                                         options:0
                                                           error:error];
    if (!contents) return nil;

    NSSet *exts = [NSSet setWithArray:@[@"wav",@"mp3",@"m4a",@"aac",@"aiff",@"caf",@"flac",@"mp4",@"mov"]];
    NSArray *filtered = [contents filteredArrayUsingPredicate:
                         [NSPredicate predicateWithBlock:^BOOL(NSURL *u, NSDictionary *_) {
        return [exts containsObject:u.pathExtension.lowercaseString];
    }]];
    return [filtered sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.path compare:b.path];
    }];
}

// ── MVAU stream-in mode ───────────────────────────────────────────────────────

- (BOOL)runAudioStreamWithError:(NSError **)error {
    MVAudioFormat fallback;
    fallback.sampleRate = self.sampleRate > 0 ? self.sampleRate : 16000;
    fallback.channels   = self.channels   > 0 ? self.channels   : 1;
    fallback.bitDepth   = self.bitDepth   > 0 ? self.bitDepth   : 16;

    MVAudioReader *reader = [[MVAudioReader alloc] initWithFileDescriptor:STDIN_FILENO
                                                            fallbackFormat:fallback];
    NSError *readErr = nil;
    NSData *pcmData = [reader readAllData:&readErr];
    if (!pcmData || pcmData.length == 0) {
        if (error) *error = readErr ?: [NSError errorWithDomain:ShazamErrorDomain code:70
                                          userInfo:@{NSLocalizedDescriptionKey: @"No audio data received from stdin"}];
        return NO;
    }

    MVAudioFormat fmt = reader.format;

    // Write PCM to a temp WAV file for Shazam matching
    NSString *tmpName = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"wav"];
    NSURL *tmpWav = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:tmpName]];

    NSDictionary *wavSettings = @{
        AVFormatIDKey:             @(kAudioFormatLinearPCM),
        AVSampleRateKey:           @(fmt.sampleRate),
        AVNumberOfChannelsKey:     @(fmt.channels),
        AVLinearPCMBitDepthKey:    @(fmt.bitDepth),
        AVLinearPCMIsFloatKey:     @NO,
        AVLinearPCMIsBigEndianKey: @NO,
    };
    NSError *wavErr = nil;
    AVAudioFile *wavFile = [[AVAudioFile alloc] initForWriting:tmpWav settings:wavSettings error:&wavErr];
    if (!wavFile) { if (error) *error = wavErr; return NO; }

    AVAudioFormat *avFmt = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                            sampleRate:(double)fmt.sampleRate
                                                              channels:(AVAudioChannelCount)fmt.channels
                                                           interleaved:YES];
    AVAudioFrameCount frameCount = (AVAudioFrameCount)(pcmData.length / (fmt.channels * (fmt.bitDepth / 8)));
    AVAudioPCMBuffer *pcmBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:avFmt frameCapacity:frameCount];
    pcmBuf.frameLength = frameCount;
    memcpy(pcmBuf.int16ChannelData[0], pcmData.bytes, pcmData.length);

    if (![wavFile writeFromBuffer:pcmBuf error:error]) {
        [[NSFileManager defaultManager] removeItemAtURL:tmpWav error:nil];
        return NO;
    }
    wavFile = nil;

    // Run regular match on the temp file
    self.inputPath = tmpWav.path;
    self.streamIn  = NO;  // avoid recursive call
    BOOL ok = [self runWithError:error];
    [[NSFileManager defaultManager] removeItemAtURL:tmpWav error:nil];
    return ok;
}

@end
