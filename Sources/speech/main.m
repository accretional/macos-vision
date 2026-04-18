#import "main.h"
#import "common/MVJsonEmit.h"
#import <Speech/Speech.h>

static NSString * const SpeechErrorDomain = @"SpeechProcessorError";

@implementation SpeechProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation = @"transcribe";
        _lang      = @"en-US";
    }
    return self;
}

// ── Public entry point ────────────────────────────────────────────────────────

- (BOOL)runWithError:(NSError **)error {
    NSArray *validOps = @[@"transcribe", @"voice-analytics", @"list-locales", @"authorize"];
    if (![validOps containsObject:self.operation]) {
        if (error) {
            *error = [NSError errorWithDomain:SpeechErrorDomain code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Unknown operation '%@'. Valid: %@",
                                                     self.operation, [validOps componentsJoinedByString:@", "]]}];
        }
        return NO;
    }

    if ([self.operation isEqualToString:@"authorize"]) {
        return [self authorizeWithError:error];
    }

    if ([self.operation isEqualToString:@"list-locales"]) {
        NSDictionary *result = [self listLocalesWithError:error];
        if (!result) return NO;
        NSDictionary *envelope = MVMakeEnvelope(@"speech", self.operation, @"", result);
        return MVEmitEnvelope(envelope, self.jsonOutput, error);
    }

    if (!self.inputPath.length) {
        if (error) {
            *error = [NSError errorWithDomain:SpeechErrorDomain code:2
                                     userInfo:@{NSLocalizedDescriptionKey: @"Provide --input <audio_file>"}];
        }
        return NO;
    }

    NSURL *fileURL = [NSURL fileURLWithPath:self.inputPath];
    NSDictionary *result = nil;

    if ([self.operation isEqualToString:@"transcribe"]) {
        result = [self transcribeURL:fileURL error:error];
    } else if ([self.operation isEqualToString:@"voice-analytics"]) {
        result = [self voiceAnalyticsFromURL:fileURL error:error];
    }

    if (!result) return NO;

    NSDictionary *envelope = MVMakeEnvelope(@"speech", self.operation, self.inputPath, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── authorize ─────────────────────────────────────────────────────────────────
//
// On macOS 26+, TCC resolves the "responsible process" (the IDE or terminal that
// launched this CLI tool) when requestAuthorization: is called. No terminal app
// declares NSSpeechRecognitionUsageDescription, so TCC sends SIGKILL before the
// dialog can appear — the callback is never reached. The fix is a one-time manual
// grant via System Settings, after which authorizationStatus returns .authorized
// and no further dialog is ever needed.

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
        // Fall through to open System Settings anyway.
    }
    if (status == SFSpeechRecognizerAuthorizationStatusRestricted) {
        if (error) {
            *error = [NSError errorWithDomain:SpeechErrorDomain code:15
                userInfo:@{NSLocalizedDescriptionKey:
                    @"Speech recognition is restricted on this device (MDM policy)."}];
        }
        return NO;
    }

    // Open System Settings → Privacy & Security → Speech Recognition.
    // The user adds this binary via the "+" button and toggles it on.
    NSURL *settingsURL = [NSURL URLWithString:
        @"x-apple.systempreferences:com.apple.preference.security?Privacy_SpeechRecognition"];
    NSTask *task = [[NSTask alloc] init];
    task.launchPath = @"/usr/bin/open";
    task.arguments  = @[settingsURL.absoluteString];
    [task launch];

    fprintf(stdout,
        "\nSystem Settings is opening to Privacy & Security → Speech Recognition.\n\n"
        "To authorize macos-vision:\n"
        "  1. Click the lock icon and authenticate if prompted.\n"
        "  2. Click the '+' button.\n"
        "  3. Navigate to and select this binary:\n"
        "     %s\n"
        "  4. Toggle it ON.\n\n"
        "Then re-run your speech command.\n",
        [[NSProcessInfo processInfo].arguments[0] UTF8String]);

    return YES;
}

