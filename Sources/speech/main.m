#import "main.h"
#import "common/MVJsonEmit.h"
#import "common/MVAudioStream.h"
#import <Speech/Speech.h>
#import <AVFoundation/AVFoundation.h>
#include <unistd.h>
#include <fcntl.h>
#include <sys/stat.h>

static NSString * const SpeechErrorDomain = @"SpeechProcessorError";

@implementation SpeechProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation  = @"transcribe";
        _lang       = @"en-US";
        _sampleRate = 16000;
        _channels   = 1;
        _bitDepth   = 16;
    }
    return self;
}

// ── Public entry point ────────────────────────────────────────────────────────

- (BOOL)runWithError:(NSError **)error {
    NSArray *validOps = @[@"transcribe", @"voice-analytics", @"list-locales", @"authorize", @"_request-auth"];
    if (![validOps containsObject:self.operation]) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:1
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Unknown operation '%@'. Valid: %@",
                 self.operation, [validOps componentsJoinedByString:@", "]]}];
        return NO;
    }

    if ([self.operation isEqualToString:@"authorize"])
        return [self authorizeWithError:error];
    if ([self.operation isEqualToString:@"_request-auth"])
        return [self requestAuthWithError:error];

    // list-locales needs no TCC — run directly in the parent process.
    if ([self.operation isEqualToString:@"list-locales"]) {
        NSDictionary *result = [self listLocalesWithError:error];
        if (!result) return NO;
        NSDictionary *envelope = MVMakeEnvelope(@"speech", self.operation, @"", result);
        return MVEmitEnvelope(envelope, self.jsonOutput, error);
    }

    // Child side: launched via `open` so launchd is the TCC responsible process.
    if (self.appContext)
        return [self runInAppContextWithError:error];

    // Parent side: validate input, then set up pipes and relaunch.
    if ([self.operation isEqualToString:@"voice-analytics"] && self.streamIn) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:2
            userInfo:@{NSLocalizedDescriptionKey:
                @"voice-analytics requires --input <file>; streaming input is not supported"}];
        return NO;
    }
    if (!self.streamIn && !self.inputPath.length) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:2
            userInfo:@{NSLocalizedDescriptionKey:
                @"Provide --input <audio_file> (piped stdin enables stream mode automatically)"}];
        return NO;
    }

    return [self relaunchAsAppWithError:error];
}

// ── Child side ────────────────────────────────────────────────────────────────
//
// The child receives --_result-pipe (always) and either --input (file) or
// --_audio-pipe (stdin stream). It writes JSON lines to the result pipe:
//   Partial:  {"partial":true,"transcript":"…"}
//   Final:    full MVMakeEnvelope JSON object
//   Error:    {"error":"…"}
// The child always calls exit() when done.

- (BOOL)runInAppContextWithError:(NSError **)error {
    if (!self.resultPipe.length) exit(EXIT_FAILURE);

    int resultFd = open(self.resultPipe.UTF8String, O_WRONLY);
    if (resultFd < 0) exit(EXIT_FAILURE);

    BOOL ok = NO;
    if (self.audioPipe.length) {
        // Stream input: read PCM from audio pipe, use buffer recognition request.
        if ([self.operation isEqualToString:@"transcribe"])
            ok = [self transcribeAudioPipe:self.audioPipe toResultFd:resultFd error:error];
        else if (error)
            *error = [NSError errorWithDomain:SpeechErrorDomain code:2
                userInfo:@{NSLocalizedDescriptionKey:
                    @"Only 'transcribe' supports streaming input via audio pipe"}];
    } else if (self.inputPath.length) {
        // File input: hand URL directly to the framework (handles any audio format).
        NSURL *fileURL = [NSURL fileURLWithPath:self.inputPath];
        if ([self.operation isEqualToString:@"transcribe"])
            ok = [self transcribeURL:fileURL toResultFd:resultFd error:error];
        else if ([self.operation isEqualToString:@"voice-analytics"])
            ok = [self voiceAnalyticsURL:fileURL toResultFd:resultFd error:error];
    } else {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:2
            userInfo:@{NSLocalizedDescriptionKey: @"No input provided to speech child"}];
    }

    if (!ok && error && *error)
        [self writeDict:@{@"error": (*error).localizedDescription ?: @"Unknown error"}
             toResultFd:resultFd];

    close(resultFd);
    exit(ok ? EXIT_SUCCESS : EXIT_FAILURE);
}

