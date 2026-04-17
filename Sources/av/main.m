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
    AVProcessorErrorExportFailed     = 11,
    AVProcessorErrorComposeEmpty     = 12,
    AVProcessorErrorComposeFailed    = 13,
    AVProcessorErrorNoAudioTrack     = 14,
    AVProcessorErrorReaderFailed     = 15,
    AVProcessorErrorTTSNoText        = 16,
    AVProcessorErrorTTSFailed        = 17,
};

static NSArray<NSDictionary *> *MAVCollectArtifacts(NSDictionary *obj) {
    NSMutableArray *a = [NSMutableArray array];
    NSString *out = obj[@"output"];
    if ([out isKindOfClass:[NSString class]] && out.length)
        [a addObject:MVArtifactEntry(out, @"media_output")];
    id thumbs = obj[@"thumbnails"];
    if ([thumbs isKindOfClass:[NSArray class]]) {
        for (id t in thumbs) {
            if ([t isKindOfClass:[NSDictionary class]] && [t[@"path"] isKindOfClass:[NSString class]])
                [a addObject:MVArtifactEntry(t[@"path"], @"thumbnail")];
        }
    }
    NSString *p = obj[@"path"];
    if ([p isKindOfClass:[NSString class]] && p.length) {
        BOOL dup = [out isKindOfClass:[NSString class]] && [out isEqualToString:p];
        if (!dup) [a addObject:MVArtifactEntry(p, @"thumbnail")];
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
        @"low": AVAssetExportPresetLowQuality,
        @"medium": AVAssetExportPresetMediumQuality,
        @"high": AVAssetExportPresetHighestQuality,
        @"hevc-1080p": AVAssetExportPresetHEVC1920x1080,
        @"hevc-4k": AVAssetExportPresetHEVC3840x2160,
        @"prores-422": AVAssetExportPresetAppleProRes422LPCM,
        @"prores-4444": AVAssetExportPresetAppleProRes4444LPCM,
        @"m4a": AVAssetExportPresetAppleM4A,
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

/// Write TTS PCM buffers to linear PCM WAV (used for direct .wav output and as an intermediate for AAC).
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
    if (!file) {
        if (error) *error = fe;
        return NO;
    }
    for (AVAudioPCMBuffer *buf in buffers) {
        NSError *we = nil;
        if (![file writeFromBuffer:buf error:&we]) {
            if (error) *error = we;
            return NO;
        }
    }
    return YES;
}

/// Encode WAV to AAC in MPEG-4 (.m4a) for browser `<audio>` / MediaSource compatibility.
static BOOL MTTSExportWAVToM4A(NSURL *wavURL, NSURL *m4aURL, NSError **error) {
    [[NSFileManager defaultManager] removeItemAtURL:m4aURL error:nil];
    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:wavURL options:nil];
    MWaitAssetKeys(asset, @[@"tracks", @"duration"]);
    NSArray *ok = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    NSString *preset = AVAssetExportPresetAppleM4A;
    if (![ok containsObject:preset]) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorPresetIncompat
                             userInfo:@{NSLocalizedDescriptionKey:
                                            @"Intermediate WAV is not compatible with the Apple M4A export preset"}];
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
                                                               [NSString stringWithFormat:@"TTS AAC/M4A export failed (status %ld)",
                                                                                                  (long)session.status]}];
        return NO;
    }
    return YES;
}

@implementation AVProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation = @"inspect";
    }
    return self;
}

