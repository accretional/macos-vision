#import "main.h"
#import "common/MVJsonEmit.h"
#import <AVFoundation/AVFoundation.h>
#import <AppKit/AppKit.h>

static NSString * const MediaErrorDomain = @"AVProcessorError";

typedef NS_ENUM(NSInteger, AVProcessorErrorCode) {
    AVProcessorErrorUnknownOp       = 1,
    AVProcessorErrorMissingInput    = 2,
    AVProcessorErrorFrameExtract    = 3,
    AVProcessorErrorImageLoad       = 4,
    AVProcessorErrorImageRasterize  = 5,
    AVProcessorErrorUnknownPreset   = 6,
    AVProcessorErrorExportRequired  = 7,
    AVProcessorErrorPresetIncompat  = 8,
    AVProcessorErrorSessionCreate   = 9,
    AVProcessorErrorNoFileTypes     = 10,
    AVProcessorErrorExportFailed    = 11,
    AVProcessorErrorConcatEmpty     = 12,
    AVProcessorErrorConcatFailed    = 13,
    AVProcessorErrorNoAudioTrack    = 14,
    AVProcessorErrorReaderFailed    = 15,
    AVProcessorErrorTTSNoText       = 16,
    AVProcessorErrorTTSFailed       = 17,
    AVProcessorErrorNoVideoTrack    = 18,
    AVProcessorErrorMixNoInputs     = 19,
    AVProcessorErrorBurnNoContent   = 20,
    AVProcessorErrorFetchFailed     = 21,
    AVProcessorErrorRetimeFactor    = 22,
    AVProcessorErrorSplitNoPoints   = 23,
};

static NSArray<NSDictionary *> *MAVCollectArtifacts(NSDictionary *obj) {
    NSMutableArray *a = [NSMutableArray array];
    NSString *out = obj[@"output"];
    if ([out isKindOfClass:[NSString class]] && out.length)
        [a addObject:MVArtifactEntry(out, @"media_output")];
    // frames operation stores results under "frames" key
    id frames = obj[@"frames"];
    if ([frames isKindOfClass:[NSArray class]]) {
        for (id t in frames) {
            if ([t isKindOfClass:[NSDictionary class]] && [t[@"path"] isKindOfClass:[NSString class]])
                [a addObject:MVArtifactEntry(t[@"path"], @"frame")];
        }
    }
    // split operation stores segments
    id segments = obj[@"segments"];
    if ([segments isKindOfClass:[NSArray class]]) {
        for (id s in segments) {
            if ([s isKindOfClass:[NSDictionary class]] && [s[@"path"] isKindOfClass:[NSString class]])
                [a addObject:MVArtifactEntry(s[@"path"], @"media_output")];
        }
    }
    NSString *p = obj[@"path"];
    if ([p isKindOfClass:[NSString class]] && p.length) {
        BOOL dup = [out isKindOfClass:[NSString class]] && [out isEqualToString:p];
        if (!dup) [a addObject:MVArtifactEntry(p, @"frame")];
    }
    return a;
}

static void MPrintJSON(id obj) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    if (data) printf("%s\n", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}

static BOOL MWriteJSON(id obj, NSURL *url, NSError **error) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:error];
    if (!data) return NO;
    [[NSFileManager defaultManager] createDirectoryAtURL:url.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

static void MWaitAssetKeys(AVAsset *asset, NSArray<NSString *> *keys) {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [asset loadValuesAsynchronouslyForKeys:keys completionHandler:^{
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 300 * NSEC_PER_SEC));
}

static NSString *MStatusString(AVKeyValueStatus st) {
    switch (st) {
        case AVKeyValueStatusLoaded: return @"loaded";
        case AVKeyValueStatusFailed: return @"failed";
        case AVKeyValueStatusCancelled: return @"cancelled";
        default: return @"unknown";
    }
}

static NSString *MPresetConstant(NSString *name) {
    NSDictionary *map = @{
        @"low":        AVAssetExportPresetLowQuality,
        @"medium":     AVAssetExportPresetMediumQuality,
        @"high":       AVAssetExportPresetHighestQuality,
        @"hevc-1080p": AVAssetExportPresetHEVC1920x1080,
        @"hevc-4k":    AVAssetExportPresetHEVC3840x2160,
        @"prores-422":  AVAssetExportPresetAppleProRes422LPCM,
        @"prores-4444": AVAssetExportPresetAppleProRes4444LPCM,
        @"m4a":         AVAssetExportPresetAppleM4A,
        @"passthrough": AVAssetExportPresetPassthrough,
    };
    return map[name.lowercaseString];
}

static NSArray<NSDictionary *> *MFormatDescriptionsSummary(NSArray *descs) {
    NSMutableArray *out = [NSMutableArray array];
    for (id obj in descs) {
        if (CFGetTypeID((__bridge CFTypeRef)obj) != CMFormatDescriptionGetTypeID()) continue;
        CMFormatDescriptionRef fmt = (__bridge CMFormatDescriptionRef)obj;
        FourCharCode type = CMFormatDescriptionGetMediaType(fmt);
        FourCharCode subtype = CMFormatDescriptionGetMediaSubType(fmt);
        char tb[5] = { (char)(type >> 24), (char)(type >> 16), (char)(type >> 8), (char)type, 0 };
        char sb[5] = { (char)(subtype >> 24), (char)(subtype >> 16), (char)(subtype >> 8), (char)subtype, 0 };
        NSMutableDictionary *one = [@{
            @"mediaType": [NSString stringWithUTF8String:tb],
            @"mediaSubType": [NSString stringWithUTF8String:sb],
        } mutableCopy];
        if (type == kCMMediaType_Video) {
            CMVideoDimensions dim = CMVideoFormatDescriptionGetDimensions(fmt);
            one[@"width"] = @(dim.width);
            one[@"height"] = @(dim.height);
        }
        [out addObject:one];
    }
    return out;
}

static NSDictionary *MMetadataItemDict(AVMetadataItem *item) {
    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    d[@"identifier"] = item.identifier ?: [NSNull null];
    if (item.stringValue) d[@"stringValue"] = item.stringValue;
    if (item.numberValue) d[@"numberValue"] = item.numberValue;
    if (item.dateValue) d[@"dateValue"] = @([item.dateValue timeIntervalSince1970]);
    return d;
}

/// Write TTS PCM buffers to linear PCM WAV.
static BOOL MTTSWritePCMSequenceToWAV(NSArray<AVAudioPCMBuffer *> *buffers,
                                       AVAudioFormat *outputFormat,
                                       NSURL *wavURL,
                                       NSError **error) {
    NSDictionary *pcmSettings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVSampleRateKey: @(outputFormat.sampleRate),
        AVNumberOfChannelsKey: @(outputFormat.channelCount),
        AVLinearPCMBitDepthKey: @16,
        AVLinearPCMIsFloatKey: @NO,
        AVLinearPCMIsBigEndianKey: @NO,
    };
    NSError *fe = nil;
    AVAudioFile *file = [[AVAudioFile alloc] initForWriting:wavURL settings:pcmSettings error:&fe];
    if (!file) { if (error) *error = fe; return NO; }
    for (AVAudioPCMBuffer *buf in buffers) {
        NSError *we = nil;
        if (![file writeFromBuffer:buf error:&we]) { if (error) *error = we; return NO; }
    }
    return YES;
}

/// Encode WAV to AAC in MPEG-4 (.m4a).
static BOOL MTTSExportWAVToM4A(NSURL *wavURL, NSURL *m4aURL, NSError **error) {
    [[NSFileManager defaultManager] removeItemAtURL:m4aURL error:nil];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:wavURL options:nil];
    MWaitAssetKeys(asset, @[@"tracks", @"duration"]);
    NSArray *ok = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    NSString *preset = AVAssetExportPresetAppleM4A;
    if (![ok containsObject:preset]) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorPresetIncompat
                             userInfo:@{NSLocalizedDescriptionKey: @"Intermediate WAV not compatible with M4A preset"}];
        return NO;
    }
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    if (!session) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorSessionCreate
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not create TTS M4A export session"}];
        return NO;
    }
    session.outputURL = m4aURL;
    NSString *fileType = session.supportedFileTypes.firstObject;
    if (!fileType) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorNoFileTypes
                             userInfo:@{NSLocalizedDescriptionKey: @"TTS M4A export: no supported output file types"}];
        return NO;
    }
    session.outputFileType = fileType;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL completed = NO;
    [session exportAsynchronouslyWithCompletionHandler:^{
        completed = (session.status == AVAssetExportSessionStatusCompleted);
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3600 * NSEC_PER_SEC));
    if (!completed) {
        if (error) *error = session.error ?: [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorExportFailed
                                               userInfo:@{NSLocalizedDescriptionKey:
                                                              [NSString stringWithFormat:@"TTS M4A export failed (status %ld)",
                                                                                         (long)session.status]}];
        return NO;
    }
    return YES;
}