- (void)writeDict:(NSDictionary *)dict toResultFd:(int)fd {
    NSData *d = [NSJSONSerialization dataWithJSONObject:dict options:0 error:nil];
    if (!d) return;
    write(fd, d.bytes, d.length);
    write(fd, "\n", 1);
}

// File input — SFSpeechURLRecognitionRequest.
// AVFoundation decodes any supported audio format (wav, mp3, m4a, aiff, caf…).
- (BOOL)transcribeURL:(NSURL *)url toResultFd:(int)resultFd error:(NSError **)error {
    if (![self checkAuthorizationWithError:error]) return NO;
    SFSpeechRecognizer *recognizer = [self recognizerWithError:error];
    if (!recognizer) return NO;

    SFSpeechURLRecognitionRequest *request = [[SFSpeechURLRecognitionRequest alloc] initWithURL:url];
    request.shouldReportPartialResults  = YES;
    request.requiresOnDeviceRecognition = self.offline;
    if (@available(macOS 13.0, *)) request.addsPunctuation = YES;

    __block NSMutableArray *segments   = [NSMutableArray array];
    __block NSString       *transcript = @"";
    __block NSError        *recErr     = nil;
    __block BOOL            done       = NO;
    NSDate *start = self.debug ? [NSDate date] : nil;

    [recognizer recognitionTaskWithRequest:request
                             resultHandler:^(SFSpeechRecognitionResult *result, NSError *err) {
        if (err) { recErr = err; done = YES; return; }
        if (!result) return;
        NSString *tx = result.bestTranscription.formattedString;
        if (result.isFinal) {
            transcript = tx;
            for (SFTranscriptionSegment *seg in result.bestTranscription.segments) {
                NSMutableDictionary *e = [@{
                    @"text":       seg.substring,
                    @"timestamp":  @(round(seg.timestamp * 1000.0) / 1000.0),
                    @"duration":   @(round(seg.duration  * 1000.0) / 1000.0),
                    @"confidence": @(seg.confidence),
                } mutableCopy];
                if (seg.alternativeSubstrings.count) e[@"alternatives"] = seg.alternativeSubstrings;
                [segments addObject:e];
            }
            done = YES;
        } else {
            [self writeDict:@{@"partial": @YES, @"transcript": tx} toResultFd:resultFd];
        }
    }];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120.0];
    while (!done && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    if (!done) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:30
            userInfo:@{NSLocalizedDescriptionKey: @"Speech recognition timed out after 120s."}];
        return NO;
    }
    if (recErr) { if (error) *error = recErr; return NO; }

    NSMutableDictionary *result = [@{
        @"locale":     self.lang,
        @"path":       MVRelativePath(url.path),
        @"transcript": transcript,
        @"segments":   segments,
    } mutableCopy];
    if (self.debug && start)
        result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));

    [self writeDict:MVMakeEnvelope(@"speech", self.operation, url.path, result) toResultFd:resultFd];
    return YES;
}