- (BOOL)runWithError:(NSError **)error {
    NSArray *valid = @[@"inspect", @"tracks", @"metadata", @"thumbnail", @"export", @"export-audio",
                       @"list-presets", @"compose", @"waveform", @"tts", @"noise", @"pitch", @"isolate"];
    if (![valid containsObject:self.operation]) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:1
                             userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithFormat:@"Unknown operation '%@'", self.operation]}];
        return NO;
    }

    if ([self.operation isEqualToString:@"list-presets"]) {
        return [self runListPresets:error];
    }
    if ([self.operation isEqualToString:@"compose"]) {
        return [self runCompose:error];
    }
    if ([self.operation isEqualToString:@"tts"]) {
        return [self runTTS:error];
    }

    NSURL *mediaURL = nil;
    BOOL isImage = NO;
    if (self.video.length) {
        mediaURL = [NSURL fileURLWithPath:self.video];
    } else if (self.img.length) {
        mediaURL = [NSURL fileURLWithPath:self.img];
        isImage = YES;
    } else {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:2
                             userInfo:@{NSLocalizedDescriptionKey: @"Provide --input"}];
        return NO;
    }

    if ([self.operation isEqualToString:@"thumbnail"] && isImage) {
        return [self runImageThumbnail:mediaURL error:error];
    }

    AVURLAsset *asset = [AVURLAsset URLAssetWithURL:mediaURL
                                            options:@{ AVURLAssetPreferPreciseDurationAndTimingKey: @YES }];

    if ([self.operation isEqualToString:@"inspect"]) {
        return [self runInspect:asset error:error];
    }
    if ([self.operation isEqualToString:@"tracks"]) {
        return [self runTracks:asset error:error];
    }
    if ([self.operation isEqualToString:@"metadata"]) {
        return [self runMetadata:asset error:error];
    }
    if ([self.operation isEqualToString:@"thumbnail"]) {
        return [self runThumbnail:asset error:error];
    }
    if ([self.operation isEqualToString:@"export"] || [self.operation isEqualToString:@"export-audio"]) {
        return [self runExport:asset error:error];
    }
    if ([self.operation isEqualToString:@"waveform"]) {
        return [self runWaveform:asset error:error];
    }
    if ([self.operation isEqualToString:@"noise"]) {
        return [self runNoise:asset error:error];
    }
    if ([self.operation isEqualToString:@"pitch"]) {
        return [self runPitch:asset error:error];
    }
    if ([self.operation isEqualToString:@"isolate"]) {
        return [self runIsolate:asset error:error];
    }

    return YES;
}

- (BOOL)runListPresets:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    NSArray *all = [AVAssetExportSession allExportPresets];
    NSMutableDictionary *byPreset = [NSMutableDictionary dictionary];
    for (NSString *p in all) byPreset[p] = @{ @"defined": @YES };

    NSMutableDictionary *root = [@{ @"operation": @"list-presets", @"presets": all } mutableCopy];
    if (self.video.length) {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:self.video] options:nil];
        NSArray *ok = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
        root[@"compatibleWithVideo"] = ok;
    }
    if (t0) root[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));

    NSDictionary *merged = MVResultByMergingArtifacts(root, MAVCollectArtifacts(root));
    NSString *inp = self.video.length ? self.video : (self.img.length ? self.img : nil);
    NSDictionary *env = MVMakeEnvelope(@"av", @"list-presets", inp.length ? inp : nil, merged);
    if (self.output.length) {
        return MVEmitEnvelope(env, self.output, error);
    }
    return MVEmitEnvelope(env, nil, error);
}

- (BOOL)runInspect:(AVURLAsset *)asset error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    NSArray *keys = @[@"duration", @"preferredRate", @"preferredVolume", @"preferredTransform", @"tracks"];
    MWaitAssetKeys(asset, keys);

    NSMutableDictionary *d = [NSMutableDictionary dictionary];
    for (NSString *k in keys) {
        NSError *e = nil;
        AVKeyValueStatus st = [asset statusOfValueForKey:k error:&e];
        d[k] = @{ @"status": MStatusString(st), @"error": e.localizedDescription ?: [NSNull null] };
    }

    CMTime dur = asset.duration;
    CGAffineTransform tf = asset.preferredTransform;
    double rotationDeg = atan2(tf.b, tf.a) * 180.0 / M_PI;
    NSMutableDictionary *out = [@{
        @"operation": @"inspect",
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
        out[@"loadStatus"] = d;
    }

    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));

    return [self emit:out error:error];
}

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
    NSDictionary *out = @{ @"operation": @"tracks", @"tracks": arr };
    NSMutableDictionary *m = [out mutableCopy];
    if (t0) m[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:m error:error];
}