/// Run an AVAssetExportSession synchronously and return YES on success.
static BOOL MRunExportSession(AVAssetExportSession *session, NSError **error) {
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL ok = YES;
    [session exportAsynchronouslyWithCompletionHandler:^{
        if (session.status != AVAssetExportSessionStatusCompleted) ok = NO;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3600 * NSEC_PER_SEC));
    if (!ok && error) {
        *error = session.error ?: [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorExportFailed
                                    userInfo:@{NSLocalizedDescriptionKey:
                                                   [NSString stringWithFormat:@"Export failed (status %ld)", (long)session.status]}];
    }
    return ok;
}

@implementation AVProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation = @"probe";
    }
    return self;
}

- (BOOL)runWithError:(NSError **)error {
    NSArray *valid = @[@"probe", @"tracks", @"meta", @"frames", @"encode",
                       @"presets", @"concat", @"waveform", @"tts", @"noise",
                       @"pitch", @"stems", @"split", @"mix", @"burn", @"fetch", @"retime"];
    if (![valid containsObject:self.operation]) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorUnknownOp
                             userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithFormat:@"Unknown operation '%@'", self.operation]}];
        return NO;
    }

    // Operations that don't need a single media-file input
    if ([self.operation isEqualToString:@"presets"]) return [self runPresets:error];
    if ([self.operation isEqualToString:@"concat"])  return [self runConcat:error];
    if ([self.operation isEqualToString:@"tts"])     return [self runTTS:error];
    if ([self.operation isEqualToString:@"mix"])     return [self runMix:error];
    if ([self.operation isEqualToString:@"fetch"])   return [self runFetch:error];

    NSURL *mediaURL = nil;
    BOOL isImage = NO;
    if (self.video.length) {
        mediaURL = [NSURL fileURLWithPath:self.video];
    } else if (self.img.length) {
        mediaURL = [NSURL fileURLWithPath:self.img];
        isImage = YES;
    } else {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorMissingInput
                             userInfo:@{NSLocalizedDescriptionKey: @"Provide --input"}];
        return NO;
    }

    if ([self.operation isEqualToString:@"frames"] && isImage) {
        return [self runFramesFromImage:mediaURL error:error];
    }

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:mediaURL
                                            options:@{ AVURLAssetPreferPreciseDurationAndTimingKey: @YES }];

    if ([self.operation isEqualToString:@"probe"])    return [self runProbe:asset error:error];
    if ([self.operation isEqualToString:@"tracks"])   return [self runTracks:asset error:error];
    if ([self.operation isEqualToString:@"meta"])     return [self runMeta:asset error:error];
    if ([self.operation isEqualToString:@"frames"])   return [self runFrames:asset error:error];
    if ([self.operation isEqualToString:@"encode"])   return [self runEncode:asset error:error];
    if ([self.operation isEqualToString:@"waveform"]) return [self runWaveform:asset error:error];
    if ([self.operation isEqualToString:@"noise"])    return [self runNoise:asset error:error];
    if ([self.operation isEqualToString:@"pitch"])    return [self runPitch:asset error:error];
    if ([self.operation isEqualToString:@"stems"])    return [self runStems:asset error:error];
    if ([self.operation isEqualToString:@"split"])    return [self runSplit:asset error:error];
    if ([self.operation isEqualToString:@"burn"])     return [self runBurn:asset error:error];
    if ([self.operation isEqualToString:@"retime"])   return [self runRetime:asset error:error];

    return YES;
}

// ── presets ───────────────────────────────────────────────────────────────────

- (BOOL)runPresets:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    NSArray *all = [AVAssetExportSession allExportPresets];
    NSMutableDictionary *root = [@{ @"operation": @"presets", @"presets": all } mutableCopy];
    if (self.video.length) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:self.video] options:nil];
        root[@"compatibleWithInput"] = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    }
    if (t0) root[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    NSDictionary *merged = MVResultByMergingArtifacts(root, MAVCollectArtifacts(root));
    NSString *inp = self.video.length ? self.video : nil;
    NSDictionary *env = MVMakeEnvelope(@"av", @"presets", inp, merged);
    return MVEmitEnvelope(env, self.jsonOutput.length ? self.jsonOutput : nil, error);
}

// ── probe ─────────────────────────────────────────────────────────────────────

- (BOOL)runProbe:(AVURLAsset *)asset error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    NSArray *keys = @[@"duration", @"preferredRate", @"preferredVolume", @"preferredTransform", @"tracks"];
    MWaitAssetKeys(asset, keys);

    NSMutableDictionary *loadStatus = [NSMutableDictionary dictionary];
    for (NSString *k in keys) {
        NSError *e = nil;
        AVKeyValueStatus st = [asset statusOfValueForKey:k error:&e];
        loadStatus[k] = @{ @"status": MStatusString(st), @"error": e.localizedDescription ?: [NSNull null] };
    }

    CMTime dur = asset.duration;
    CGAffineTransform tf = asset.preferredTransform;
    double rotationDeg = atan2(tf.b, tf.a) * 180.0 / M_PI;
    NSMutableDictionary *out = [@{
        @"operation": @"probe",
        @"durationSeconds": CMTIME_IS_NUMERIC(dur) ? @(CMTimeGetSeconds(dur)) : [NSNull null],
        @"preferredRate": @(asset.preferredRate),
        @"preferredVolume": @(asset.preferredVolume),
        @"preferredTransform": @{
            @"a": @(tf.a), @"b": @(tf.b), @"c": @(tf.c), @"d": @(tf.d),
            @"tx": @(tf.tx), @"ty": @(tf.ty),
            @"rotationDegrees": @(rotationDeg),
        },
        @"trackCount": @(asset.tracks.count),
    } mutableCopy];
    if (self.debug) {
        out[@"durationTimescale"] = @(dur.timescale);
        out[@"loadStatus"] = loadStatus;
    }
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── tracks ────────────────────────────────────────────────────────────────────

