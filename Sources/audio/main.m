#import "main.h"
#import <AVFoundation/AVFoundation.h>
#import <Speech/Speech.h>
#import <SoundAnalysis/SoundAnalysis.h>
#import <ShazamKit/ShazamKit.h>
#import <Cocoa/Cocoa.h>
#include <math.h>

static NSString *const AudioErrorDomain = @"AudioProcessorError";

// ── JSON helpers ──────────────────────────────────────────────────────────────

static void APrintJSON(id obj) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    if (data) {
        NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        printf("%s\n", str.UTF8String);
    }
}

static BOOL AWriteJSON(id obj, NSURL *url, NSError **error) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:error];
    if (!data) return NO;
    [[NSFileManager defaultManager] createDirectoryAtURL:[url URLByDeletingLastPathComponent]
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

// ── SoundAnalysis: Classification observer ────────────────────────────────────

@interface AudioClassificationObserver : NSObject <SNResultsObserving>
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *results;
@property (nonatomic, assign) NSInteger topK;
- (instancetype)initWithTopK:(NSInteger)topK;
@end

@implementation AudioClassificationObserver

- (instancetype)initWithTopK:(NSInteger)topK {
    if (self = [super init]) {
        _topK    = topK;
        _results = [NSMutableArray array];
    }
    return self;
}

- (void)request:(id<SNRequest>)request didProduceResult:(id<SNResult>)result {
    if (![result isKindOfClass:[SNClassificationResult class]]) return;
    SNClassificationResult *cr = (SNClassificationResult *)result;
    NSArray *all  = cr.classifications;
    NSInteger cnt = MIN(self.topK, (NSInteger)all.count);
    NSMutableArray *classes = [NSMutableArray arrayWithCapacity:cnt];
    for (NSInteger i = 0; i < cnt; i++) {
        SNClassification *c = all[i];
        [classes addObject:@{
            @"identifier": c.identifier,
            @"confidence": @(round(c.confidence * 1000.0) / 1000.0)
        }];
    }
    [self.results addObject:@{
        @"time":     @(round(CMTimeGetSeconds(cr.timeRange.start)    * 100.0) / 100.0),
        @"duration": @(round(CMTimeGetSeconds(cr.timeRange.duration) * 100.0) / 100.0),
        @"classifications": classes
    }];
}

- (void)request:(id<SNRequest>)request didFailWithError:(NSError *)error {
    fprintf(stderr, "Classification error: %s\n", error.localizedDescription.UTF8String);
}

- (void)requestDidComplete:(id<SNRequest>)request {}

@end

// ── SoundAnalysis: Detection observer (all classes, for targeted filtering) ───

@interface AudioDetectionObserver : NSObject <SNResultsObserving>
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *results;
@end

@implementation AudioDetectionObserver

- (instancetype)init {
    if (self = [super init]) {
        _results = [NSMutableArray array];
    }
    return self;
}

- (void)request:(id<SNRequest>)request didProduceResult:(id<SNResult>)result {
    if (![result isKindOfClass:[SNClassificationResult class]]) return;
    SNClassificationResult *cr = (SNClassificationResult *)result;
    NSMutableArray *classes = [NSMutableArray array];
    for (SNClassification *c in cr.classifications) {
        [classes addObject:@{
            @"identifier": c.identifier,
            @"confidence": @(round(c.confidence * 1000.0) / 1000.0)
        }];
    }
    [self.results addObject:@{
        @"time":     @(round(CMTimeGetSeconds(cr.timeRange.start)    * 100.0) / 100.0),
        @"duration": @(round(CMTimeGetSeconds(cr.timeRange.duration) * 100.0) / 100.0),
        @"classifications": classes
    }];
}

- (void)request:(id<SNRequest>)request didFailWithError:(NSError *)error {}
- (void)requestDidComplete:(id<SNRequest>)request {}

@end

// ── ShazamKit delegate ────────────────────────────────────────────────────────

API_AVAILABLE(macos(12.0))
@interface AudioShazamDelegate : NSObject <SHSessionDelegate>
@property (nonatomic, strong) NSDictionary *result;
@property (nonatomic)         dispatch_semaphore_t semaphore;
- (instancetype)initWithSemaphore:(dispatch_semaphore_t)sem;
@end

API_AVAILABLE(macos(12.0))
@implementation AudioShazamDelegate

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
    dispatch_semaphore_signal(self.semaphore);
}