// File input — voice analytics (always on-device; no partial results).
- (BOOL)voiceAnalyticsURL:(NSURL *)url toResultFd:(int)resultFd error:(NSError **)error {
    if (![self checkAuthorizationWithError:error]) return NO;
    SFSpeechRecognizer *recognizer = [self recognizerWithError:error];
    if (!recognizer) return NO;

    SFSpeechURLRecognitionRequest *request = [[SFSpeechURLRecognitionRequest alloc] initWithURL:url];
    request.shouldReportPartialResults  = NO;
    request.requiresOnDeviceRecognition = YES;

    __block NSString     *transcript = @"";
    __block NSDictionary *metaOut    = nil;
    __block NSError      *recErr     = nil;
    __block BOOL          done       = NO;
    NSDate *start = self.debug ? [NSDate date] : nil;

    [recognizer recognitionTaskWithRequest:request
                             resultHandler:^(SFSpeechRecognitionResult *result, NSError *err) {
        if (err) { recErr = err; done = YES; return; }
        if (!result || !result.isFinal) return;
        transcript = result.bestTranscription.formattedString;

        if (@available(macOS 11.3, *)) {
            SFSpeechRecognitionMetadata *meta = result.speechRecognitionMetadata;
            if (meta) {
                NSMutableDictionary *m = [@{
                    @"speaking_rate_wpm":        @(round(meta.speakingRate * 10.0) / 10.0),
                    @"average_pause_duration_s": @(round(meta.averagePauseDuration * 1000.0) / 1000.0),
                    @"speech_start_s":           @(round(meta.speechStartTimestamp * 1000.0) / 1000.0),
                    @"speech_duration_s":        @(round(meta.speechDuration * 1000.0) / 1000.0),
                } mutableCopy];

                SFVoiceAnalytics *va = meta.voiceAnalytics;
                if (va) {
                    NSDictionary *(^summarize)(SFAcousticFeature *) = ^NSDictionary *(SFAcousticFeature *feat) {
                        if (!feat || feat.acousticFeatureValuePerFrame.count == 0) return nil;
                        NSArray<NSNumber *> *vals = feat.acousticFeatureValuePerFrame;
                        double sum = 0;
                        for (NSNumber *v in vals) sum += v.doubleValue;
                        double mean = sum / vals.count;
                        return @{@"mean":             @(round(mean * 100000.0) / 100000.0),
                                 @"frame_count":      @(vals.count),
                                 @"frame_duration_s": @(feat.frameDuration)};
                    };
                    NSMutableDictionary *analytics = [NSMutableDictionary dictionary];
                    NSDictionary *pitch   = summarize(va.pitch);
                    NSDictionary *jitter  = summarize(va.jitter);
                    NSDictionary *shimmer = summarize(va.shimmer);
                    NSDictionary *voicing = summarize(va.voicing);
                    if (pitch)   analytics[@"pitch_ln_normalized"] = pitch;
                    if (jitter)  analytics[@"jitter_pct"]          = jitter;
                    if (shimmer) analytics[@"shimmer_db"]          = shimmer;
                    if (voicing) analytics[@"voicing_probability"] = voicing;
                    if (analytics.count) m[@"voice_analytics"] = analytics;
                }
                metaOut = m;
            }
        }
        done = YES;
    }];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120.0];
    while (!done && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    if (!done) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:30
            userInfo:@{NSLocalizedDescriptionKey: @"Speech recognition timed out after 120s."}];
        return NO;
    }
    if (recErr) { if (error) *error = recErr; return NO; }

    NSMutableDictionary *result = [@{
        @"locale":     self.lang,
        @"path":       MVRelativePath(url.path),
        @"transcript": transcript,
        @"note":       @"voice analytics require on-device recognition (requiresOnDeviceRecognition=YES); "
                        "pitch is ln(normalized_fundamental_frequency)",
    } mutableCopy];
    if (metaOut) [result addEntriesFromDictionary:metaOut];
    if (self.debug && start)
        result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));

    [self writeDict:MVMakeEnvelope(@"speech", self.operation, url.path, result) toResultFd:resultFd];
    return YES;
}