- (BOOL)runTracks:(AVURLAsset *)asset error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    MWaitAssetKeys(asset, @[@"tracks"]);
    NSMutableArray *arr = [NSMutableArray array];
    for (AVAssetTrack *tr in asset.tracks) {
        CGSize sz = tr.naturalSize;
        CGAffineTransform tft = tr.preferredTransform;
        NSMutableDictionary *one = [@{
            @"mediaType": tr.mediaType ?: @"",
            @"trackID": @(tr.trackID),
            @"enabled": @(tr.isEnabled),
            @"playable": @(tr.isPlayable),
            @"estimatedDataRate": @(tr.estimatedDataRate),
            @"nominalFrameRate": @(tr.nominalFrameRate),
            @"naturalWidth": @(sz.width),
            @"naturalHeight": @(sz.height),
            @"timeRangeStart": @(CMTimeGetSeconds(tr.timeRange.start)),
            @"timeRangeDuration": @(CMTimeGetSeconds(tr.timeRange.duration)),
            @"formatDescriptions": MFormatDescriptionsSummary(tr.formatDescriptions),
            @"languageTags": ({
                NSMutableArray *lt = [NSMutableArray array];
                if (tr.extendedLanguageTag.length) [lt addObject:tr.extendedLanguageTag];
                else if (tr.languageCode.length) [lt addObject:tr.languageCode];
                lt;
            }),
        } mutableCopy];
        double tftDeg = atan2(tft.b, tft.a) * 180.0 / M_PI;
        one[@"preferredTransform"] = @{
            @"a": @(tft.a), @"b": @(tft.b), @"c": @(tft.c), @"d": @(tft.d),
            @"tx": @(tft.tx), @"ty": @(tft.ty),
            @"rotationDegrees": @(tftDeg),
        };
        [arr addObject:one];
    }
    NSMutableDictionary *out = [@{ @"operation": @"tracks", @"tracks": arr } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── meta ──────────────────────────────────────────────────────────────────────

- (BOOL)runMeta:(AVURLAsset *)asset error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    MWaitAssetKeys(asset, @[@"metadata", @"availableChapterLocales"]);

    // Metadata items
    NSMutableArray *items = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (AVMetadataItem *item in asset.metadata) {
        if (self.metaKey.length && item.identifier && ![item.identifier isEqualToString:self.metaKey]) continue;
        NSString *dedupeKey = item.identifier ?: [NSString stringWithFormat:@"%p", item];
        if ([seen containsObject:dedupeKey]) continue;
        [seen addObject:dedupeKey];
        [items addObject:MMetadataItemDict(item)];
    }

    // Chapters
    NSMutableArray *chapters = [NSMutableArray array];
    NSArray<NSLocale *> *chapterLocales = asset.availableChapterLocales;
    NSLocale *locale = chapterLocales.firstObject ?: [NSLocale currentLocale];
    NSArray<AVTimedMetadataGroup *> *groups =
        [asset chapterMetadataGroupsWithTitleLocale:locale
                       containingItemsWithCommonKeys:@[AVMetadataCommonKeyTitle]];
    for (AVTimedMetadataGroup *group in groups) {
        NSMutableDictionary *chap = [@{
            @"startSeconds":    @(CMTimeGetSeconds(group.timeRange.start)),
            @"durationSeconds": @(CMTimeGetSeconds(group.timeRange.duration)),
        } mutableCopy];
        for (AVMetadataItem *item in group.items) {
            if (item.stringValue) { chap[@"title"] = item.stringValue; break; }
        }
        [chapters addObject:chap];
    }

    NSMutableDictionary *out = [@{
        @"operation": @"meta",
        @"metadata": items,
        @"chapters": chapters,
    } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── frames ────────────────────────────────────────────────────────────────────

- (BOOL)runFrames:(AVURLAsset *)asset error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    MWaitAssetKeys(asset, @[@"tracks", @"duration"]);

    AVAssetImageGenerator *gen = [[AVAssetImageGenerator alloc] initWithAsset:asset];
    gen.appliesPreferredTrackTransform = YES;
    gen.requestedTimeToleranceBefore = kCMTimeZero;
    gen.requestedTimeToleranceAfter = kCMTimeZero;

    NSMutableArray *times = [NSMutableArray array];
    if (self.timesStr.length) {
        for (NSString *part in [self.timesStr componentsSeparatedByString:@","]) {
            NSString *t = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
            if (t.length) [times addObject:[NSValue valueWithCMTime:CMTimeMakeWithSeconds(t.doubleValue, 600)]];
        }
    } else {
        double sec = self.timeStr ? self.timeStr.doubleValue : 0;
        [times addObject:[NSValue valueWithCMTime:CMTimeMakeWithSeconds(sec, 600)]];
    }

    BOOL isMulti = self.timesStr.length > 0;
    NSURL *singleOutURL = nil;
    NSURL *destDir = nil;
    if (!isMulti && self.mediaOutput.length) {
        singleOutURL = [NSURL fileURLWithPath:self.mediaOutput];
        [[NSFileManager defaultManager] createDirectoryAtURL:singleOutURL.URLByDeletingLastPathComponent
                                 withIntermediateDirectories:YES attributes:nil error:nil];
    } else {
        destDir = self.artifactsDir.length
            ? [NSURL fileURLWithPath:self.artifactsDir]
            : [NSURL fileURLWithPath:[[NSFileManager defaultManager] currentDirectoryPath]];
        [[NSFileManager defaultManager] createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];
    }

    NSMutableArray *written = [NSMutableArray array];
    NSInteger idx = 0;
    for (NSValue *tv in times) {
        CMTime t = [tv CMTimeValue];
        NSError *e = nil;
        CGImageRef cg = [gen copyCGImageAtTime:t actualTime:NULL error:&e];
        if (!cg) {
            if (error) *error = e ?: [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorFrameExtract
                                       userInfo:@{NSLocalizedDescriptionKey: @"copyCGImageAtTime failed"}];
            return NO;
        }
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
        CGImageRelease(cg);

        NSURL *pngURL;
        if (singleOutURL) {
            pngURL = singleOutURL;
        } else if (isMulti) {
            pngURL = [destDir URLByAppendingPathComponent:
                      [NSString stringWithFormat:@"av_frame_%03ld.png", (long)(idx + 1)]];
        } else {
            pngURL = [destDir URLByAppendingPathComponent:@"av_frame.png"];
        }

        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (![png writeToURL:pngURL options:NSDataWritingAtomic error:error]) return NO;
        [written addObject:@{ @"timeSeconds": @(CMTimeGetSeconds(t)), @"path": MVRelativePath(pngURL.path) }];
        idx++;
    }

    NSMutableDictionary *out = [@{ @"operation": @"frames", @"frames": written } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

- (BOOL)runFramesFromImage:(NSURL *)imgURL error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    NSImage *img = [[NSImage alloc] initWithContentsOfURL:imgURL];
    if (!img) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorImageLoad
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not load image"}];
        return NO;
    }
    NSURL *outURL;
    if (self.mediaOutput.length) {
        outURL = [NSURL fileURLWithPath:self.mediaOutput];
    } else {
        NSURL *destDir = self.artifactsDir.length
            ? [NSURL fileURLWithPath:self.artifactsDir]
            : [NSURL fileURLWithPath:[[NSFileManager defaultManager] currentDirectoryPath]];
        outURL = [destDir URLByAppendingPathComponent:@"av_frame.png"];
    }
    [[NSFileManager defaultManager] createDirectoryAtURL:outURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];

    CGImageRef cg = [img CGImageForProposedRect:NULL context:nil hints:nil];
    if (!cg) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorImageRasterize
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not rasterize image"}];
        return NO;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (![png writeToURL:outURL options:NSDataWritingAtomic error:error]) return NO;

    NSMutableDictionary *out = [@{
        @"operation": @"frames",
        @"path": MVRelativePath(outURL.path),
        @"width": @(rep.pixelsWide),
        @"height": @(rep.pixelsHigh),
    } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    NSDictionary *merged = MVResultByMergingArtifacts(out, MAVCollectArtifacts(out));
    NSDictionary *env = MVMakeEnvelope(@"av", @"frames", imgURL.path, merged);
    if (self.jsonOutput.length) {
        return MVEmitEnvelope(env, self.jsonOutput, error);
    }
    return MVEmitEnvelope(env, nil, error);
}

// ── encode ────────────────────────────────────────────────────────────────────

- (BOOL)runEncode:(AVURLAsset *)asset error:(NSError **)error {
    NSString *presetName = self.audioOnly ? @"m4a" : (self.preset ?: @"");
    NSString *preset = MPresetConstant(presetName);
    if (!preset) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorUnknownPreset
                             userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithFormat:@"Unknown preset '%@'. Use low|medium|high|hevc-1080p|hevc-4k|prores-422|prores-4444|m4a|passthrough", presetName]}];
        return NO;
    }
    if (!self.mediaOutput.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorExportRequired
                             userInfo:@{NSLocalizedDescriptionKey: @"encode requires --output"}];
        return NO;
    }

    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    if (![compatiblePresets containsObject:preset]) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorPresetIncompat
                             userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithFormat:@"Preset '%@' not compatible with this asset", presetName]}];
        return NO;
    }

    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    if (!session) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorSessionCreate
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not create export session"}];
        return NO;
    }
    NSURL *outputURL = [NSURL fileURLWithPath:self.mediaOutput];
    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
    session.outputURL = outputURL;
    NSString *fileType = session.supportedFileTypes.firstObject;
    if (!fileType) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorNoFileTypes
                             userInfo:@{NSLocalizedDescriptionKey: @"Export session returned no supported file types"}];
        return NO;
    }
    session.outputFileType = fileType;

    if (self.timeRangeStr.length) {
        NSArray *parts = [self.timeRangeStr componentsSeparatedByString:@","];
        if (parts.count >= 2) {
            double start = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].doubleValue;
            double dur   = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].doubleValue;
            session.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(start, 600), CMTimeMakeWithSeconds(dur, 600));
        }
    }

    NSDate *t0 = self.debug ? [NSDate date] : nil;
    if (!MRunExportSession(session, error)) return NO;

    NSMutableDictionary *out = [@{
        @"operation": @"encode",
        @"output": MVRelativePath(self.mediaOutput),
        @"preset": presetName,
    } mutableCopy];
    if (self.audioOnly) out[@"audioOnly"] = @YES;
    if (self.timeRangeStr.length) out[@"timeRange"] = self.timeRangeStr;
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── concat ────────────────────────────────────────────────────────────────────