@end

// ── AudioProcessor ────────────────────────────────────────────────────────────

@implementation AudioProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation = @"classify";
        _lang      = @"en-US";
        _topk      = 3;
    }
    return self;
}

// ── Public entry point ────────────────────────────────────────────────────────

- (BOOL)runWithError:(NSError **)error {
    BOOL hasInput = self.audio || self.audioDir || self.mic;
    if (!hasInput) {
        if (error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Provide --audio, --audio-dir, or --mic"}];
        }
        return NO;
    }

    NSArray *validOps = @[@"transcribe", @"classify", @"shazam",
                          @"detect", @"noise", @"pitch", @"isolate", @"shazam-custom", @"shazam-build"];
    if (![validOps containsObject:self.operation]) {
        if (error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:2
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Unknown operation '%@'. Valid: %@",
                                                     self.operation, [validOps componentsJoinedByString:@", "]]}];
        }
        return NO;
    }

    if (self.mic) {
        return [self runStreamingWithError:error];
    }

    NSArray<NSURL *> *files;
    if (self.audioDir) {
        files = [self listAudioFilesInDirectory:self.audioDir error:error];
        if (!files) return NO;
    } else if (self.audio) {
        files = @[[NSURL fileURLWithPath:self.audio]];
    } else {
        files = @[];
    }

    if (self.debug) {
        fprintf(stderr, "Processing %lu files\n", (unsigned long)files.count);
    }

    NSMutableArray *allResults = [NSMutableArray array];

    for (NSURL *fileURL in files) {
        NSDictionary *result = [self processFile:fileURL error:error];
        if (!result) return NO;

        if (self.outputDir) {
            NSString *baseName = [[fileURL.lastPathComponent stringByDeletingPathExtension]
                                  stringByAppendingPathExtension:@"json"];
            NSURL *outURL = [[NSURL fileURLWithPath:self.outputDir] URLByAppendingPathComponent:baseName];
            if (!AWriteJSON(result, outURL, error)) return NO;
        } else if (files.count == 1 && self.output) {
            if (!AWriteJSON(result, [NSURL fileURLWithPath:self.output], error)) return NO;
        } else if (!self.outputDir && !self.output) {
            APrintJSON(result);
        }
        [allResults addObject:result];
    }

    if (self.merge && self.output) {
        NSDictionary *merged = @{@"operation": self.operation, @"files": allResults};
        if (!AWriteJSON(merged, [NSURL fileURLWithPath:self.output], error)) return NO;
    }

    return YES;
}

// ── Per-file dispatcher ───────────────────────────────────────────────────────

- (nullable NSDictionary *)processFile:(NSURL *)url error:(NSError **)error {
    NSDate *start = [NSDate date];

    // shazam-build takes a directory, not an audio file — skip file-info probing
    if ([self.operation isEqualToString:@"shazam-build"]) {
        NSDictionary *results = [self buildShazamCatalogFromURL:url error:error];
        if (!results) return nil;
        NSMutableDictionary *dict = [results mutableCopy];
        if (self.debug) dict[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
        return dict;
    }

    NSDictionary *fi = [self audioFileInfoForURL:url error:error];
    if (!fi) return nil;

    id results = nil;

    if ([self.operation isEqualToString:@"transcribe"]) {
        results = [self transcribeURL:url error:error];
    } else if ([self.operation isEqualToString:@"classify"]) {
        results = [self classifyURL:url error:error];
    } else if ([self.operation isEqualToString:@"shazam"]) {
        results = [self shazamURL:url error:error];
    } else if ([self.operation isEqualToString:@"detect"]) {
        results = [self detectSoundsInURL:url error:error];
    } else if ([self.operation isEqualToString:@"noise"]) {
        results = [self measureNoiseInURL:url error:error];
    } else if ([self.operation isEqualToString:@"pitch"]) {
        results = [self analyzePitchInURL:url error:error];
    } else if ([self.operation isEqualToString:@"isolate"]) {
        results = [self isolateVoiceInURL:url error:error];
    } else if ([self.operation isEqualToString:@"shazam-custom"]) {
        results = [self shazamCustomURL:url error:error];
    } else if ([self.operation isEqualToString:@"shazam-build"]) {
        results = [self buildShazamCatalogFromURL:url error:error];
    }

    if (!results) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:3
                                     userInfo:@{NSLocalizedDescriptionKey: @"Operation returned no results"}];
        }
        return nil;
    }

    NSMutableDictionary *dict = [@{
        @"operation":  self.operation,
        @"file":       url.lastPathComponent,
        @"path":       url.path,
        @"duration":   fi[@"duration"],
        @"sampleRate": fi[@"sampleRate"],
        @"channels":   fi[@"channels"],
        @"results":    results
    } mutableCopy];

    if (self.debug) {
        dict[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }
    return dict;
}