- (BOOL)checkAuthorizationWithError:(NSError **)error {
    SFSpeechRecognizerAuthorizationStatus status = [SFSpeechRecognizer authorizationStatus];

    // On macOS 26+, calling requestAuthorization: from a CLI tool crashes when the
    // kernel's "responsible process" (e.g. an IDE) lacks NSSpeechRecognitionUsageDescription.
    // TCC sends SIGKILL before the callback fires — it cannot be caught.
    // Instead, surface a clear error so the user can pre-authorize via System Settings.
    if (status == SFSpeechRecognizerAuthorizationStatusNotDetermined) {
        if (error) {
            *error = [NSError errorWithDomain:SpeechErrorDomain code:10
                userInfo:@{NSLocalizedDescriptionKey:
                    @"Speech recognition has not been authorized yet. "
                     "Run: macos-vision speech --operation authorize"}];
        }
        return NO;
    }

    if (status != SFSpeechRecognizerAuthorizationStatusAuthorized) {
        NSString *reason;
        if (status == SFSpeechRecognizerAuthorizationStatusDenied) {
            reason = @"Speech recognition access was denied. Enable it in System Settings → Privacy & Security → Speech Recognition.";
        } else if (status == SFSpeechRecognizerAuthorizationStatusRestricted) {
            reason = @"Speech recognition is restricted on this device (MDM policy).";
        } else {
            reason = @"Speech recognition not authorized.";
        }
        if (error) {
            *error = [NSError errorWithDomain:SpeechErrorDomain code:10
                                     userInfo:@{NSLocalizedDescriptionKey: reason}];
        }
        return NO;
    }
    return YES;
}

// ── Recognizer factory ────────────────────────────────────────────────────────

- (nullable SFSpeechRecognizer *)recognizerWithError:(NSError **)error {
    SFSpeechRecognizer *rec =
        [[SFSpeechRecognizer alloc] initWithLocale:[NSLocale localeWithLocaleIdentifier:self.lang]];
    if (!rec) {
        if (error) {
            *error = [NSError errorWithDomain:SpeechErrorDomain code:11
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Unsupported locale: %@", self.lang]}];
        }
        return nil;
    }
    if (!rec.isAvailable) {
        if (error) {
            *error = [NSError errorWithDomain:SpeechErrorDomain code:12
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:@"Speech recognizer not available for locale: %@", self.lang]}];
        }
        return nil;
    }
    return rec;
}

// ── list-locales ──────────────────────────────────────────────────────────────

- (nullable NSDictionary *)listLocalesWithError:(NSError **)error {
    (void)error;
    NSSet<NSLocale *> *supported = [SFSpeechRecognizer supportedLocales];
    NSMutableArray<NSString *> *identifiers = [NSMutableArray array];
    for (NSLocale *locale in supported) {
        [identifiers addObject:locale.localeIdentifier];
    }
    [identifiers sortUsingSelector:@selector(compare:)];
    return @{
        @"count":   @(identifiers.count),
        @"locales": identifiers,
    };
}

// ── transcribe ────────────────────────────────────────────────────────────────