- (BOOL)runMetadata:(AVURLAsset *)asset error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    MWaitAssetKeys(asset, @[@"metadata"]);
    NSMutableArray *items = [NSMutableArray array];
    NSMutableSet *seen = [NSMutableSet set];
    for (AVMetadataItem *item in asset.metadata) {
        if (self.metaKey.length && item.identifier && ![item.identifier isEqualToString:self.metaKey]) continue;
        NSString *dedupeKey = item.identifier ?: [NSString stringWithFormat:@"%p", item];
        if ([seen containsObject:dedupeKey]) continue;
        [seen addObject:dedupeKey];
        [items addObject:MMetadataItemDict(item)];
    }
    NSMutableDictionary *out = [@{ @"operation": @"metadata", @"metadata": items } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

- (BOOL)runThumbnail:(AVURLAsset *)asset error:(NSError **)error {
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

    NSURL *destDir;
    if (self.artifactsDir.length) {
        destDir = [NSURL fileURLWithPath:self.artifactsDir];
    } else if (self.output.length) {
        destDir = [[NSURL fileURLWithPath:self.output] URLByDeletingLastPathComponent];
    } else {
        destDir = [NSURL fileURLWithPath:[[NSFileManager defaultManager] currentDirectoryPath]];
    }
    [[NSFileManager defaultManager] createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];

    NSString *base = asset.URL.lastPathComponent.stringByDeletingPathExtension ?: @"thumb";
    NSMutableArray *written = [NSMutableArray array];

    NSInteger idx = 0;
    for (NSValue *tv in times) {
        CMTime t = [tv CMTimeValue];
        NSError *e = nil;
        CGImageRef cg = [gen copyCGImageAtTime:t actualTime:NULL error:&e];
        if (!cg) {
            if (error) *error = e ?: [NSError errorWithDomain:MediaErrorDomain code:3
                                       userInfo:@{NSLocalizedDescriptionKey: @"copyCGImageAtTime failed"}];
            return NO;
        }
        NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
        CGImageRelease(cg);
        NSString *name = [NSString stringWithFormat:@"%@_%ld.png", base, (long)idx++];
        NSURL *pngURL = [destDir URLByAppendingPathComponent:name];
        NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
        if (![png writeToURL:pngURL options:NSDataWritingAtomic error:error]) return NO;
        [written addObject:@{ @"timeSeconds": @(CMTimeGetSeconds(t)), @"path": MVRelativePath(pngURL.path) }];
    }

    NSMutableDictionary *out = [@{ @"operation": @"thumbnail", @"thumbnails": written } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

- (BOOL)runImageThumbnail:(NSURL *)imgURL error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    NSImage *img = [[NSImage alloc] initWithContentsOfURL:imgURL];
    if (!img) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:4
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not load image"}];
        return NO;
    }
    NSURL *destDir;
    if (self.artifactsDir.length) {
        destDir = [NSURL fileURLWithPath:self.artifactsDir];
    } else if (self.output.length) {
        destDir = [[NSURL fileURLWithPath:self.output] URLByDeletingLastPathComponent];
    } else {
        destDir = [NSURL fileURLWithPath:[[NSFileManager defaultManager] currentDirectoryPath]];
    }
    [[NSFileManager defaultManager] createDirectoryAtURL:destDir withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *name = [[imgURL.lastPathComponent stringByDeletingPathExtension] stringByAppendingString:@"_thumb.png"];
    NSURL *outURL = self.output ? [NSURL fileURLWithPath:self.output] : [destDir URLByAppendingPathComponent:name];

    CGImageRef cg = [img CGImageForProposedRect:NULL context:nil hints:nil];
    if (!cg) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:5
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not rasterize image"}];
        return NO;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cg];
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (![png writeToURL:outURL options:NSDataWritingAtomic error:error]) return NO;

    NSMutableDictionary *out = [@{ @"operation": @"thumbnail", @"path": MVRelativePath(outURL.path), @"width": @(rep.pixelsWide), @"height": @(rep.pixelsHigh) } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    NSDictionary *merged = MVResultByMergingArtifacts(out, MAVCollectArtifacts(out));
    NSDictionary *env = MVMakeEnvelope(@"av", @"thumbnail", imgURL.path, merged);
    if (self.output.length) {
        NSString *jsonPath = [[self.output stringByDeletingPathExtension] stringByAppendingPathExtension:@"json"];
        return MVEmitEnvelope(env, jsonPath, error);
    }
    return MVEmitEnvelope(env, nil, error);
}

- (BOOL)runExport:(AVURLAsset *)asset error:(NSError **)error {
    NSString *presetName = self.preset;
    if ([self.operation isEqualToString:@"export-audio"]) {
        presetName = @"m4a";
    }
    NSString *preset = MPresetConstant(presetName ?: @"");
    if (!preset) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:6
                             userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithFormat:@"Unknown preset '%@'. Use low|medium|high|hevc-1080p|hevc-4k|prores-422|prores-4444|m4a|passthrough", presetName]}];
        return NO;
    }
    if (!self.output.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:7
                             userInfo:@{NSLocalizedDescriptionKey: @"export requires --output"}];
        return NO;
    }

    NSArray *compatiblePresets = [AVAssetExportSession exportPresetsCompatibleWithAsset:asset];
    if (![compatiblePresets containsObject:preset]) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:8
                             userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithFormat:@"Preset '%@' not compatible with this asset", preset]}];
        return NO;
    }

    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:asset presetName:preset];
    if (!session) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:9
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not create export session"}];
        return NO;
    }
    NSURL *outputURL = [NSURL fileURLWithPath:self.output];
    [[NSFileManager defaultManager] removeItemAtURL:outputURL error:nil];
    session.outputURL = outputURL;
    NSString *fileType = session.supportedFileTypes.firstObject;
    if (!fileType) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:9
                             userInfo:@{NSLocalizedDescriptionKey: @"Export session returned no supported file types"}];
        return NO;
    }
    session.outputFileType = fileType;

    if (self.timeRangeStr.length) {
        NSArray *parts = [self.timeRangeStr componentsSeparatedByString:@","];
        if (parts.count >= 2) {
            double start = [parts[0] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].doubleValue;
            double dur = [parts[1] stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]].doubleValue;
            session.timeRange = CMTimeRangeMake(CMTimeMakeWithSeconds(start, 600), CMTimeMakeWithSeconds(dur, 600));
        }
    }

    NSDate *t0 = self.debug ? [NSDate date] : nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL ok = YES;
    [session exportAsynchronouslyWithCompletionHandler:^{
        if (session.status != AVAssetExportSessionStatusCompleted) ok = NO;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3600 * NSEC_PER_SEC));

    if (!ok) {
        if (error) *error = session.error ?: [NSError errorWithDomain:MediaErrorDomain code:10
                                                userInfo:@{NSLocalizedDescriptionKey:
                                                               [NSString stringWithFormat:@"Export failed: status %ld", (long)session.status]}];
        return NO;
    }

    NSMutableDictionary *out = [@{
        @"operation": self.operation,
        @"output": MVRelativePath(self.output),
        @"preset": preset,
    } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

// ── compose ───────────────────────────────────────────────────────────────────

- (BOOL)runCompose:(NSError **)error {
    if (!self.videosStr.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorComposeEmpty
                             userInfo:@{NSLocalizedDescriptionKey: @"compose requires --videos <path1,path2,...>"}];
        return NO;
    }
    if (!self.output.length) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorExportRequired
                             userInfo:@{NSLocalizedDescriptionKey: @"compose requires --output"}];
        return NO;
    }

    NSDate *t0 = self.debug ? [NSDate date] : nil;

    NSArray<NSString *> *parts = [self.videosStr componentsSeparatedByString:@","];
    NSMutableArray<AVURLAsset *> *assets = [NSMutableArray array];
    for (NSString *raw in parts) {
        NSString *p = [raw stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
        if (!p.length) continue;
        AVURLAsset *a = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:p]
                                           options:@{ AVURLAssetPreferPreciseDurationAndTimingKey: @YES }];
        MWaitAssetKeys(a, @[@"tracks", @"duration"]);
        [assets addObject:a];
    }

    if (assets.count == 0) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorComposeEmpty
                             userInfo:@{NSLocalizedDescriptionKey: @"No valid paths found in --videos"}];
        return NO;
    }

    AVMutableComposition *comp = [AVMutableComposition composition];
    CMTime insertAt = kCMTimeZero;
    for (AVURLAsset *asset in assets) {
        CMTimeRange range = CMTimeRangeMake(kCMTimeZero, asset.duration);
        NSError *insertErr = nil;
        if (![comp insertTimeRange:range ofAsset:asset atTime:insertAt error:&insertErr]) {
            if (error) *error = insertErr;
            return NO;
        }
        insertAt = CMTimeAdd(insertAt, asset.duration);
    }

    NSString *presetConst = MPresetConstant(self.preset ?: @"medium") ?: AVAssetExportPresetMediumQuality;
    AVAssetExportSession *session = [[AVAssetExportSession alloc] initWithAsset:comp presetName:presetConst];
    if (!session) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorSessionCreate
                             userInfo:@{NSLocalizedDescriptionKey: @"Could not create export session for composition"}];
        return NO;
    }
    NSURL *compOutputURL = [NSURL fileURLWithPath:self.output];
    [[NSFileManager defaultManager] createDirectoryAtURL:compOutputURL.URLByDeletingLastPathComponent
                                 withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] removeItemAtURL:compOutputURL error:nil];
    session.outputURL = compOutputURL;
    session.outputFileType = session.supportedFileTypes.firstObject;

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block BOOL ok = YES;
    [session exportAsynchronouslyWithCompletionHandler:^{
        if (session.status != AVAssetExportSessionStatusCompleted) ok = NO;
        dispatch_semaphore_signal(sem);
    }];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 3600 * NSEC_PER_SEC));

    if (!ok) {
        if (error) *error = session.error ?: [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorComposeFailed
                                               userInfo:@{NSLocalizedDescriptionKey: @"Composition export failed"}];
        return NO;
    }

    NSMutableDictionary *out = [@{
        @"operation": @"compose",
        @"output": MVRelativePath(self.output),
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
        if (asbd) {
            channelCount = (NSUInteger)asbd->mChannelsPerFrame;
            sampleRate = asbd->mSampleRate;
        }
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

    if (![reader startReading]) {
        if (error) *error = reader.error;
        return NO;
    }

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
    if (reader.status == AVAssetReaderStatusFailed) {
        if (error) *error = reader.error;
        return NO;
    }

    const NSInteger TARGET_POINTS = 1000;
    NSUInteger totalFrames = rawData.length / (sizeof(int16_t) * channelCount);
    NSInteger stride = MAX(1, (NSInteger)(totalFrames / TARGET_POINTS));
    int16_t *samples = (int16_t *)rawData.bytes;

    NSMutableArray *channels = [NSMutableArray array];
    for (NSUInteger ch = 0; ch < channelCount; ch++) {
        [channels addObject:[NSMutableArray array]];
    }
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
    if (!self.output.length) {
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
            else done = YES;  // zero-length frame signals end
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

    // Browser-friendly default: AAC in MPEG-4 (.m4a). PCM only for explicit .wav / .aif / .aiff.
    // Extensionless --output gets .m4a
    NSString *mediaPath = self.output;
    NSString *ext = mediaPath.pathExtension.lowercaseString;
    if (!ext.length) {
        mediaPath = [mediaPath stringByAppendingPathExtension:@"m4a"];
        ext = @"m4a";
    } else if ([ext isEqualToString:@"caf"]) {
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
        // AAC cannot be written incrementally via AVAudioFile; PCM WAV → AVAssetExportSession (browser-safe .m4a).
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

// ── noise (RMS over 100 ms windows, AVAssetReader, works for video+audio) ─────

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
    NSInteger win = (NSInteger)(sampleRate * 0.1);  // 100 ms window
    float *samples = (float *)rawData.bytes;
    NSMutableArray *out = [NSMutableArray array];

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
        [out addObject:@{
            @"time":  @(round((double)s / sampleRate * 100.0) / 100.0),
            @"rms":   @(round(rms * 10000.0) / 10000.0),
            @"db":    @(round(db  * 10.0) / 10.0),
            @"level": level,
        }];
    }

    NSMutableDictionary *result = [@{
        @"operation":     @"noise",
        @"path":          MVRelativePath(asset.URL.path),
        @"windows":       out,
        @"sample_rate":   @(sampleRate),
        @"channel_count": @(channelCount),
        @"window_s":      @(0.1),
    } mutableCopy];
    if (t0) result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:result error:error];
}

// ── pitch (autocorrelation, AVAssetReader, works for video+audio) ─────────────

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

    NSInteger win    = 2048;
    NSMutableArray *pitches = [NSMutableArray array];

    for (NSInteger s = 0; s + win < (NSInteger)totalFrames; s += hop) {
        float maxCorr = 0.0f;
        NSInteger bestLag = 0;
        NSInteger lagMax = MIN(1000, win / 2);
        for (NSInteger lag = 50; lag < lagMax; lag++) {
            float corr = 0.0f;
            // Use only channel 0 (index 0 of each frame) for pitch
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

// ── isolate (high-pass filter via AVAudioEngine manual rendering) ─────────────

- (BOOL)runIsolate:(AVURLAsset *)asset error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;
    MWaitAssetKeys(asset, @[@"tracks"]);

    // Pre-check: ensure there's an audio track (gives clear error for video-only files)
    NSArray<AVAssetTrack *> *audioTracks = [asset tracksWithMediaType:AVMediaTypeAudio];
    if (audioTracks.count == 0) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:AVProcessorErrorNoAudioTrack
                             userInfo:@{NSLocalizedDescriptionKey: @"No audio tracks found — cannot isolate"}];
        return NO;
    }

    // Determine output path
    NSString *srcBase = asset.URL.lastPathComponent.stringByDeletingPathExtension ?: @"audio";
    NSString *outName = [NSString stringWithFormat:@"isolated_%@.m4a", srcBase];
    NSURL *outURL;
    if (self.output.length) {
        outURL = [NSURL fileURLWithPath:self.output];
    } else if (self.artifactsDir.length) {
        outURL = [[NSURL fileURLWithPath:self.artifactsDir] URLByAppendingPathComponent:outName];
    } else {
        outURL = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:outName]];
    }
    [[NSFileManager defaultManager] createDirectoryAtURL:outURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];

    // AVAudioFile can read audio from many container formats (mp4, mov, aiff, wav, m4a, …)
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
        @"operation": @"isolate",
        @"input":     MVRelativePath(asset.URL.path),
        @"output":    MVRelativePath(outURL.path),
        @"method":    @"high-pass filter (150Hz)",
        @"note":      @"macOS 15+ voiceProcessing API available for better isolation",
    } mutableCopy];
    if (t0) result[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:result error:error];
}