- (BOOL)runConcat:(NSError **)error {
    if (!self.videosStr.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorConcatEmpty
                             userInfo:@{NSLocalizedDescriptionKey: @"concat requires --videos <path1,path2,...>"}];
        return NO;
    }
    if (!self.mediaOutput.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorExportRequired
                             userInfo:@{NSLocalizedDescriptionKey: @"concat requires --output"}];
        return NO;
    }

    NSDate *t0 = self.debug ? [NSDate date] : nil;
    NSMutableArray<AVURLAsset *> *assets = [NSMutableArray array];
    for (NSString *raw in [self.videosStr componentsSeparatedByString:@","]) {
        NSString *p = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!p.length) continue;
        AVURLAsset *a = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:p]
                                           options:@{ AVURLAssetPreferPreciseDurationAndTimingKey: @YES }];
        MWaitAssetKeys(a, @[@"tracks", @"duration"]);
        [assets addObject:a];
    }
    if (assets.count == 0) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorConcatEmpty
                             userInfo:@{NSLocalizedDescriptionKey: @"No valid paths found in --videos"}];
        return NO;
    }

    AVMutableComposition *comp = [AVMutableComposition composition];
    CMTime insertAt = kCMTimeZero;
    for (AVURLAsset *asset in assets) {
        NSError *insertErr = nil;
        if (![comp insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration)
                           ofAsset:asset atTime:insertAt error:&insertErr]) {
            if (error) *error = insertErr;
            return NO;
        }
        insertAt = CMTimeAdd(insertAt, asset.duration);
    }

    NSString *presetConst = MPresetConstant(self.preset ?: @"medium") ?: AVAssetExportPresetMediumQuality;
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:comp presetName:presetConst];
    if (!session) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorSessionCreate
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not create export session for concat"}];
        return NO;
    }
    NSURL *outURL = [NSURL fileURLWithPath:self.mediaOutput];
    [[NSFileManager defaultManager] createDirectoryAtURL:outURL.URLByDeletingLastPathComponent
                                 withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];
    session.outputURL = outURL;
    session.outputFileType = session.supportedFileTypes.firstObject;

    if (!MRunExportSession(session, error)) return NO;

    NSMutableDictionary *out = [@{
        @"operation": @"concat",
        @"output": MVRelativePath(self.mediaOutput),
        @"inputCount": @(assets.count),
        @"durationSeconds": @(CMTimeGetSeconds(comp.duration)),
    } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── waveform ──────────────────────────────────────────────────────────────────

- (BOOL)runWaveform:(AVURLAsset *)asset error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    MWaitAssetKeys(asset, @[@"tracks"]);

    NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if (audioTracks.count == 0) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorNoAudioTrack
                             userInfo:@{NSLocalizedDescriptionKey: @"No audio tracks found in asset"}];
        return NO;
    }

    AVAssetTrack *track = audioTracks.firstObject;
    NSUInteger channelCount = 1;
    double sampleRate = 44100.0;
    if (track.formatDescriptions.count > 0) {
        CMFormatDescriptionRef fmt = (__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;
        const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt);
        if (asbd) { channelCount = (NSUInteger)asbd->mChannelsPerFrame; sampleRate = asbd->mSampleRate; }
    }

    NSError *readerErr = nil;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&readerErr];
    if (!reader) { if (error) *error = readerErr; return NO; }

    NSDictionary *outputSettings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey: @16,
        AVLinearPCMIsFloatKey: @NO,
        AVLinearPCMIsBigEndianKey: @NO,
        AVLinearPCMIsNonInterleaved: @NO,
    };
    AVAssetReaderTrackOutput *trackOutput =
        [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:outputSettings];
    [reader addOutput:trackOutput];
    if (![reader startReading]) { if (error) *error = reader.error; return NO; }

    NSMutableData *rawData = [NSMutableData data];
    while (reader.status == AVAssetReaderStatusReading) {
        CMSampleBufferRef sampleBuf = [trackOutput copyNextSampleBuffer];
        if (!sampleBuf) break;
        CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuf);
        if (block) {
            size_t len = CMBlockBufferGetDataLength(block);
            NSMutableData *chunk = [NSMutableData dataWithLength:len];
            CMBlockBufferCopyDataBytes(block, 0, len, chunk.mutableBytes);
            [rawData appendData:chunk];
        }
        CFRelease(sampleBuf);
    }
    if (reader.status == AVAssetReaderStatusFailed) { if (error) *error = reader.error; return NO; }

    const NSInteger TARGET_POINTS = 1000;
    NSUInteger totalFrames = rawData.length / (sizeof(int16_t) * channelCount);
    NSInteger stride = MAX(1, (NSInteger)(totalFrames / TARGET_POINTS));
    int16_t *samples = (int16_t *)rawData.bytes;

    NSMutableArray *channels = [NSMutableArray array];
    for (NSUInteger ch = 0; ch < channelCount; ch++) [channels addObject:[NSMutableArray array]];
    for (NSUInteger frame = 0; frame < totalFrames; frame += (NSUInteger)stride) {
        for (NSUInteger ch = 0; ch < channelCount; ch++) {
            int16_t s = samples[frame * channelCount + ch];
            [channels[ch] addObject:@(s / 32768.0)];
        }
    }

    NSMutableDictionary *out = [@{
        @"operation": @"waveform",
        @"channels": channels,
        @"channelCount": @(channelCount),
        @"sampleRate": @(sampleRate),
        @"totalFrames": @(totalFrames),
        @"samplesPerChannel": @([(NSArray *)channels[0] count]),
    } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── tts ───────────────────────────────────────────────────────────────────────

- (BOOL)runTTS:(NSError **)error {
    NSString *txt = self.text;
    if (!txt.length && self.inputFile.length) {
        NSError *readErr = nil;
        txt = [NSString stringWithContentsOfFile:self.inputFile encoding:NSUTF8StringEncoding error:&readErr];
        if (!txt) { if (error) *error = readErr; return NO; }
    }
    if (!txt.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorTTSNoText
                             userInfo:@{NSLocalizedDescriptionKey: @"tts requires --text or --input"}];
        return NO;
    }
    if (!self.mediaOutput.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorExportRequired
                             userInfo:@{NSLocalizedDescriptionKey: @"tts requires --output"}];
        return NO;
    }

    NSDate *t0 = self.debug ? [NSDate date] : nil;

    AVSpeechUtterance *utterance = [AVSpeechUtterance speechUtteranceWithString:txt];
    if (self.voice.length) {
        AVSpeechSynthesisVoice *v = [AVSpeechSynthesisVoice voiceWithIdentifier:self.voice];
        if (v) utterance.voice = v;
    }

    AVSpeechSynthesizer *synth = [[AVSpeechSynthesizer alloc] init];
    __block AVAudioFormat *outputFormat = nil;
    __block NSMutableArray<AVAudioPCMBuffer *> *buffers = [NSMutableArray array];
    __block BOOL done = NO;

    [synth writeUtterance:utterance toBufferCallback:^(AVAudioBuffer *buffer) {
        if (!buffer) { done = YES; return; }
        if ([buffer isKindOfClass:[AVAudioPCMBuffer class]]) {
            AVAudioPCMBuffer *pcm = (AVAudioPCMBuffer *)buffer;
            if (!outputFormat) outputFormat = pcm.format;
            if (pcm.frameLength > 0) [buffers addObject:pcm];
            else done = YES;
        }
    }];

    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:300.0];
    while (!done && [deadline timeIntervalSinceNow] > 0) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
    }

    if (!outputFormat || buffers.count == 0) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorTTSFailed
                             userInfo:@{NSLocalizedDescriptionKey: @"TTS synthesis produced no audio"}];
        return NO;
    }

    NSString *mediaPath = self.mediaOutput;
    NSString *ext = mediaPath.pathExtension.lowercaseString;
    if (!ext.length) { mediaPath = [mediaPath stringByAppendingPathExtension:@"m4a"]; ext = @"m4a"; }
    else if ([ext isEqualToString:@"caf"]) {
        mediaPath = [[mediaPath stringByDeletingPathExtension] stringByAppendingPathExtension:@"m4a"];
        ext = @"m4a";
    }

    NSURL *outURL = [NSURL fileURLWithPath:mediaPath];
    [[NSFileManager defaultManager] createDirectoryAtURL:outURL.URLByDeletingLastPathComponent
                                 withIntermediateDirectories:YES attributes:nil error:nil];

    BOOL wantPCM = [ext isEqualToString:@"aiff"] || [ext isEqualToString:@"aif"] || [ext isEqualToString:@"wav"];
    if (wantPCM) {
        if (!MTTSWritePCMSequenceToWAV(buffers, outputFormat, outURL, error)) return NO;
    } else {
        NSString *tmpName = [[NSUUID UUID].UUIDString stringByAppendingPathExtension:@"wav"];
        NSURL *tmpWav = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:tmpName]];
        [[NSFileManager defaultManager] removeItemAtURL:tmpWav error:nil];
        if (!MTTSWritePCMSequenceToWAV(buffers, outputFormat, tmpWav, error)) return NO;
        if (!MTTSExportWAVToM4A(tmpWav, outURL, error)) {
            [[NSFileManager defaultManager] removeItemAtURL:tmpWav error:nil];
            return NO;
        }
        [[NSFileManager defaultManager] removeItemAtURL:tmpWav error:nil];
    }

    NSMutableDictionary *out = [@{
        @"operation": @"tts",
        @"output": MVRelativePath(mediaPath),
        @"characterCount": @(txt.length),
    } mutableCopy];
    if (self.voice.length) out[@"voice"] = self.voice;
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── noise ─────────────────────────────────────────────────────────────────────