// Stream input — SFSpeechAudioBufferRecognitionRequest.
// Audio chunks are read from the named pipe in a background thread so the main
// run loop remains free to deliver SFSpeechRecognizer callbacks.
- (BOOL)transcribeAudioPipe:(NSString *)audioPipePath toResultFd:(int)resultFd error:(NSError **)error {
    if (![self checkAuthorizationWithError:error]) return NO;
    SFSpeechRecognizer *recognizer = [self recognizerWithError:error];
    if (!recognizer) return NO;

    int audioFd = open(audioPipePath.UTF8String, O_RDONLY);
    if (audioFd < 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to open audio pipe"}];
        return NO;
    }

    MVAudioFormat fallback = {
        .sampleRate = self.sampleRate ?: 16000,
        .channels   = self.channels   ?: 1,
        .bitDepth   = self.bitDepth   ?: 16,
    };
    MVAudioReader *reader = [[MVAudioReader alloc] initWithFileDescriptor:audioFd fallbackFormat:fallback];
    MVAudioFormat fmt = reader.format;

    AVAudioFormat *avFmt = [[AVAudioFormat alloc]
        initWithCommonFormat:AVAudioPCMFormatInt16
                  sampleRate:(double)fmt.sampleRate
                    channels:(AVAudioChannelCount)fmt.channels
                 interleaved:YES];
    if (!avFmt) {
        close(audioFd);
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:11
            userInfo:@{NSLocalizedDescriptionKey: @"Unsupported audio format on pipe"}];
        return NO;
    }

    NSUInteger bytesPerFrame = fmt.channels * (fmt.bitDepth / 8);
    NSUInteger chunkBytes    = bytesPerFrame * 4096; // ~256ms at 16 kHz mono 16-bit

    SFSpeechAudioBufferRecognitionRequest *request = [[SFSpeechAudioBufferRecognitionRequest alloc] init];
    request.shouldReportPartialResults  = YES;
    request.requiresOnDeviceRecognition = self.offline;
    if (@available(macOS 13.0, *)) request.addsPunctuation = YES;

    __block NSMutableArray *segments   = [NSMutableArray array];
    __block NSString       *transcript = @"";
    __block NSError        *recErr     = nil;
    __block BOOL            done       = NO;
    NSDate *start = self.debug ? [NSDate date] : nil;

    [recognizer recognitionTaskWithRequest:request
                             resultHandler:^(SFSpeechRecognitionResult *result, NSError *err) {
        if (err) { recErr = err; done = YES; return; }
        if (!result) return;
        NSString *tx = result.bestTranscription.formattedString;
        if (result.isFinal) {
            transcript = tx;
            for (SFTranscriptionSegment *seg in result.bestTranscription.segments) {
                NSMutableDictionary *e = [@{
                    @"text":       seg.substring,
                    @"timestamp":  @(round(seg.timestamp * 1000.0) / 1000.0),
                    @"duration":   @(round(seg.duration  * 1000.0) / 1000.0),
                    @"confidence": @(seg.confidence),
                } mutableCopy];
                if (seg.alternativeSubstrings.count) e[@"alternatives"] = seg.alternativeSubstrings;
                [segments addObject:e];
            }
            done = YES;
        } else {
            // SFTranscriptionSegment.timestamp/duration are always 0 on partial results;
            // timing data is only valid on the final result. Emit transcript text only.
            [self writeDict:@{@"partial": @YES, @"transcript": tx} toResultFd:resultFd];
        }
    }];

    // Feed audio into the recognizer from a background thread — readChunksOfSize:
    // blocks on each read(), so it must not run on the main thread.
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        [reader readChunksOfSize:chunkBytes handler:^(NSData *pcmChunk) {
            AVAudioFrameCount frames = (AVAudioFrameCount)(pcmChunk.length / bytesPerFrame);
            if (!frames) return;
            AVAudioPCMBuffer *buf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:avFmt
                                                                  frameCapacity:frames];
            buf.frameLength = frames;
            memcpy(buf.int16ChannelData[0], pcmChunk.bytes, pcmChunk.length);
            [request appendAudioPCMBuffer:buf];
        }];
        [request endAudio];
        close(audioFd);
    });

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:120.0];
    while (!done && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    if (!done) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:30
            userInfo:@{NSLocalizedDescriptionKey: @"Speech recognition timed out after 120s."}];
        return NO;
    }
    if (recErr) { if (error) *error = recErr; return NO; }

    NSMutableDictionary *result = [@{
        @"locale":     self.lang,
        @"source":     @"stdin",
        @"transcript": transcript,
        @"segments":   segments,
    } mutableCopy];
    if (reader.hasMVAUHeader) result[@"hadMVAUHeader"] = @YES;
    if (self.debug && start)
        result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));

    [self writeDict:MVMakeEnvelope(@"speech", self.operation, @"stdin", result) toResultFd:resultFd];
    return YES;
}

// ── Parent side ───────────────────────────────────────────────────────────────
//
// Two named pipes bridge parent ↔ child:
//
//   audio pipe  (parent → child):  stdin bytes forwarded verbatim,
//                                  or omitted when input is a file path.
//   result pipe (child → parent):  JSON lines emitted by the child.
//
// The child is launched via `open` so that launchd — not the terminal — is the
// TCC responsible process, allowing SFSpeechRecognizer authorization to work.
//
// Output routing (parent side):
//   No --output / --json-output → stream every JSON line to stdout immediately.
//   --output / --json-output set → collect the final (non-partial) line and write to file.

