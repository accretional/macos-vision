#import "main.h"
#import "common/MVJsonEmit.h"
#import "common/MVAudioStream.h"
#import <SoundAnalysis/SoundAnalysis.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreML/CoreML.h>
#import <CoreMedia/CoreMedia.h>

static NSString * const SNAErrorDomain = @"SNAProcessorError";

// ── Classification observer (batch — file mode) ───────────────────────────────

@interface SNAObserver : NSObject <SNResultsObserving>
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *windows;
@property (nonatomic, assign) NSInteger topK;
- (instancetype)initWithTopK:(NSInteger)topK;
@end

@implementation SNAObserver

- (instancetype)initWithTopK:(NSInteger)topK {
    if (self = [super init]) {
        _topK    = topK;
        _windows = [NSMutableArray array];
    }
    return self;
}

- (void)request:(id<SNRequest>)request didProduceResult:(id<SNResult>)result {
    if (![result isKindOfClass:[SNClassificationResult class]]) return;
    SNClassificationResult *cr = (SNClassificationResult *)result;
    NSArray<SNClassification *> *all = cr.classifications;
    NSInteger count = MIN(self.topK, (NSInteger)all.count);
    NSMutableArray *top = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (NSInteger i = 0; i < count; i++) {
        SNClassification *c = all[(NSUInteger)i];
        [top addObject:@{
            @"identifier": c.identifier,
            @"confidence": @(round(c.confidence * 10000.0) / 10000.0),
        }];
    }
    [self.windows addObject:@{
        @"time":     @(round(CMTimeGetSeconds(cr.timeRange.start)    * 1000.0) / 1000.0),
        @"duration": @(round(CMTimeGetSeconds(cr.timeRange.duration) * 1000.0) / 1000.0),
        @"classifications": top,
    }];
}

- (void)request:(id<SNRequest>)request didFailWithError:(NSError *)error {
    fprintf(stderr, "SoundAnalysis error: %s\n", error.localizedDescription.UTF8String);
}

- (void)requestDidComplete:(id<SNRequest>)request {}

@end

// ── Classification observer (stream — emits NDJSON per window) ────────────────

@interface SNAStreamObserver : NSObject <SNResultsObserving>
@property (nonatomic, assign) NSInteger topK;
- (instancetype)initWithTopK:(NSInteger)topK;
@end

@implementation SNAStreamObserver

- (instancetype)initWithTopK:(NSInteger)topK {
    if (self = [super init]) { _topK = topK; }
    return self;
}

- (void)request:(id<SNRequest>)request didProduceResult:(id<SNResult>)result {
    if (![result isKindOfClass:[SNClassificationResult class]]) return;
    SNClassificationResult *cr = (SNClassificationResult *)result;
    NSArray<SNClassification *> *all = cr.classifications;
    NSInteger count = MIN(self.topK, (NSInteger)all.count);
    NSMutableArray *top = [NSMutableArray arrayWithCapacity:(NSUInteger)count];
    for (NSInteger i = 0; i < count; i++) {
        SNClassification *c = all[(NSUInteger)i];
        [top addObject:@{
            @"identifier": c.identifier,
            @"confidence": @(round(c.confidence * 10000.0) / 10000.0),
        }];
    }
    NSDictionary *window = @{
        @"time":            @(round(CMTimeGetSeconds(cr.timeRange.start)    * 1000.0) / 1000.0),
        @"duration":        @(round(CMTimeGetSeconds(cr.timeRange.duration) * 1000.0) / 1000.0),
        @"classifications": top,
    };
    NSData *jsonData = [NSJSONSerialization dataWithJSONObject:window options:0 error:nil];
    if (jsonData) {
        write(STDOUT_FILENO, jsonData.bytes, jsonData.length);
        write(STDOUT_FILENO, "\n", 1);
    }
}

- (void)request:(id<SNRequest>)request didFailWithError:(NSError *)error {
    fprintf(stderr, "SoundAnalysis error: %s\n", error.localizedDescription.UTF8String);
}

- (void)requestDidComplete:(id<SNRequest>)request {}

@end

// ── SNAProcessor ──────────────────────────────────────────────────────────────

@implementation SNAProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation  = @"classify";
        _topk       = 5;
        _sampleRate = 16000;
        _channels   = 1;
        _bitDepth   = 16;
    }
    return self;
}

// ── Public entry point ────────────────────────────────────────────────────────