- (BOOL)runNoise:(AVURLAsset *)asset error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    MWaitAssetKeys(asset, @[@"tracks"]);

    NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if (audioTracks.count == 0) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorNoAudioTrack
                             userInfo:@{NSLocalizedDescriptionKey: @"No audio tracks found in asset"}];
        return NO;
    }

    AVAssetTrack *track = audioTracks.firstObject;
    NSUInteger channelCount = 1;
    double sampleRate = 44100.0;
    if (track.formatDescriptions.count > 0) {
        CMFormatDescriptionRef fmt = (__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;
        const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt);
        if (asbd) { channelCount = (NSUInteger)asbd->mChannelsPerFrame; sampleRate = asbd->mSampleRate; }
    }

    NSError *readerErr = nil;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&readerErr];
    if (!reader) { if (error) *error = readerErr; return NO; }

    NSDictionary *outputSettings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey: @32,
        AVLinearPCMIsFloatKey: @YES,
        AVLinearPCMIsBigEndianKey: @NO,
        AVLinearPCMIsNonInterleaved: @NO,
    };
    AVAssetReaderTrackOutput *trackOutput =
        [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:outputSettings];
    [reader addOutput:trackOutput];
    if (![reader startReading]) { if (error) *error = reader.error; return NO; }

    NSMutableData *rawData = [NSMutableData data];
    while (reader.status == AVAssetReaderStatusReading) {
        CMSampleBufferRef sampleBuf = [trackOutput copyNextSampleBuffer];
        if (!sampleBuf) break;
        CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuf);
        if (block) {
            size_t len = CMBlockBufferGetDataLength(block);
            NSMutableData *chunk = [NSMutableData dataWithLength:len];
            CMBlockBufferCopyDataBytes(block, 0, len, chunk.mutableBytes);
            [rawData appendData:chunk];
        }
        CFRelease(sampleBuf);
    }
    if (reader.status == AVAssetReaderStatusFailed) { if (error) *error = reader.error; return NO; }

    NSUInteger totalFrames = rawData.length / (sizeof(float) * channelCount);
    NSInteger win = (NSInteger)(sampleRate * 0.1);
    float *samples = (float *)rawData.bytes;
    NSMutableArray *windows = [NSMutableArray array];

    for (NSUInteger s = 0; s < totalFrames; s += (NSUInteger)MAX(1, win)) {
        NSUInteger e = MIN(s + (NSUInteger)MAX(1, win), totalFrames);
        NSUInteger n = e - s;
        float ssq = 0.0f;
        for (NSUInteger f = s; f < e; f++) {
            for (NSUInteger c = 0; c < channelCount; c++) {
                float v = samples[f * channelCount + c];
                ssq += v * v;
            }
        }
        float rms = sqrtf(ssq / (float)(n * channelCount));
        float db  = 20.0f * log10f(MAX(rms, 1e-5f));
        NSString *level = (db > -20) ? @"loud" : (db > -40) ? @"moderate" : @"quiet";
        [windows addObject:@{
            @"time":  @(round((double)s / sampleRate * 100.0) / 100.0),
            @"rms":   @(round(rms * 10000.0) / 10000.0),
            @"db":    @(round(db  * 10.0) / 10.0),
            @"level": level,
        }];
    }

    NSMutableDictionary *result = [@{
        @"operation":     @"noise",
        @"path":          MVRelativePath(asset.URL.path),
        @"windows":       windows,
        @"sample_rate":   @(sampleRate),
        @"channel_count": @(channelCount),
        @"window_s":      @(0.1),
    } mutableCopy];
    if (t0) result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:result error:error];
}

// ── pitch ─────────────────────────────────────────────────────────────────────

static NSString *MAVFrequencyToNote(float freq) {
    NSArray *notes = @[@"C",@"C#",@"D",@"D#",@"E",@"F",@"F#",@"G",@"G#",@"A",@"A#",@"B"];
    float semitones = 12.0f * log2f(freq / 440.0f);
    NSInteger idx   = ((NSInteger)roundf(semitones) % 12 + 12) % 12;
    NSInteger oct   = 4 + (NSInteger)roundf(semitones) / 12;
    return [NSString stringWithFormat:@"%@%ld", notes[idx], (long)oct];
}