// ── transcribe (SFSpeechRecognizer) ──────────────────────────────────────────

- (nullable NSArray *)transcribeURL:(NSURL *)url error:(NSError **)error {
    // requestAuthorization crashes on macOS 26 unless signed with a real Developer ID.
    // Check status only; sign with a Developer ID cert to get the permission prompt.
    SFSpeechRecognizerAuthorizationStatus authStatus = [SFSpeechRecognizer authorizationStatus];

    if (authStatus != SFSpeechRecognizerAuthorizationStatusAuthorized) {
        if (error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:10
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Speech recognition not authorized — sign the binary with a Developer ID certificate "
                                                    "to trigger the permission prompt (macOS 26 requires a real cert for requestAuthorization)"}];
        }
        return nil;
    }

    SFSpeechRecognizer *recognizer =
        [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:self.lang]];
    if (!recognizer) {
        if (error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:11
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Unsupported locale: %@", self.lang]}];
        }
        return nil;
    }
    if (!recognizer.isAvailable) {
        if (error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:12
                                     userInfo:@{NSLocalizedDescriptionKey: @"Speech recognizer not available"}];
        }
        return nil;
    }

    SFSpeechURLRecognitionRequest *request = [[SFSpeechURLRecognitionRequest alloc] initWithURL:url];
    if (@available(macOS 13.0, *)) {
        request.requiresOnDeviceRecognition = self.offline;
    }
    request.shouldReportPartialResults = NO;

    __block NSMutableArray *segments = [NSMutableArray array];
    __block NSError *recognitionError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    SFSpeechRecognitionTask *task =
        [recognizer recognitionTaskWithRequest:request
                                 resultHandler:^(SFSpeechRecognitionResult *result, NSError *err) {
            if (err) {
                recognitionError = err;
                dispatch_semaphore_signal(sem);
                return;
            }
            if (!result || !result.isFinal) return;

            SFTranscription *tx = result.bestTranscription;
            double totalDuration = 0.0;
            float  totalConf     = 0.0f;
            for (SFTranscriptionSegment *seg in tx.segments) {
                totalDuration = seg.timestamp + seg.duration;
                totalConf    += seg.confidence;
                [segments addObject:@{
                    @"text":       seg.substring,
                    @"timestamp":  @(round(seg.timestamp * 1000.0) / 1000.0),
                    @"duration":   @(round(seg.duration  * 1000.0) / 1000.0),
                    @"confidence": @(seg.confidence)
                }];
            }
            float avgConf = tx.segments.count > 0 ? totalConf / (float)tx.segments.count : 0.0f;
            [segments insertObject:@{
                @"text":               tx.formattedString,
                @"timestamp":          @(0),
                @"duration":           @(totalDuration),
                @"confidence":         @(avgConf),
                @"is_full_transcript": @YES,
                @"api":                @"SFSpeechRecognizer"
            } atIndex:0];
            dispatch_semaphore_signal(sem);
        }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    [task cancel];

    if (recognitionError) {
        if (error) *error = recognitionError;
        return nil;
    }
    return segments;
}