- (BOOL)runWithError:(NSError **)error {
    NSArray *validOps = @[@"classify", @"classify-custom", @"detect", @"list-labels"];
    if (![validOps containsObject:self.operation]) {
        if (error) {
            *error = [NSError errorWithDomain:SNAErrorDomain code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Unknown operation '%@'. Valid: %@",
                                                     self.operation, [validOps componentsJoinedByString:@", "]]}];
        }
        return NO;
    }

    if ([self.operation isEqualToString:@"list-labels"]) {
        NSDictionary *result = [self listLabelsWithError:error];
        if (!result) return NO;
        NSDictionary *envelope = MVMakeEnvelope(@"sna", self.operation, @"", result);
        return MVEmitEnvelope(envelope, self.jsonOutput, error);
    }

    // Stream-in mode: read audio from stdin
    if (self.streamIn) return [self runAudioStreamWithError:error];

    if (!self.inputPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:SNAErrorDomain code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Provide --input <audio_file>"}];
        }
        return NO;
    }

    NSURL *fileURL = [NSURL fileURLWithPath:self.inputPath];
    NSDictionary *result = nil;

    if ([self.operation isEqualToString:@"classify"]) {
        result = [self classifyBuiltinFromURL:fileURL error:error];
    } else if ([self.operation isEqualToString:@"classify-custom"]) {
        result = [self classifyCustomFromURL:fileURL error:error];
    } else if ([self.operation isEqualToString:@"detect"]) {
        result = [self detectBuiltinFromURL:fileURL error:error];
    }

    if (!result) return NO;

    NSDictionary *envelope = MVMakeEnvelope(@"sna", self.operation, self.inputPath, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── Request configuration helper ──────────────────────────────────────────────

- (BOOL)configureRequest:(SNClassifySoundRequest *)request error:(NSError **)error {
    if (@available(macOS 12.0, *)) {
        if (self.overlapFactorSet) {
            double o = self.overlapFactor;
            if (o < 0.0 || o >= 1.0) {
                if (error) {
                    *error = [NSError errorWithDomain:SNAErrorDomain code:20
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                            @"--classify-overlap must be in [0.0, 1.0)"}];
                }
                return NO;
            }
            request.overlapFactor = o;
        }
        if (self.windowDurationSet) {
            double w = self.windowDuration;
            if (w <= 0.0) {
                if (error) {
                    *error = [NSError errorWithDomain:SNAErrorDomain code:21
                                             userInfo:@{NSLocalizedDescriptionKey:
                                                            @"--classify-window must be > 0 seconds"}];
                }
                return NO;
            }
            request.windowDuration = CMTimeMakeWithSeconds(w, 1000000);
        }
    }
    return YES;
}

// ── Run analysis and collect results ─────────────────────────────────────────

- (nullable NSArray *)runAnalysis:(SNClassifySoundRequest *)request
                          fileURL:(NSURL *)fileURL
                            error:(NSError **)error {
    SNAudioFileAnalyzer *analyzer = [[SNAudioFileAnalyzer alloc] initWithURL:fileURL error:error];
    if (!analyzer) return nil;

    SNAObserver *observer = [[SNAObserver alloc] initWithTopK:self.topk];
    if (![analyzer addRequest:request withObserver:observer error:error]) return nil;

    [analyzer analyze];
    return observer.windows;
}

// ── classify (built-in SNClassifierIdentifierVersion1, macOS 12+) ─────────────

- (nullable NSDictionary *)classifyBuiltinFromURL:(NSURL *)fileURL error:(NSError **)error {
    if (@available(macOS 12.0, *)) {
        SNClassifySoundRequest *request =
            [[SNClassifySoundRequest alloc] initWithClassifierIdentifier:SNClassifierIdentifierVersion1
                                                                   error:error];
        if (!request) return nil;
        if (![self configureRequest:request error:error]) return nil;

        NSDate *start = self.debug ? [NSDate date] : nil;
        NSArray *windows = [self runAnalysis:request fileURL:fileURL error:error];
        if (!windows) return nil;

        NSMutableDictionary *result = [@{
            @"classifier":     @"built-in:v1",
            @"path":           MVRelativePath(fileURL.path),
            @"overlap_factor": @(request.overlapFactor),
            @"window_duration_s": @(CMTimeGetSeconds(request.windowDuration)),
            @"windows":        windows,
        } mutableCopy];
        if (self.debug && start) {
            result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
        }
        return result;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:SNAErrorDomain code:30
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"classify requires macOS 12.0+ (SNClassifierIdentifierVersion1)"}];
        }
        return nil;
    }
}