- (BOOL)runPitch:(AVURLAsset *)asset error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    MWaitAssetKeys(asset, @[@"tracks"]);

    NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if (audioTracks.count == 0) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorNoAudioTrack
                             userInfo:@{NSLocalizedDescriptionKey: @"No audio tracks found in asset"}];
        return NO;
    }

    AVAssetTrack *track = audioTracks.firstObject;
    NSUInteger channelCount = 1;
    double sampleRate = 44100.0;
    if (track.formatDescriptions.count > 0) {
        CMFormatDescriptionRef fmt = (__bridge CMFormatDescriptionRef)track.formatDescriptions.firstObject;
        const AudioStreamBasicDescription *asbd = CMAudioFormatDescriptionGetStreamBasicDescription(fmt);
        if (asbd) { channelCount = (NSUInteger)asbd->mChannelsPerFrame; sampleRate = asbd->mSampleRate; }
    }

    NSError *readerErr = nil;
    AVAssetReader *reader = [AVAssetReader assetReaderWithAsset:asset error:&readerErr];
    if (!reader) { if (error) *error = readerErr; return NO; }

    NSDictionary *outputSettings = @{
        AVFormatIDKey: @(kAudioFormatLinearPCM),
        AVLinearPCMBitDepthKey: @32,
        AVLinearPCMIsFloatKey: @YES,
        AVLinearPCMIsBigEndianKey: @NO,
        AVLinearPCMIsNonInterleaved: @NO,
    };
    AVAssetReaderTrackOutput *trackOutput =
        [AVAssetReaderTrackOutput assetReaderTrackOutputWithTrack:track outputSettings:outputSettings];
    [reader addOutput:trackOutput];
    if (![reader startReading]) { if (error) *error = reader.error; return NO; }

    NSMutableData *rawData = [NSMutableData data];
    while (reader.status == AVAssetReaderStatusReading) {
        CMSampleBufferRef sampleBuf = [trackOutput copyNextSampleBuffer];
        if (!sampleBuf) break;
        CMBlockBufferRef block = CMSampleBufferGetDataBuffer(sampleBuf);
        if (block) {
            size_t len = CMBlockBufferGetDataLength(block);
            NSMutableData *chunk = [NSMutableData dataWithLength:len];
            CMBlockBufferCopyDataBytes(block, 0, len, chunk.mutableBytes);
            [rawData appendData:chunk];
        }
        CFRelease(sampleBuf);
    }
    if (reader.status == AVAssetReaderStatusFailed) { if (error) *error = reader.error; return NO; }

    NSUInteger totalFrames = rawData.length / (sizeof(float) * channelCount);
    float *samples = (float *)rawData.bytes;

    NSInteger hop = self.pitchHopFrames > 0 ? self.pitchHopFrames : 512;
    if (hop < 32) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorReaderFailed
                             userInfo:@{NSLocalizedDescriptionKey: @"--pitch-hop must be at least 32 audio frames"}];
        return NO;
    }
    if (hop > 1048576) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorReaderFailed
                             userInfo:@{NSLocalizedDescriptionKey: @"--pitch-hop is unreasonably large"}];
        return NO;
    }

    NSInteger win = 2048;
    NSMutableArray *pitches = [NSMutableArray array];

    for (NSInteger s = 0; s + win < (NSInteger)totalFrames; s += hop) {
        float maxCorr = 0.0f;
        NSInteger bestLag = 0;
        NSInteger lagMax = MIN(1000, win / 2);
        for (NSInteger lag = 50; lag < lagMax; lag++) {
            float corr = 0.0f;
            for (NSInteger i = 0; i < win - lag; i++) {
                float a = samples[(s + i) * (NSInteger)channelCount];
                float b = samples[(s + i + lag) * (NSInteger)channelCount];
                corr += a * b;
            }
            if (corr > maxCorr) { maxCorr = corr; bestLag = lag; }
        }
        if (bestLag > 0 && maxCorr > 0.1f) {
            float freq = (float)sampleRate / (float)bestLag;
            if (freq >= 50.0f && freq <= 2000.0f) {
                [pitches addObject:@{
                    @"time":       @(round((double)s / sampleRate * 100.0) / 100.0),
                    @"frequency":  @(round(freq * 10.0) / 10.0),
                    @"note":       MAVFrequencyToNote(freq),
                    @"confidence": @(round(maxCorr * 100.0) / 100.0),
                }];
            }
        }
    }

    NSMutableDictionary *result = [@{
        @"operation":     @"pitch",
        @"path":          MVRelativePath(asset.URL.path),
        @"frames":        pitches,
        @"sample_rate":   @(sampleRate),
        @"channel_count": @(channelCount),
        @"hop_frames":    @(hop),
    } mutableCopy];
    if (t0) result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:result error:error];
}

// ── stems ─────────────────────────────────────────────────────────────────────

- (BOOL)runStems:(AVURLAsset *)asset error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    MWaitAssetKeys(asset, @[@"tracks"]);

    NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if (audioTracks.count == 0) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorNoAudioTrack
                             userInfo:@{NSLocalizedDescriptionKey: @"No audio tracks found — cannot run stems"}];
        return NO;
    }

    NSString *srcBase = asset.URL.lastPathComponent.stringByDeletingPathExtension ?: @"audio";
    NSString *outName = [NSString stringWithFormat:@"stems_%@.m4a", srcBase];
    NSURL *outURL;
    if (self.mediaOutput.length) {
        outURL = [NSURL fileURLWithPath:self.mediaOutput];
    } else if (self.artifactsDir.length) {
        outURL = [[NSURL fileURLWithPath:self.artifactsDir] URLByAppendingPathComponent:outName];
    } else {
        outURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:outName]];
    }
    [[NSFileManager defaultManager] createDirectoryAtURL:outURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];

    NSError *afErr = nil;
    AVAudioFile *audioFile = [[AVAudioFile alloc] initForReading:asset.URL error:&afErr];
    if (!audioFile) { if (error) *error = afErr; return NO; }

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

    NSError *engErr = nil;
    if (![engine enableManualRenderingMode:AVAudioEngineManualRenderingModeOffline
                                    format:audioFile.processingFormat
                         maximumFrameCount:4096
                                     error:&engErr]) {
        if (error) *error = engErr; return NO;
    }
    NSError *startErr = nil;
    if (![engine startAndReturnError:&startErr]) { if (error) *error = startErr; return NO; }
    [player scheduleFile:audioFile atTime:nil completionHandler:nil];
    [player play];

    AVAudioFile *outFile = [[AVAudioFile alloc] initForWriting:outURL
                                                      settings:audioFile.fileFormat.settings
                                                         error:error];
    if (!outFile) { [engine stop]; return NO; }

    AVAudioPCMBuffer *renderBuf =
        [[AVAudioPCMBuffer alloc] initWithPCMFormat:engine.manualRenderingFormat frameCapacity:4096];

    while (engine.manualRenderingSampleTime < audioFile.length) {
        AVAudioFrameCount toRender =
            (AVAudioFrameCount)MIN(4096LL, audioFile.length - engine.manualRenderingSampleTime);
        NSError *renderErr = nil;
        AVAudioEngineManualRenderingStatus status =
            [engine renderOffline:toRender toBuffer:renderBuf error:&renderErr];
        if (status == AVAudioEngineManualRenderingStatusError) { if (error) *error = renderErr; break; }
        if (renderBuf.frameLength > 0) { [outFile writeFromBuffer:renderBuf error:nil]; }
        if (status == AVAudioEngineManualRenderingStatusInsufficientDataFromInputNode) break;
    }
    [player stop];
    [engine stop];

    NSMutableDictionary *result = [@{
        @"operation": @"stems",
        @"input":     MVRelativePath(asset.URL.path),
        @"output":    MVRelativePath(outURL.path),
        @"method":    @"high-pass filter (150Hz)",
        @"note":      @"macOS 15+ voiceProcessing API available for better isolation",
    } mutableCopy];
    if (t0) result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:result error:error];
}

// ── split ─────────────────────────────────────────────────────────────────────