// ── classify (SNClassifySoundRequest, macOS 12+) ──────────────────────────────

- (nullable NSArray *)classifyURL:(NSURL *)url error:(NSError **)error {
    if (@available(macOS 12.0, *)) {
        SNClassifySoundRequest *request =
            [[SNClassifySoundRequest alloc] initWithClassifierIdentifier:SNClassifierIdentifierVersion1
                                                                   error:error];
        if (!request) return nil;

        SNAudioFileAnalyzer *analyzer = [[SNAudioFileAnalyzer alloc] initWithURL:url error:error];
        if (!analyzer) return nil;

        AudioClassificationObserver *observer = [[AudioClassificationObserver alloc] initWithTopK:self.topk];
        if (![analyzer addRequest:request withObserver:observer error:error]) return nil;
        [analyzer analyze];
        return observer.results;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:22
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"Sound classification requires macOS 12.0+"}];
        }
        return nil;
    }
}

// ── shazam (SHSession, macOS 12+) ────────────────────────────────────────────

- (nullable NSDictionary *)shazamURL:(NSURL *)url error:(NSError **)error {
    if (@available(macOS 12.0, *)) {
        SHSignature *sig = [self generateSignatureFromURL:url error:error];
        if (!sig) return nil;

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        AudioShazamDelegate *delegate = [[AudioShazamDelegate alloc] initWithSemaphore:sem];
        SHSession *session = [[SHSession alloc] init];
        session.delegate = delegate;
        [session matchSignature:sig];
        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
        return delegate.result;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:20
                                     userInfo:@{NSLocalizedDescriptionKey: @"ShazamKit requires macOS 12.0+"}];
        }
        return nil;
    }
}

// ── detect (SNClassifySoundRequest filtered to specific sound keywords) ────────

- (nullable NSArray *)detectSoundsInURL:(NSURL *)url error:(NSError **)error {
    if (@available(macOS 12.0, *)) {
        SNClassifySoundRequest *request =
            [[SNClassifySoundRequest alloc] initWithClassifierIdentifier:SNClassifierIdentifierVersion1
                                                                   error:error];
        if (!request) return nil;

        SNAudioFileAnalyzer *analyzer = [[SNAudioFileAnalyzer alloc] initWithURL:url error:error];
        if (!analyzer) return nil;

        AudioDetectionObserver *observer = [[AudioDetectionObserver alloc] init];
        if (![analyzer addRequest:request withObserver:observer error:error]) return nil;
        [analyzer analyze];

        NSArray *targets = @[@"crying", @"scream", @"glass", @"alarm",
                             @"siren", @"dog", @"cat", @"baby"];
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSDictionary *result in observer.results) {
            NSArray *matched = [result[@"classifications"]
                filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *cls, NSDictionary *_) {
                    NSString *id_ = [cls[@"identifier"] lowercaseString];
                    for (NSString *t in targets) {
                        if ([id_ containsString:t]) return YES;
                    }
                    return NO;
                }]];
            if (matched.count > 0) {
                NSMutableDictionary *entry = [result mutableCopy];
                entry[@"classifications"] = matched;
                [filtered addObject:entry];
            }
        }
        return filtered;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:23
                                     userInfo:@{NSLocalizedDescriptionKey: @"Sound detection requires macOS 12.0+"}];
        }
        return nil;
    }
}

// ── noise (RMS across 100 ms windows) ────────────────────────────────────────