// ── classify-custom (CoreML model, macOS 10.15+) ──────────────────────────────

- (nullable NSDictionary *)classifyCustomFromURL:(NSURL *)fileURL error:(NSError **)error {
    if (!self.modelPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:SNAErrorDomain code:40
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"classify-custom requires --model <path_to_CoreML_model>"}];
        }
        return nil;
    }

    NSURL *modelURL = [NSURL fileURLWithPath:self.modelPath];
    MLModel *mlModel = [MLModel modelWithContentsOfURL:modelURL error:error];
    if (!mlModel) return nil;

    SNClassifySoundRequest *request = [[SNClassifySoundRequest alloc] initWithMLModel:mlModel error:error];
    if (!request) return nil;
    if (![self configureRequest:request error:error]) return nil;

    NSDate *start = self.debug ? [NSDate date] : nil;
    NSArray *windows = [self runAnalysis:request fileURL:fileURL error:error];
    if (!windows) return nil;

    NSMutableDictionary *result = [@{
        @"classifier": @"custom",
        @"model":      MVRelativePath(self.modelPath),
        @"path":       MVRelativePath(fileURL.path),
        @"windows":    windows,
    } mutableCopy];
    if (@available(macOS 12.0, *)) {
        result[@"overlap_factor"]    = @(request.overlapFactor);
        result[@"window_duration_s"] = @(CMTimeGetSeconds(request.windowDuration));
    }
    if (self.debug && start) {
        result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }
    return result;
}

// ── detect (built-in classifier, filter to target sound keywords) ─────────────

- (nullable NSDictionary *)detectBuiltinFromURL:(NSURL *)fileURL error:(NSError **)error {
    if (@available(macOS 12.0, *)) {
        SNClassifySoundRequest *request =
            [[SNClassifySoundRequest alloc] initWithClassifierIdentifier:SNClassifierIdentifierVersion1
                                                                   error:error];
        if (!request) return nil;
        if (![self configureRequest:request error:error]) return nil;

        // Collect ALL classifications (no topK cap) so we can filter by keyword
        SNAudioFileAnalyzer *analyzer = [[SNAudioFileAnalyzer alloc] initWithURL:fileURL error:error];
        if (!analyzer) return nil;
        SNAObserver *observer = [[SNAObserver alloc] initWithTopK:NSIntegerMax];
        if (![analyzer addRequest:request withObserver:observer error:error]) return nil;

        NSDate *start = self.debug ? [NSDate date] : nil;
        [analyzer analyze];
        NSArray *allWindows = observer.windows;

        NSArray *targets = @[@"crying", @"scream", @"glass", @"alarm",
                             @"siren", @"dog", @"cat", @"baby"];
        NSMutableArray *filtered = [NSMutableArray array];
        for (NSDictionary *win in allWindows) {
            NSArray *matched = [win[@"classifications"]
                filteredArrayUsingPredicate:[NSPredicate predicateWithBlock:^BOOL(NSDictionary *cls, NSDictionary *_) {
                    NSString *ident = [cls[@"identifier"] lowercaseString];
                    for (NSString *t in targets) {
                        if ([ident containsString:t]) return YES;
                    }
                    return NO;
                }]];
            if (matched.count > 0) {
                NSMutableDictionary *entry = [win mutableCopy];
                entry[@"classifications"] = matched;
                [filtered addObject:entry];
            }
        }

        NSMutableDictionary *result = [@{
            @"classifier":        @"built-in:v1",
            @"path":              MVRelativePath(fileURL.path),
            @"overlap_factor":    @(request.overlapFactor),
            @"window_duration_s": @(CMTimeGetSeconds(request.windowDuration)),
            @"targets":           targets,
            @"windows":           filtered,
        } mutableCopy];
        if (self.debug && start) {
            result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
        }
        return result;
    } else {
        if (error) {
            *error = [NSError errorWithDomain:SNAErrorDomain code:31
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"detect requires macOS 12.0+ (SNClassifierIdentifierVersion1)"}];
        }
        return nil;
    }
}

// ── list-labels ───────────────────────────────────────────────────────────────