- (BOOL)relaunchAsAppWithError:(NSError **)error {
    NSString *appPath = @"/Applications/macos-vision.app";
    if (![[NSFileManager defaultManager] fileExistsAtPath:appPath]) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:19
            userInfo:@{NSLocalizedDescriptionKey:
                @"Run 'make install' to install macos-vision.app, then retry."}];
        return NO;
    }

    NSString *base           = [NSUUID UUID].UUIDString;
    NSString *resultPipePath = [NSTemporaryDirectory()
        stringByAppendingPathComponent:[base stringByAppendingString:@"-result.fifo"]];
    NSString *audioPipePath  = self.streamIn
        ? [NSTemporaryDirectory() stringByAppendingPathComponent:
           [base stringByAppendingString:@"-audio.fifo"]]
        : nil;

    if (mkfifo(resultPipePath.UTF8String, 0600) != 0) {
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create result pipe"}];
        return NO;
    }
    if (audioPipePath && mkfifo(audioPipePath.UTF8String, 0600) != 0) {
        unlink(resultPipePath.UTF8String);
        if (error) *error = [NSError errorWithDomain:NSPOSIXErrorDomain code:errno
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to create audio pipe"}];
        return NO;
    }

    // Build child arguments.
    NSMutableArray *openArgs = [@[@"-n", appPath, @"--args",
                                  @"speech", @"--operation", self.operation] mutableCopy];
    if (self.inputPath.length) {
        NSString *abs = self.inputPath.isAbsolutePath ? self.inputPath
            : [[[NSFileManager defaultManager] currentDirectoryPath]
               stringByAppendingPathComponent:self.inputPath];
        [openArgs addObjectsFromArray:@[@"--input", abs]];
    }
    if (audioPipePath)
        [openArgs addObjectsFromArray:@[@"--_audio-pipe", audioPipePath]];
    [openArgs addObjectsFromArray:@[@"--_result-pipe", resultPipePath]];
    if (![self.lang isEqualToString:@"en-US"])
        [openArgs addObjectsFromArray:@[@"--audio-lang", self.lang]];
    if (self.offline)  [openArgs addObject:@"--offline"];
    if (self.debug)    [openArgs addObject:@"--debug"];
    if (self.noHeader) [openArgs addObject:@"--no-header"];
    [openArgs addObjectsFromArray:@[
        @"--sample-rate", [NSString stringWithFormat:@"%u", self.sampleRate],
        @"--channels",    [NSString stringWithFormat:@"%u", self.channels],
        @"--bit-depth",   [NSString stringWithFormat:@"%u", self.bitDepth],
    ]];
    [openArgs addObject:@"--_app-context"];

    NSTask *task = [[NSTask alloc] init];
    task.launchPath    = @"/usr/bin/open";
    task.arguments     = openArgs;
    task.standardError = [NSPipe pipe]; // suppress "GetProcessPID" noise from open

    NSError *launchErr = nil;
    if (![task launchAndReturnError:&launchErr]) {
        unlink(resultPipePath.UTF8String);
        if (audioPipePath) unlink(audioPipePath.UTF8String);
        if (error) *error = launchErr;
        return NO;
    }

    // Open result pipe for reading in a background thread — open() on a named pipe
    // blocks until the other end connects, so it must not run on the main thread.
    __block int resultFd = -1;
    dispatch_semaphore_t resultReady = dispatch_semaphore_create(0);
    dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
        resultFd = open(resultPipePath.UTF8String, O_RDONLY);
        dispatch_semaphore_signal(resultReady);
    });

    // Forward stdin → audio pipe in a background thread (stream-input mode only).
    if (audioPipePath) {
        NSString *capAudioPipe = audioPipePath;
        dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
            int wfd = open(capAudioPipe.UTF8String, O_WRONLY);
            if (wfd < 0) return;
            uint8_t buf[4096];
            ssize_t n;
            while ((n = read(STDIN_FILENO, buf, sizeof(buf))) > 0)
                write(wfd, buf, n);
            close(wfd); // pipe close → child reads EOF → calls endAudio()
        });
    }

    // Wait up to 30s for the child to open the result pipe write end.
    if (dispatch_semaphore_wait(resultReady,
            dispatch_time(DISPATCH_TIME_NOW, 30LL * NSEC_PER_SEC)) != 0 || resultFd < 0) {
        unlink(resultPipePath.UTF8String);
        if (audioPipePath) unlink(audioPipePath.UTF8String);
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:22
            userInfo:@{NSLocalizedDescriptionKey:
                @"Timed out waiting for the speech recognition process to start. "
                "Ensure macos-vision.app is installed via 'make install'."}];
        return NO;
    }

    // Read result pipe line by line until child closes its write end.
    BOOL   streamOutput = (self.jsonOutput.length == 0);
    NSData *finalLine   = nil;
    BOOL    hasError    = NO;
    NSString *errorMsg  = nil;

    NSMutableData *lineBuf = [NSMutableData data];
    uint8_t byte;
    ssize_t n;

    while ((n = read(resultFd, &byte, 1)) == 1) {
        if (byte != '\n') { [lineBuf appendBytes:&byte length:1]; continue; }
        if (!lineBuf.length) continue;

        NSData *lineData = [lineBuf copy];
        lineBuf = [NSMutableData data];

        NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];
        if ([parsed[@"error"] isKindOfClass:[NSString class]]) {
            hasError = YES; errorMsg = parsed[@"error"]; break;
        }
        if (streamOutput) {
            fwrite(lineData.bytes, 1, lineData.length, stdout);
            fputc('\n', stdout); fflush(stdout);
        } else if (![parsed[@"partial"] boolValue]) {
            finalLine = lineData; // keep overwriting; last non-partial = final result
        }
    }
    // Flush any line not terminated with \n (shouldn't happen, but be safe).
    if (lineBuf.length && !hasError) {
        NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:lineBuf options:0 error:nil];
        if ([parsed[@"error"] isKindOfClass:[NSString class]]) {
            hasError = YES; errorMsg = parsed[@"error"];
        } else if (streamOutput) {
            fwrite(lineBuf.bytes, 1, lineBuf.length, stdout);
            fputc('\n', stdout); fflush(stdout);
        } else if (![parsed[@"partial"] boolValue]) {
            finalLine = [lineBuf copy];
        }
    }

    close(resultFd);
    unlink(resultPipePath.UTF8String);
    if (audioPipePath) unlink(audioPipePath.UTF8String);

    if (hasError) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:21
            userInfo:@{NSLocalizedDescriptionKey: errorMsg ?: @"Unknown error from speech process"}];
        return NO;
    }

    if (!streamOutput) {
        if (!finalLine.length) {
            if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:20
                userInfo:@{NSLocalizedDescriptionKey:
                    @"Speech recognition produced no output — ensure permission is granted in "
                    "System Settings → Privacy & Security → Speech Recognition, "
                    "or run: macos-vision speech --operation authorize"}];
            return NO;
        }
        if (self.jsonOutput.length)
            return [finalLine writeToFile:self.jsonOutput atomically:YES];
        fwrite(finalLine.bytes, 1, finalLine.length, stdout);
        fputc('\n', stdout);
    }

    return YES;
}