- (BOOL)runSplit:(AVURLAsset *)asset error:(NSError **)error {
    if (!self.timesStr.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorSplitNoPoints
                             userInfo:@{NSLocalizedDescriptionKey: @"split requires --times <t1,t2,...> split points"}];
        return NO;
    }

    MWaitAssetKeys(asset, @[@"tracks", @"duration"]);
    NSDate *t0 = self.debug ? [NSDate date] : nil;

    // Build ordered split points: 0 … user times … duration
    NSMutableArray<NSNumber *> *points = [NSMutableArray arrayWithObject:@(0)];
    for (NSString *part in [self.timesStr componentsSeparatedByString:@","]) {
        NSString *s = [part stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (s.length) [points addObject:@(s.doubleValue)];
    }
    [points addObject:@(CMTimeGetSeconds(asset.duration))];

    NSString *outDir = self.mediaOutput.length ? self.mediaOutput
                     : (self.artifactsDir.length ? self.artifactsDir
                     : [[NSFileManager defaultManager] currentDirectoryPath]);
    [[NSFileManager defaultManager] createDirectoryAtPath:outDir
                                withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *presetConst = MPresetConstant(self.preset ?: @"high") ?: AVAssetExportPresetHighestQuality;
    NSMutableArray *segments = [NSMutableArray array];

    for (NSUInteger i = 0; i + 1 < points.count; i++) {
        double start = points[i].doubleValue;
        double end   = points[i + 1].doubleValue;
        if (end <= start) continue;

        CMTimeRange range = CMTimeRangeMake(CMTimeMakeWithSeconds(start, 600),
                                           CMTimeMakeWithSeconds(end - start, 600));
        NSString *segPath = [outDir stringByAppendingPathComponent:
                             [NSString stringWithFormat:@"segment_%03lu.mp4", (unsigned long)(i + 1)]];
        [[NSFileManager defaultManager] removeItemAtPath:segPath error:nil];

        AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:presetConst];
        if (!session) {
            if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorSessionCreate
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:@"Could not create session for segment %lu",
                                                                            (unsigned long)(i + 1)]}];
            return NO;
        }
        session.outputURL = [NSURL fileURLWithPath:segPath];
        session.outputFileType = AVFileTypeMPEG4;
        session.timeRange = range;

        if (!MRunExportSession(session, error)) return NO;

        [segments addObject:@{
            @"index": @(i + 1),
            @"startSeconds": @(start),
            @"endSeconds": @(end),
            @"durationSeconds": @(end - start),
            @"path": MVRelativePath(segPath),
        }];
    }

    NSMutableDictionary *out = [@{
        @"operation": @"split",
        @"segmentCount": @(segments.count),
        @"segments": segments,
    } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── mix ───────────────────────────────────────────────────────────────────────

- (BOOL)runMix:(NSError **)error {
    if (!self.inputsStr.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorMixNoInputs
                             userInfo:@{NSLocalizedDescriptionKey: @"mix requires --inputs <path1,path2,...>"}];
        return NO;
    }
    if (!self.mediaOutput.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorExportRequired
                             userInfo:@{NSLocalizedDescriptionKey: @"mix requires --output"}];
        return NO;
    }

    NSDate *t0 = self.debug ? [NSDate date] : nil;

    NSMutableArray<AVURLAsset *> *assets = [NSMutableArray array];
    for (NSString *raw in [self.inputsStr componentsSeparatedByString:@","]) {
        NSString *p = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!p.length) continue;
        AVURLAsset *a = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:p]
                                           options:@{ AVURLAssetPreferPreciseDurationAndTimingKey: @YES }];
        MWaitAssetKeys(a, @[@"tracks", @"duration"]);
        [assets addObject:a];
    }
    if (assets.count == 0) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorMixNoInputs
                             userInfo:@{NSLocalizedDescriptionKey: @"No valid paths found in --inputs"}];
        return NO;
    }

    // Lay all audio tracks starting at time zero — this mixes them simultaneously.
    AVMutableComposition *comp = [AVMutableComposition composition];
    NSMutableArray<AVMutableAudioMixInputParameters *> *mixParams = [NSMutableArray array];

    for (AVURLAsset *asset in assets) {
        NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
        if (audioTracks.count == 0) continue;

        AVMutableCompositionTrack *compTrack =
            [comp addMutableTrackWithMediaType:AVMediaTypeAudio
                             preferredTrackID:kCMPersistentTrackID_Invalid];
        NSError *insertErr = nil;
        [compTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration)
                           ofTrack:audioTracks.firstObject
                            atTime:kCMTimeZero
                             error:&insertErr];

        AVMutableAudioMixInputParameters *params =
            [AVMutableAudioMixInputParameters audioMixInputParametersWithTrack:compTrack];
        [params setVolume:1.0 atTime:kCMTimeZero];
        [mixParams addObject:params];
    }

    AVMutableAudioMix *audioMix = [AVMutableAudioMix audioMix];
    audioMix.inputParameters = mixParams;

    NSURL *outURL = [NSURL fileURLWithPath:self.mediaOutput];
    [[NSFileManager defaultManager] createDirectoryAtURL:outURL.URLByDeletingLastPathComponent
                                 withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];

    AVAssetExportSession *session =
        [[AVAssetExportSession alloc] initWithAsset:comp presetName:AVAssetExportPresetAppleM4A];
    if (!session) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorSessionCreate
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not create mix export session"}];
        return NO;
    }
    session.outputURL = outURL;
    session.outputFileType = AVFileTypeAppleM4A;
    session.audioMix = audioMix;

    if (!MRunExportSession(session, error)) return NO;

    NSMutableDictionary *out = [@{
        @"operation": @"mix",
        @"output": MVRelativePath(self.mediaOutput),
        @"inputCount": @(assets.count),
        @"durationSeconds": @(CMTimeGetSeconds(comp.duration)),
    } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── burn ──────────────────────────────────────────────────────────────────────

- (BOOL)runBurn:(AVURLAsset *)asset error:(NSError **)error {
    if (!self.text.length && !self.overlayPath.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorBurnNoContent
                             userInfo:@{NSLocalizedDescriptionKey: @"burn requires --text or --overlay <image>"}];
        return NO;
    }
    if (!self.mediaOutput.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorExportRequired
                             userInfo:@{NSLocalizedDescriptionKey: @"burn requires --output"}];
        return NO;
    }

    MWaitAssetKeys(asset, @[@"tracks", @"duration"]);
    NSDate *t0 = self.debug ? [NSDate date] : nil;

    NSArray<AVAssetTrack *> *videoTracks = [asset tracksWithMediaType:AVMediaTypeVideo];
    if (videoTracks.count == 0) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorNoVideoTrack
                             userInfo:@{NSLocalizedDescriptionKey: @"No video tracks found in asset"}];
        return NO;
    }
    AVAssetTrack *videoTrack = videoTracks.firstObject;

    // Compute render size accounting for rotation transform
    CGSize naturalSize = videoTrack.naturalSize;
    CGAffineTransform t = videoTrack.preferredTransform;
    CGRect rotatedRect = CGRectApplyAffineTransform(CGRectMake(0, 0, naturalSize.width, naturalSize.height), t);
    CGSize renderSize = CGSizeMake(fabs(rotatedRect.size.width), fabs(rotatedRect.size.height));

    // Layer hierarchy: parentLayer (flipped for macOS CA) → videoLayer + overlay layers
    CGRect videoRect = CGRectMake(0, 0, renderSize.width, renderSize.height);
    CALayer *parentLayer = [CALayer layer];
    parentLayer.frame = videoRect;
    parentLayer.geometryFlipped = YES;  // y-axis up, matching video coordinate system

    CALayer *videoLayer = [CALayer layer];
    videoLayer.frame = videoRect;
    [parentLayer addSublayer:videoLayer];

    if (self.overlayPath.length) {
        NSImage *img = [[NSImage alloc] initWithContentsOfFile:self.overlayPath];
        if (img) {
            // Top-right corner, 20% of video width
            CGFloat imgW = renderSize.width * 0.2;
            CGFloat imgH = imgW * (img.size.height / MAX(img.size.width, 1));
            CGFloat padding = renderSize.width * 0.02;
            CALayer *imgLayer = [CALayer layer];
            imgLayer.frame = CGRectMake(renderSize.width - imgW - padding,
                                        renderSize.height - imgH - padding,
                                        imgW, imgH);
            imgLayer.contents = (__bridge id)([img CGImageForProposedRect:NULL context:nil hints:nil]);
            imgLayer.opacity = 0.85f;
            [parentLayer addSublayer:imgLayer];
        }
    }

    if (self.text.length) {
        // Bottom-center, good for title burns and timecodes
        CGFloat fontSize = MAX(24.0, renderSize.height * 0.04);
        CGFloat textH = fontSize * 1.8;
        CGFloat padding = renderSize.height * 0.04;
        CATextLayer *tl = [CATextLayer layer];
        tl.string = self.text;
        tl.font = (__bridge CFTypeRef)([NSFont boldSystemFontOfSize:fontSize]);
        tl.fontSize = fontSize;
        tl.foregroundColor = [NSColor whiteColor].CGColor;
        tl.shadowOpacity = 0.9f;
        tl.shadowRadius = 3.0f;
        tl.shadowOffset = CGSizeMake(1, -1);
        tl.alignmentMode = kCAAlignmentCenter;
        tl.frame = CGRectMake(0, padding, renderSize.width, textH);
        [parentLayer addSublayer:tl];
    }

    // Video composition
    float fps = videoTrack.nominalFrameRate > 0 ? videoTrack.nominalFrameRate : 30.0f;
    AVMutableVideoComposition *videoComp = [AVMutableVideoComposition videoComposition];
    videoComp.frameDuration = CMTimeMake(1, (int32_t)round(fps));
    videoComp.renderSize = renderSize;
    videoComp.animationTool =
        [AVVideoCompositionCoreAnimationTool
         videoCompositionCoreAnimationToolWithPostProcessingAsVideoLayer:videoLayer
                                                                inLayer:parentLayer];

    AVMutableVideoCompositionInstruction *instruction =
        [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);

    AVMutableVideoCompositionLayerInstruction *layerInstruction =
        [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:videoTrack];
    [layerInstruction setTransform:t atTime:kCMTimeZero];
    instruction.layerInstructions = @[layerInstruction];
    videoComp.instructions = @[instruction];

    NSURL *outURL = [NSURL fileURLWithPath:self.mediaOutput];
    [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];

    NSString *presetConst = MPresetConstant(self.preset ?: @"high") ?: AVAssetExportPresetHighestQuality;
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:presetConst];
    if (!session) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorSessionCreate
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not create burn export session"}];
        return NO;
    }
    session.outputURL = outURL;
    session.outputFileType = AVFileTypeMPEG4;
    session.videoComposition = videoComp;

    if (!MRunExportSession(session, error)) return NO;

    NSMutableDictionary *out = [@{
        @"operation": @"burn",
        @"output": MVRelativePath(self.mediaOutput),
    } mutableCopy];
    if (self.text.length) out[@"text"] = self.text;
    if (self.overlayPath.length) out[@"overlay"] = MVRelativePath(self.overlayPath);
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── fetch ─────────────────────────────────────────────────────────────────────