- (nullable NSArray *)measureNoiseInURL:(NSURL *)url error:(NSError **)error {
    AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:url error:error];
    if (!audioFile) return nil;

    AVAudioFormat *format = audioFile.processingFormat;
    AVAudioPCMBuffer *buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                                          frameCapacity:(AVAudioFrameCount)audioFile.length];
    if (!buf || ![audioFile readIntoBuffer:buf error:error]) return nil;

    float *const *ch = buf.floatChannelData;
    if (!ch) return @[];

    double sr  = format.sampleRate;
    NSInteger win  = (NSInteger)(sr * 0.1);  // 100 ms
    NSInteger nch  = (NSInteger)format.channelCount;
    NSMutableArray *out = [NSMutableArray array];

    for (NSInteger s = 0; s < (NSInteger)buf.frameLength; s += win) {
        NSInteger e = MIN(s + win, (NSInteger)buf.frameLength);
        NSInteger n = e - s;
        float ssq = 0.0f;
        for (NSInteger c = 0; c < nch; c++) {
            for (NSInteger i = s; i < e; i++) ssq += ch[c][i] * ch[c][i];
        }
        float rms = sqrtf(ssq / (float)(n * nch));
        float db  = 20.0f * log10f(MAX(rms, 1e-5f));
        NSString *level = (db > -20) ? @"loud" : (db > -40) ? @"moderate" : @"quiet";
        [out addObject:@{
            @"time":  @(round((double)s / sr * 100.0) / 100.0),
            @"rms":   @(round(rms * 10000.0) / 10000.0),
            @"db":    @(round(db  * 10.0)    / 10.0),
            @"level": level
        }];
    }
    return out;
}

// ── pitch (autocorrelation) ───────────────────────────────────────────────────

- (nullable NSArray *)analyzePitchInURL:(NSURL *)url error:(NSError **)error {
    AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:url error:error];
    if (!audioFile) return nil;

    AVAudioFormat *format = audioFile.processingFormat;
    AVAudioPCMBuffer *buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format
                                                          frameCapacity:(AVAudioFrameCount)audioFile.length];
    if (!buf || ![audioFile readIntoBuffer:buf error:error]) return nil;

    float *const *ch = buf.floatChannelData;
    if (!ch) return @[];

    float *data  = ch[0];
    float sr     = (float)format.sampleRate;
    NSInteger win = 2048, hop = 512;
    NSMutableArray *pitches = [NSMutableArray array];

    for (NSInteger s = 0; s + win < (NSInteger)buf.frameLength; s += hop) {
        float maxCorr = 0.0f;
        NSInteger bestLag = 0;
        NSInteger lagMax = MIN(1000, win / 2);
        for (NSInteger lag = 50; lag < lagMax; lag++) {
            float corr = 0.0f;
            for (NSInteger i = 0; i < win - lag; i++) corr += data[s+i] * data[s+i+lag];
            if (corr > maxCorr) { maxCorr = corr; bestLag = lag; }
        }
        if (bestLag > 0 && maxCorr > 0.1f) {
            float freq = sr / (float)bestLag;
            if (freq >= 50.0f && freq <= 2000.0f) {
                [pitches addObject:@{
                    @"time":       @(round((double)s / (double)sr * 100.0) / 100.0),
                    @"frequency":  @(round(freq * 10.0) / 10.0),
                    @"note":       [self frequencyToNote:freq],
                    @"confidence": @(round(maxCorr * 100.0) / 100.0)
                }];
            }
        }
    }
    return pitches;
}

- (NSString *)frequencyToNote:(float)freq {
    NSArray *notes = @[@"C",@"C#",@"D",@"D#",@"E",@"F",@"F#",@"G",@"G#",@"A",@"A#",@"B"];
    float semitones = 12.0f * log2f(freq / 440.0f);
    NSInteger idx   = ((NSInteger)roundf(semitones) % 12 + 12) % 12;
    NSInteger oct   = 4 + (NSInteger)roundf(semitones) / 12;
    return [NSString stringWithFormat:@"%@%ld", notes[idx], (long)oct];
}

// ── isolate (offline AVAudioEngine with high-pass filter) ─────────────────────