// ── authorize ─────────────────────────────────────────────────────────────────
//
// On macOS 26+, TCC resolves the "responsible process" when requestAuthorization:
// is called. Terminal apps don't declare NSSpeechRecognitionUsageDescription, so
// TCC SIGKILLs the process before the dialog appears. Fix: self-relaunch via `open`
// so launchd is the responsible process. The relaunched instance calls
// requestAuthorization: safely and TCC stores the grant for the bundle ID.

- (BOOL)authorizeWithError:(NSError **)error {
    SFSpeechRecognizerAuthorizationStatus status = [SFSpeechRecognizer authorizationStatus];

    if (status == SFSpeechRecognizerAuthorizationStatusAuthorized) {
        fprintf(stdout, "Speech recognition is already authorized. No action needed.\n");
        return YES;
    }
    if (status == SFSpeechRecognizerAuthorizationStatusDenied) {
        fprintf(stdout,
            "Speech recognition was previously denied.\n"
            "Re-enable it in System Settings → Privacy & Security → Speech Recognition.\n");
        return YES;
    }
    if (status == SFSpeechRecognizerAuthorizationStatusRestricted) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:15
            userInfo:@{NSLocalizedDescriptionKey:
                @"Speech recognition is restricted on this device (MDM policy)."}];
        return NO;
    }

    NSString *appPath = @"/Applications/macos-vision.app";
    if (![[NSFileManager defaultManager] fileExistsAtPath:appPath]) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:19
            userInfo:@{NSLocalizedDescriptionKey:
                @"Run 'make install' first to install macos-vision.app, "
                "then re-run: macos-vision speech --operation authorize"}];
        return NO;
    }

    fprintf(stdout,
        "Opening macos-vision.app to request speech recognition permission...\n"
        "Approve the dialog that appears, then re-run your speech command.\n");

    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/open";
    task.arguments  = @[appPath, @"--args", @"speech", @"--operation", @"_request-auth"];
    [task launch];
    return YES;
}