- (BOOL)runFetch:(NSError **)error {
    if (!self.inputFile.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorMissingInput
                             userInfo:@{NSLocalizedDescriptionKey: @"fetch requires --input <url>"}];
        return NO;
    }
    if (!self.mediaOutput.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorExportRequired
                             userInfo:@{NSLocalizedDescriptionKey: @"fetch requires --output"}];
        return NO;
    }

    NSURL *remoteURL = [NSURL URLWithString:self.inputFile];
    if (!remoteURL || !remoteURL.scheme) {
        // Treat as a local file path (passthrough copy via AVFoundation)
        remoteURL = [NSURL fileURLWithPath:self.inputFile];
    }

    NSDate *t0 = self.debug ? [NSDate date] : nil;

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:remoteURL
                                            options:@{ AVURLAssetPreferPreciseDurationAndTimingKey: @YES }];
    MWaitAssetKeys(asset, @[@"tracks", @"duration"]);

    NSURL *outURL = [NSURL fileURLWithPath:self.mediaOutput];
    [[NSFileManager defaultManager] createDirectoryAtURL:outURL.URLByDeletingLastPathComponent
                                 withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];

    // Try passthrough first; fall back to highest quality re-encode
    NSArray *compatible = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    NSString *presetConst = [compatible containsObject:AVAssetExportPresetPassthrough]
        ? AVAssetExportPresetPassthrough
        : AVAssetExportPresetHighestQuality;

    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:presetConst];
    if (!session) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorSessionCreate
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not create fetch export session"}];
        return NO;
    }
    session.outputURL = outURL;
    NSString *fileType = session.supportedFileTypes.firstObject;
    if (!fileType) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorNoFileTypes
                             userInfo:@{NSLocalizedDescriptionKey: @"fetch: no supported output file types"}];
        return NO;
    }
    session.outputFileType = fileType;

    if (!MRunExportSession(session, error)) return NO;

    NSMutableDictionary *out = [@{
        @"operation": @"fetch",
        @"source": self.inputFile,
        @"output": MVRelativePath(self.mediaOutput),
        @"durationSeconds": @(CMTimeGetSeconds(asset.duration)),
    } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── retime ────────────────────────────────────────────────────────────────────

- (BOOL)runRetime:(AVURLAsset *)asset error:(NSError **)error {
    if (self.factor <= 0) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorRetimeFactor
                             userInfo:@{NSLocalizedDescriptionKey: @"retime requires --factor > 0 (e.g. 2.0 = 2x speed)"}];
        return NO;
    }
    if (!self.mediaOutput.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorExportRequired
                             userInfo:@{NSLocalizedDescriptionKey: @"retime requires --output"}];
        return NO;
    }

    MWaitAssetKeys(asset, @[@"tracks", @"duration"]);
    NSDate *t0 = self.debug ? [NSDate date] : nil;

    AVMutableComposition *comp = [AVMutableComposition composition];
    NSError *insertErr = nil;
    if (![comp insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration)
                       ofAsset:asset atTime:kCMTimeZero error:&insertErr]) {
        if (error) *error = insertErr;
        return NO;
    }

    CMTime originalDuration = comp.duration;
    double newSeconds = CMTimeGetSeconds(originalDuration) / self.factor;
    CMTime newDuration = CMTimeMakeWithSeconds(newSeconds, 600);

    for (AVMutableCompositionTrack *track in comp.tracks) {
        [track scaleTimeRange:CMTimeRangeMake(kCMTimeZero, originalDuration) toDuration:newDuration];
    }

    NSURL *outURL = [NSURL fileURLWithPath:self.mediaOutput];
    [[NSFileManager defaultManager] createDirectoryAtURL:outURL.URLByDeletingLastPathComponent
                                 withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:outURL error:nil];

    NSString *presetConst = MPresetConstant(self.preset ?: @"high") ?: AVAssetExportPresetHighestQuality;
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:comp presetName:presetConst];
    if (!session) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorSessionCreate
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not create retime export session"}];
        return NO;
    }
    session.outputURL = outURL;
    session.outputFileType = AVFileTypeMPEG4;

    if (!MRunExportSession(session, error)) return NO;

    NSMutableDictionary *out = [@{
        @"operation": @"retime",
        @"output": MVRelativePath(self.mediaOutput),
        @"factor": @(self.factor),
        @"originalDurationSeconds": @(CMTimeGetSeconds(originalDuration)),
        @"newDurationSeconds": @(newSeconds),
        @"note": @"audio pitch is not corrected; use a pitch-shift pass if needed",
    } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── emit ──────────────────────────────────────────────────────────────────────

- (BOOL)emit:(NSDictionary *)obj error:(NSError **)error {
    NSString *inp = self.video.length ? self.video : (self.img.length ? self.img : @"");
    NSDictionary *merged = MVResultByMergingArtifacts(obj, MAVCollectArtifacts(obj));
    NSDictionary *env = MVMakeEnvelope(@"av", self.operation, inp.length ? inp : nil, merged);

    // split: mediaOutput is the segment directory — write JSON inside it
    if ([self.operation isEqualToString:@"split"] && self.mediaOutput.length) {
        NSString *jsonPath = [self.mediaOutput stringByAppendingPathComponent:@"split.json"];
        return MVEmitEnvelope(env, jsonPath, error);
    }

    // If jsonOutput is explicitly set, use it
    if (self.jsonOutput.length) {
        return MVEmitEnvelope(env, self.jsonOutput, error);
    }

    // Operations that produce a media file: write JSON alongside it
    BOOL isMediaOutput = [self.operation isEqualToString:@"encode"] ||
                         [self.operation isEqualToString:@"concat"] ||
                         [self.operation isEqualToString:@"tts"] ||
                         [self.operation isEqualToString:@"stems"] ||
                         [self.operation isEqualToString:@"mix"] ||
                         [self.operation isEqualToString:@"burn"] ||
                         [self.operation isEqualToString:@"fetch"] ||
                         [self.operation isEqualToString:@"retime"];
    if (isMediaOutput && self.mediaOutput.length) {
        NSString *jsonPath = [[self.mediaOutput stringByDeletingPathExtension] stringByAppendingPathExtension:@"json"];
        return MVEmitEnvelope(env, jsonPath, error);
    }
    if (self.artifactsDir.length) {
        NSString *src = self.video.length ? self.video : self.img;
        NSString *base = src.length
            ? [[src.lastPathComponent stringByDeletingPathExtension] stringByAppendingPathExtension:@"json"]
            : [NSString stringWithFormat:@"%@.json", self.operation];
        return MVEmitEnvelope(env, [self.artifactsDir stringByAppendingPathComponent:base], error);
    }
    return MVEmitEnvelope(env, nil, error);
}

@end
