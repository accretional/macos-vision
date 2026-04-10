#import "main.h"
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
};

static void MPrintJSON(id obj) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
                                                     error:nil];
    if (data) printf("%s\n", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}

static BOOL MWriteJSON(id obj, NSURL *url, NSError **error) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys
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

@implementation AVProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation = @"inspect";
    }
    return self;
}

- (BOOL)runWithError:(NSError **)error {
    NSArray *valid = @[@"inspect", @"tracks", @"metadata", @"thumbnail", @"export", @"export-audio", @"list-presets"];
    if (![valid containsObject:self.operation]) {
        if (error) *error = [NSError errorWithDomain:MediaErrorDomain code:1
                             userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithFormat:@"Unknown operation '%@'", self.operation]}];
        return NO;
    }

    if ([self.operation isEqualToString:@"list-presets"]) {
        return [self runListPresets:error];
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
                             userInfo:@{NSLocalizedDescriptionKey: @"Provide --video or --img"}];
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

    if (self.output) {
        return MWriteJSON(root, [NSURL fileURLWithPath:self.output], error);
    }
    MPrintJSON(root);
    return YES;
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
    if (self.outputDir.length) {
        destDir = [NSURL fileURLWithPath:self.outputDir];
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
        [written addObject:@{ @"timeSeconds": @(CMTimeGetSeconds(t)), @"path": pngURL.path }];
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
    if (self.outputDir.length) {
        destDir = [NSURL fileURLWithPath:self.outputDir];
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

    NSMutableDictionary *out = [@{ @"operation": @"thumbnail", @"path": outURL.path, @"width": @(rep.pixelsWide), @"height": @(rep.pixelsHigh) } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    if (self.output.length) {
        NSString *jsonPath = [[self.output stringByDeletingPathExtension] stringByAppendingPathExtension:@"json"];
        return MWriteJSON(out, [NSURL fileURLWithPath:jsonPath], error);
    }
    MPrintJSON(out);
    return YES;
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
    session.outputURL = [NSURL fileURLWithPath:self.output];
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
        @"output": self.output,
        @"preset": preset,
    } mutableCopy];
    if (t0) out[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return [self emit:out error:error];
}

- (BOOL)emit:(NSDictionary *)obj error:(NSError **)error {
    // export/export-audio: --output is the media file, JSON goes alongside it
    BOOL isExport = [self.operation isEqualToString:@"export"] || [self.operation isEqualToString:@"export-audio"];
    if (isExport && self.output) {
        NSString *jsonPath = [[self.output stringByDeletingPathExtension] stringByAppendingPathExtension:@"json"];
        return MWriteJSON(obj, [NSURL fileURLWithPath:jsonPath], error);
    }
    // --output-dir: write <source-basename>.json into the directory
    if (self.outputDir) {
        NSString *src = self.video.length ? self.video : self.img;
        NSString *base = src.length
            ? [[src.lastPathComponent stringByDeletingPathExtension] stringByAppendingPathExtension:@"json"]
            : [NSString stringWithFormat:@"%@.json", self.operation];
        NSURL *outURL = [[NSURL fileURLWithPath:self.outputDir] URLByAppendingPathComponent:base];
        return MWriteJSON(obj, outURL, error);
    }
    // --output: write JSON directly to that path
    if (self.output) {
        return MWriteJSON(obj, [NSURL fileURLWithPath:self.output], error);
    }
    MPrintJSON(obj);
    return YES;
}

@end