// ── _request-auth (internal — invoked via `open` so launchd is responsible) ───

- (BOOL)requestAuthWithError:(NSError **)error {
    __block BOOL done = NO;
    [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus status) {
        if (status == SFSpeechRecognizerAuthorizationStatusAuthorized) {
            fprintf(stdout, "Speech recognition authorized successfully.\n");
            done = YES; exit(EXIT_SUCCESS);
        } else {
            fprintf(stderr, "Speech recognition not authorized (status %ld).\n", (long)status);
            done = YES; exit(EXIT_FAILURE);
        }
    }];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60.0];
    while (!done && [deadline timeIntervalSinceNow] > 0)
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];

    if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:17
        userInfo:@{NSLocalizedDescriptionKey: @"Authorization request timed out."}];
    return NO;
}

// ── checkAuthorizationWithError: ──────────────────────────────────────────────

- (BOOL)checkAuthorizationWithError:(NSError **)error {
    SFSpeechRecognizerAuthorizationStatus status = [SFSpeechRecognizer authorizationStatus];

    // In app context (launchd is responsible process), requestAuthorization: is safe.
    if (status == SFSpeechRecognizerAuthorizationStatusNotDetermined && self.appContext) {
        __block SFSpeechRecognizerAuthorizationStatus resolved = status;
        __block BOOL done = NO;
        [SFSpeechRecognizer requestAuthorization:^(SFSpeechRecognizerAuthorizationStatus s) {
            resolved = s; done = YES;
        }];
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:60.0];
        while (!done && [deadline timeIntervalSinceNow] > 0)
            [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                     beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        status = resolved;
    }

    if (status == SFSpeechRecognizerAuthorizationStatusNotDetermined) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:10
            userInfo:@{NSLocalizedDescriptionKey:
                @"Speech recognition has not been authorized yet. "
                "Run: macos-vision speech --operation authorize"}];
        return NO;
    }
    if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
        NSString *reason;
        if (status == SFSpeechRecognizerAuthorizationStatusDenied)
            reason = @"Speech recognition access was denied. Enable it in "
                     "System Settings → Privacy & Security → Speech Recognition.";
        else if (status == SFSpeechRecognizerAuthorizationStatusRestricted)
            reason = @"Speech recognition is restricted on this device (MDM policy).";
        else
            reason = @"Speech recognition not authorized.";
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:10
            userInfo:@{NSLocalizedDescriptionKey: reason}];
        return NO;
    }
    return YES;
}

// ── Recognizer factory ────────────────────────────────────────────────────────

- (nullable SFSpeechRecognizer *)recognizerWithError:(NSError **)error {
    SFSpeechRecognizer *rec =
        [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:self.lang]];
    if (!rec) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:11
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Unsupported locale: %@", self.lang]}];
        return nil;
    }
    if (!rec.isAvailable) {
        if (error) *error = [NSError errorWithDomain:SpeechErrorDomain code:12
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Speech recognizer not available for locale: %@", self.lang]}];
        return nil;
    }
    return rec;
}

// ── list-locales ──────────────────────────────────────────────────────────────

- (nullable NSDictionary *)listLocalesWithError:(NSError **)error {
    (void)error;
    NSSet<NSLocale *> *supported = [SFSpeechRecognizer supportedLocales];
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    for (NSLocale *locale in supported)
        [identifiers addObject:locale.localeIdentifier];
    [identifiers sortUsingSelector:@selector(compare:)];
    return @{@"count": @(identifiers.count), @"locales": identifiers};
}

@end