- (nullable NSDictionary *)isolateVoiceInURL:(NSURL *)url error:(NSError **)error {
    NSString *name = [NSString stringWithFormat:@"isolated_%@.m4a",
                      url.lastPathComponent.stringByDeletingPathExtension];
    NSURL *outDirURL;
    if (self.outputDir) {
        outDirURL = [NSURL fileURLWithPath:self.outputDir];
    } else if (self.output) {
        outDirURL = [[NSURL fileURLWithPath:self.output] URLByDeletingLastPathComponent];
    } else {
        outDirURL = [NSURL fileURLWithPath:NSTemporaryDirectory()];
    }
    [[NSFileManager defaultManager] createDirectoryAtURL:outDirURL
                             withIntermediateDirectories:YES attributes:nil error:nil];
    NSURL *outURL = [outDirURL URLByAppendingPathComponent:name];

    AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:url error:error];
    if (!audioFile) return nil;

    AVAudioEngine    *engine = [[AVAudioEngine alloc] init];
    AVAudioPlayerNode *player = [[AVAudioPlayerNode alloc] init];
    AVAudioUnitEQ    *eq     = [[AVAudioUnitEQ alloc] initWithNumberOfBands:1];
    eq.bands[0].filterType = AVAudioUnitEQFilterTypeHighPass;
    eq.bands[0].frequency  = 150.0f;
    eq.bands[0].bypass     = NO;

    [engine attachNode:player];
    [engine attachNode:eq];
    [engine connect:player to:eq format:audioFile.processingFormat];
    [engine connect:eq to:engine.mainMixerNode format:audioFile.processingFormat];

    if (![engine enableManualRenderingMode:AVAudioEngineManualRenderingModeOffline
                                    format:audioFile.processingFormat
                         maximumFrameCount:4096
                                     error:error]) return nil;
    if (![engine startAndReturnError:error]) return nil;
    [player scheduleFile:audioFile atTime:nil completionHandler:nil];
    [player play];

    AVAudioFile *outFile = [[AVAudioFile alloc] initForWriting:outURL
                                                      settings:audioFile.fileFormat.settings
                                                         error:error];
    if (!outFile) { [engine stop]; return nil; }

    AVAudioPCMBuffer *renderBuf =
        [[AVAudioPCMBuffer alloc] initWithPCMFormat:engine.manualRenderingFormat frameCapacity:4096];

    while (engine.manualRenderingSampleTime < audioFile.length) {
        AVAudioFrameCount toRender =
            (AVAudioFrameCount)MIN(4096LL, audioFile.length - engine.manualRenderingSampleTime);
        AVAudioEngineManualRenderingStatus status =
            [engine renderOffline:toRender toBuffer:renderBuf error:error];
        if (status == AVAudioEngineManualRenderingStatusError) break;
        if (renderBuf.frameLength > 0) { [outFile writeFromBuffer:renderBuf error:nil]; }
        if (status == AVAudioEngineManualRenderingStatusInsufficientDataFromInputNode) break;
    }
    [player stop];
    [engine stop];

    return @{
        @"input":  url.path,
        @"output": outURL.path,
        @"method": @"high-pass filter (150Hz)",
        @"note":   @"macOS 15+ voiceProcessing API available for better isolation"
    };
}

// ── shazam-custom (match against custom or default Shazam catalog) ───────────

- (nullable NSDictionary *)shazamCustomURL:(NSURL *)url error:(NSError **)error {
    if (@available(macOS 12.0, *)) {
        SHSignature *sig = [self generateSignatureFromURL:url error:error];
        if (!sig) return nil;

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        AudioShazamDelegate *delegate = [[AudioShazamDelegate alloc] initWithSemaphore:sem];
        SHSession *session;

        if (self.catalog) {
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

        NSMutableDictionary *result = [delegate.result mutableCopy];
        if (self.catalog) {
            result[@"catalog"] = self.catalog;
        } else {
            result[@"note"] = @"No --catalog provided; matched against default Shazam catalog";
        }
        return result;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:21
                                     userInfo:@{NSLocalizedDescriptionKey: @"ShazamKit requires macOS 12.0+"}];
        }
        return nil;
    }
}

// ── shazam-build (SHCustomCatalog, macOS 12+) ────────────────────────────────