// ─────────────────────────────────────────────────────────────────────────────

- (BOOL)emit:(NSDictionary *)obj error:(NSError **)error {
    NSString *inp = self.video.length ? self.video : (self.img.length ? self.img : @"");
    NSDictionary *merged = MVResultByMergingArtifacts(obj, MAVCollectArtifacts(obj));
    NSDictionary *env = MVMakeEnvelope(@"av", self.operation, inp.length ? inp : nil, merged);

    BOOL isExport = [self.operation isEqualToString:@"export"] ||
                    [self.operation isEqualToString:@"export-audio"] ||
                    [self.operation isEqualToString:@"compose"] ||
                    [self.operation isEqualToString:@"tts"] ||
                    [self.operation isEqualToString:@"isolate"];
    if (isExport && self.output) {
        NSString *jsonPath = [[self.output stringByDeletingPathExtension] stringByAppendingPathExtension:@"json"];
        return MVEmitEnvelope(env, jsonPath, error);
    }
    if (self.artifactsDir.length) {
        NSString *src = self.video.length ? self.video : self.img;
        NSString *base = src.length
            ? [[src.lastPathComponent stringByDeletingPathExtension] stringByAppendingPathExtension:@"json"]
            : [NSString stringWithFormat:@"%@.json", self.operation];
        NSString *path = [self.artifactsDir stringByAppendingPathComponent:base];
        return MVEmitEnvelope(env, path, error);
    }
    if (self.output) {
        return MVEmitEnvelope(env, self.output, error);
    }
    return MVEmitEnvelope(env, nil, error);
}

@end