- (nullable NSDictionary *)listLabelsWithError:(NSError **)error {
    if (@available(macOS 12.0, *)) {
        SNClassifySoundRequest *request = nil;

        if (self.modelPath.length) {
            NSURL *modelURL = [NSURL fileURLWithPath:self.modelPath];
            MLModel *mlModel = [MLModel modelWithContentsOfURL:modelURL error:error];
            if (!mlModel) return nil;
            request = [[SNClassifySoundRequest alloc] initWithMLModel:mlModel error:error];
        } else {
            request = [[SNClassifySoundRequest alloc] initWithClassifierIdentifier:SNClassifierIdentifierVersion1
                                                                             error:error];
        }
        if (!request) return nil;

        NSArray<NSString *> *labels = [request.knownClassifications
                                       sortedArrayUsingSelector:@selector(compare:)];
        NSString *classifier = self.modelPath.length
            ? [@"custom:" stringByAppendingString:MVRelativePath(self.modelPath)]
            : @"built-in:v1";

        return @{
            @"classifier": classifier,
            @"count":      @(labels.count),
            @"labels":     labels,
        };
    } else {
        if (error) {
            *error = [NSError errorWithDomain:SNAErrorDomain code:50
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    @"list-labels requires macOS 12.0+ (knownClassifications)"}];
        }
        return nil;
    }
}

// ── MVAU stream-in mode ───────────────────────────────────────────────────────
// Uses SNAudioStreamAnalyzer to process chunks as they arrive and emit
// NDJSON per classification window — no buffering, no temp files.

- (BOOL)runAudioStreamWithError:(NSError **)error {
    MVAudioFormat fallback;
    fallback.sampleRate = self.sampleRate > 0 ? self.sampleRate : 16000;
    fallback.channels   = self.channels   > 0 ? self.channels   : 1;
    fallback.bitDepth   = self.bitDepth   > 0 ? self.bitDepth   : 16;

    MVAudioReader *reader = [[MVAudioReader alloc] initWithFileDescriptor:STDIN_FILENO
                                                            fallbackFormat:fallback];
    MVAudioFormat fmt = reader.format;

    AVAudioFormat *avFmt = [[AVAudioFormat alloc] initWithCommonFormat:AVAudioPCMFormatInt16
                                                            sampleRate:(double)fmt.sampleRate
                                                              channels:(AVAudioChannelCount)fmt.channels
                                                           interleaved:YES];

    SNAudioStreamAnalyzer *analyzer = [[SNAudioStreamAnalyzer alloc] initWithFormat:avFmt];

    // Build the request
    SNClassifySoundRequest *request = nil;
    if ([self.operation isEqualToString:@"classify-custom"]) {
        if (!self.modelPath.length) {
            if (error) *error = [NSError errorWithDomain:SNAErrorDomain code:40
                userInfo:@{NSLocalizedDescriptionKey: @"classify-custom requires --model <path>"}];
            return NO;
        }
        MLModel *mlModel = [MLModel modelWithContentsOfURL:[NSURL fileURLWithPath:self.modelPath]
                                                     error:error];
        if (!mlModel) return NO;
        request = [[SNClassifySoundRequest alloc] initWithMLModel:mlModel error:error];
    } else {
        if (@available(macOS 12.0, *)) {
            request = [[SNClassifySoundRequest alloc]
                initWithClassifierIdentifier:SNClassifierIdentifierVersion1 error:error];
        } else {
            if (error) *error = [NSError errorWithDomain:SNAErrorDomain code:30
                userInfo:@{NSLocalizedDescriptionKey: @"classify stream requires macOS 12.0+"}];
            return NO;
        }
    }
    if (!request) return NO;
    if (![self configureRequest:request error:error]) return NO;

    SNAStreamObserver *observer = [[SNAStreamObserver alloc] initWithTopK:self.topk];
    if (![analyzer addRequest:request withObserver:observer error:error]) return NO;

    // Feed ~250 ms chunks to the stream analyzer as they arrive
    AVAudioFrameCount bytesPerFrame = (AVAudioFrameCount)(fmt.channels * (fmt.bitDepth / 8));
    NSUInteger chunkSize = (NSUInteger)(fmt.sampleRate * bytesPerFrame / 4);

    __block AVAudioFramePosition position = 0;
    [reader readChunksOfSize:chunkSize handler:^(NSData *pcmChunk) {
        AVAudioFrameCount frameCount = (AVAudioFrameCount)(pcmChunk.length / bytesPerFrame);
        if (frameCount == 0) return;
        AVAudioPCMBuffer *buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:avFmt
                                                               frameCapacity:frameCount];
        buf.frameLength = frameCount;
        memcpy(buf.int16ChannelData[0], pcmChunk.bytes, pcmChunk.length);
        [analyzer analyzeAudioBuffer:buf atAudioFramePosition:position];
        position += frameCount;
    }];

    [analyzer completeAnalysis];
    return YES;
}

@end