- (nullable NSDictionary *)buildShazamCatalogFromURL:(NSURL *)url error:(NSError **)error {
    BOOL isDir = NO;
    if (![[NSFileManager defaultManager] fileExistsAtPath:url.path isDirectory:&isDir] || !isDir) {
        if (error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:50
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"shazam-build requires a directory path (pass via --audio)"}];
        }
        return nil;
    }

    NSArray<NSURL *> *files = [self listAudioFilesInDirectory:url.path error:error];
    if (!files) return nil;

    if (@available(macOS 12.0, *)) {
        SHCustomCatalog *catalog = [[SHCustomCatalog alloc] init];
        NSMutableArray<NSString *>      *indexed = [NSMutableArray array];
        NSMutableArray<NSDictionary *>  *failed  = [NSMutableArray array];

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
            SHMediaItem *item = [SHMediaItem mediaItemWithProperties:@{
                SHMediaItemTitle: title
            }];

            NSError *addErr = nil;
            if (![catalog addReferenceSignature:sig representingMediaItems:@[item] error:&addErr]) {
                [failed addObject:@{
                    @"file":  fileURL.lastPathComponent,
                    @"error": addErr.localizedDescription ?: @"failed to add signature to catalog"
                }];
            } else {
                [indexed addObject:title];
            }
        }

        // Derive .shazamcatalog path from --output, --output-dir, or fall back to input dir
        NSURL *catalogURL;
        if (self.output) {
            NSString *base = [[self.output stringByDeletingPathExtension]
                              stringByAppendingPathExtension:@"shazamcatalog"];
            catalogURL = [NSURL fileURLWithPath:base];
        } else if (self.outputDir) {
            NSString *name = [url.lastPathComponent stringByAppendingPathExtension:@"shazamcatalog"];
            catalogURL = [[NSURL fileURLWithPath:self.outputDir] URLByAppendingPathComponent:name];
        } else {
            NSString *name = [url.lastPathComponent stringByAppendingPathExtension:@"shazamcatalog"];
            catalogURL = [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:name];
        }

        [[NSFileManager defaultManager] createDirectoryAtURL:[catalogURL URLByDeletingLastPathComponent]
                                 withIntermediateDirectories:YES attributes:nil error:nil];

        if (![catalog writeToURL:catalogURL error:error]) return nil;

        NSMutableDictionary *result = [@{
            @"catalog": catalogURL.path,
            @"indexed": @(indexed.count),
            @"tracks":  indexed,
        } mutableCopy];
        if (failed.count > 0) result[@"failed"] = failed;
        return result;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:51
                                     userInfo:@{NSLocalizedDescriptionKey: @"SHCustomCatalog requires macOS 12.0+"}];
        }
        return nil;
    }
}

// ── Streaming modes ───────────────────────────────────────────────────────────

- (BOOL)runStreamingWithError:(NSError **)error {
    return [self streamMicWithError:error];
}