- (nullable NSDictionary *)transcribeURL:(NSURL *)url error:(NSError **)error {
    if (![self checkAuthorizationWithError:error]) return nil;

    SFSpeechRecognizer *recognizer = [self recognizerWithError:error];
    if (!recognizer) return nil;

    SFSpeechURLRecognitionRequest *request = [[SFSpeechURLRecognitionRequest alloc] initWithURL:url];
    request.shouldReportPartialResults    = NO;
    request.requiresOnDeviceRecognition   = self.offline;
    if (@available(macOS 13.0, *)) {
        request.addsPunctuation = YES;
    }

    __block NSMutableArray *segments       = [NSMutableArray array];
    __block NSString       *fullText       = @"";
    __block NSError        *recognitionErr = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSDate *start = self.debug ? [NSDate date] : nil;

    SFSpeechRecognitionTask *task =
        [recognizer recognitionTaskWithRequest:request
                                 resultHandler:^(SFSpeechRecognitionResult *result, NSError *err) {
            if (err) {
                recognitionErr = err;
                dispatch_semaphore_signal(sem);
                return;
            }
            if (!result || !result.isFinal) return;

            SFTranscription *tx = result.bestTranscription;
            fullText = tx.formattedString;

            for (SFTranscriptionSegment *seg in tx.segments) {
                NSMutableDictionary *entry = [@{
                    @"text":       seg.substring,
                    @"timestamp":  @(round(seg.timestamp * 1000.0) / 1000.0),
                    @"duration":   @(round(seg.duration  * 1000.0) / 1000.0),
                    @"confidence": @(seg.confidence),
                } mutableCopy];
                if (seg.alternativeSubstrings.count > 0) {
                    entry[@"alternatives"] = seg.alternativeSubstrings;
                }
                [segments addObject:entry];
            }
            dispatch_semaphore_signal(sem);
        }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    [task cancel];

    if (recognitionErr) {
        if (error) *error = recognitionErr;
        return nil;
    }

    NSMutableDictionary *result = [@{
        @"locale":     self.lang,
        @"path":       MVRelativePath(url.path),
        @"transcript": fullText,
        @"segments":   segments,
    } mutableCopy];
    if (self.debug && start) {
        result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }
    return result;
}

// ── voice-analytics ───────────────────────────────────────────────────────────

- (nullable NSDictionary *)voiceAnalyticsFromURL:(NSURL *)url error:(NSError **)error {
    if (![self checkAuthorizationWithError:error]) return nil;

    SFSpeechRecognizer *recognizer = [self recognizerWithError:error];
    if (!recognizer) return nil;

    SFSpeechURLRecognitionRequest *request = [[SFSpeechURLRecognitionRequest alloc] initWithURL:url];
    request.shouldReportPartialResults  = NO;
    request.requiresOnDeviceRecognition = YES; // voice analytics requires on-device recognition

    __block NSString  *fullText        = @"";
    __block NSDictionary *metaOut      = nil;
    __block NSError   *recognitionErr  = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    NSDate *start = self.debug ? [NSDate date] : nil;

    SFSpeechRecognitionTask *task =
        [recognizer recognitionTaskWithRequest:request
                                 resultHandler:^(SFSpeechRecognitionResult *result, NSError *err) {
            if (err) {
                recognitionErr = err;
                dispatch_semaphore_signal(sem);
                return;
            }
            if (!result || !result.isFinal) return;

            fullText = result.bestTranscription.formattedString;

            if (@available(macOS 11.3, *)) {
                SFSpeechRecognitionMetadata *meta = result.speechRecognitionMetadata;
                if (meta) {
                    NSMutableDictionary *m = [@{
                        @"speaking_rate_wpm":       @(round(meta.speakingRate * 10.0) / 10.0),
                        @"average_pause_duration_s": @(round(meta.averagePauseDuration * 1000.0) / 1000.0),
                        @"speech_start_s":           @(round(meta.speechStartTimestamp * 1000.0) / 1000.0),
                        @"speech_duration_s":        @(round(meta.speechDuration * 1000.0) / 1000.0),
                    } mutableCopy];

                    SFVoiceAnalytics *va = meta.voiceAnalytics;
                    if (va) {
                        NSDictionary *(^summarize)(SFAcousticFeature *) =
                            ^NSDictionary *(SFAcousticFeature *feat) {
                            if (!feat || feat.acousticFeatureValuePerFrame.count == 0) return nil;
                            NSArray<NSNumber *> *vals = feat.acousticFeatureValuePerFrame;
                            double sum = 0;
                            for (NSNumber *v in vals) sum += v.doubleValue;
                            double mean = sum / vals.count;
                            return @{
                                @"mean":           @(round(mean * 100000.0) / 100000.0),
                                @"frame_count":    @(vals.count),
                                @"frame_duration_s": @(feat.frameDuration),
                            };
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
                        if (analytics.count > 0) m[@"voice_analytics"] = analytics;
                    }
                    metaOut = m;
                }
            }
            dispatch_semaphore_signal(sem);
        }];

    dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);
    [task cancel];

    if (recognitionErr) {
        if (error) *error = recognitionErr;
        return nil;
    }

    NSMutableDictionary *result = [@{
        @"locale":     self.lang,
        @"path":       MVRelativePath(url.path),
        @"transcript": fullText,
        @"note":       @"voice analytics require on-device recognition (requiresOnDeviceRecognition=YES); pitch is ln(normalized_fundamental_frequency)",
    } mutableCopy];
    if (metaOut) [result addEntriesFromDictionary:metaOut];
    if (self.debug && start) {
        result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }
    return result;
}

@end