- (BOOL)streamMicWithError:(NSError **)error {
    NSArray *micOps = @[@"transcribe", @"classify"];
    if (![micOps containsObject:self.operation]) {
        if (error) {
            *error = [NSError errorWithDomain:AudioErrorDomain code:60
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"--mic supports: transcribe, classify"}];
        }
        return NO;
    }

    fprintf(stderr, "Listening... Press ENTER to stop\n");
    AVAudioEngine *engine = [[AVAudioEngine alloc] init];
    AVAudioFormat *format = [engine.inputNode outputFormatForBus:0];

    if ([self.operation isEqualToString:@"classify"]) {
        if (@available(macOS 12.0, *)) {
            SNAudioStreamAnalyzer *sa = [[SNAudioStreamAnalyzer alloc] initWithFormat:format];
            SNClassifySoundRequest *req =
                [[SNClassifySoundRequest alloc] initWithClassifierIdentifier:SNClassifierIdentifierVersion1
                                                                       error:error];
            if (!req) return NO;
            AudioClassificationObserver *obs = [[AudioClassificationObserver alloc] initWithTopK:self.topk];
            if (![sa addRequest:req withObserver:obs error:error]) return NO;

            [engine.inputNode installTapOnBus:0 bufferSize:8192 format:format
                                        block:^(AVAudioPCMBuffer *buf, AVAudioTime *t) {
                [sa analyzeAudioBuffer:buf atAudioFramePosition:t.sampleTime];
            }];
            if (![engine startAndReturnError:error]) return NO;
            char lb[256]; fgets(lb, sizeof(lb), stdin);
            [engine stop];
            APrintJSON(@{@"operation": @"classify", @"source": @"mic", @"results": obs.results});
        } else {
            if (error) {
                *error = [NSError errorWithDomain:AudioErrorDomain code:22
                                         userInfo:@{NSLocalizedDescriptionKey: @"Sound classification requires macOS 12.0+"}];
            }
            return NO;
        }
    } else {
        SFSpeechRecognizer *recognizer =
            [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:self.lang]];
        SFSpeechAudioBufferRecognitionRequest *req = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
        if (@available(macOS 13.0, *)) { req.requiresOnDeviceRecognition = self.offline; }

        __block NSString *finalText = @"";
        SFSpeechRecognitionTask *task =
            [recognizer recognitionTaskWithRequest:req
                                     resultHandler:^(SFSpeechRecognitionResult *r, NSError *_) {
                if (r) {
                    finalText = r.bestTranscription.formattedString;
                    fprintf(stderr, "\r\033[K%s", finalText.UTF8String);
                }
            }];

        [engine.inputNode installTapOnBus:0 bufferSize:1024 format:format
                                    block:^(AVAudioPCMBuffer *buf, AVAudioTime *_) {
            [req appendAudioPCMBuffer:buf];
        }];
        if (![engine startAndReturnError:error]) { [task cancel]; return NO; }
        char lb[256]; fgets(lb, sizeof(lb), stdin);
        fprintf(stderr, "\n");
        [engine stop];
        [req endAudio];
        [task cancel];
        APrintJSON(@{@"operation": @"transcribe", @"source": @"mic", @"text": finalText});
    }
    return YES;
}

// ── ShazamKit signature helper ────────────────────────────────────────────────

- (nullable SHSignature *)generateSignatureFromURL:(NSURL *)url error:(NSError **)error
    API_AVAILABLE(macos(12.0)) {
    AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:url error:error];
    if (!audioFile) return nil;

    AVAudioFormat        *format = audioFile.processingFormat;
    SHSignatureGenerator *gen    = [[SHSignatureGenerator alloc] init];
    AVAudioFrameCount     cap    = 8192;
    AVAudioPCMBuffer     *buf    = [[AVAudioPCMBuffer alloc] initWithPCMFormat:format frameCapacity:cap];
    if (!buf) {
        if (error) *error = [NSError errorWithDomain:AudioErrorDomain code:51 userInfo:nil];
        return nil;
    }

    AVAudioFramePosition maxFrames = (AVAudioFramePosition)(format.sampleRate * 20.0);
    AVAudioFramePosition pos = 0;
    while (pos < audioFile.length && pos < maxFrames) {
        AVAudioFrameCount toRead = (AVAudioFrameCount)MIN((AVAudioFramePosition)cap, audioFile.length - pos);
        buf.frameLength = toRead;
        if (![audioFile readIntoBuffer:buf frameCount:toRead error:error]) return nil;

        // Pass nil for time; SHSignatureGenerator uses buffer position internally
        if (![gen appendBuffer:buf atTime:nil error:error]) return nil;
        pos += (AVAudioFramePosition)toRead;
    }
    return [gen signature];
}

// ── Audio file metadata ───────────────────────────────────────────────────────

- (nullable NSDictionary *)audioFileInfoForURL:(NSURL *)url error:(NSError **)error {
    AVAudioFile *file = [[AVAudioFile alloc] initForReading:url error:error];
    if (!file) return nil;
    AVAudioFormat *fmt = file.processingFormat;
    return @{
        @"duration":   @((double)file.length / fmt.sampleRate),
        @"sampleRate": @(fmt.sampleRate),
        @"channels":   @(fmt.channelCount)
    };
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
        return [exts containsObject:[u.pathExtension lowercaseString]];
    }]];
    return [filtered sortedArrayUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.path compare:b.path];
    }];
}

@end
