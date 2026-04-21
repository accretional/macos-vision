#import "av/main.h"

static BOOL looksLikeImage(NSString *p) {
    if (!p.length) return NO;
    static NSSet<NSString *> *exts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exts = [NSSet setWithArray:@[@"jpg",@"jpeg",@"png",@"heic",@"heif",@"gif",@"tif",@"tiff",@"bmp",@"webp"]];
    });
    return [exts containsObject:p.pathExtension.lowercaseString];
}

static void printHelp(void) {
    printf(
        "USAGE: macos-vision av --operation <op> [options]\n"
        "\n"
        "Inspect, convert, extract, and synthesise audio and video.\n"
        "\n"
        "OPERATIONS:\n"
        "  inspect       (default) Inspect tracks, duration, and codec info\n"
        "  tracks        List all tracks in a media file\n"
        "  metadata      Read embedded metadata (ID3, iTunes, QuickTime)\n"
        "  thumbnail     Extract a frame as an image at a given time\n"
        "  export        Re-encode or remux video to a different preset/format\n"
        "  export-audio  Export the audio track only\n"
        "  frames        Extract frames at specified timestamps\n"
        "  waveform      Generate a waveform image from audio\n"
        "  compose       Concatenate multiple video files\n"
        "  tts           Text-to-speech synthesis to an audio file\n"
        "  noise         Compute RMS noise level over 100 ms windows\n"
        "  pitch         Autocorrelation-based pitch detection\n"
        "  isolate       Separate vocals from background (Apple Silicon)\n"
        "  list-presets  List available AVAssetExportSession preset names\n"
        "\n"
        "OPTIONS:\n"
        "  --input <path>          Video or audio file (or image for thumbnail)\n"
        "  --operation <op>        Operation to run (default: inspect)\n"
        "  --output <path>         Output file or directory\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
        "  --artifacts-dir <dir>   Directory for extracted frames / waveform image\n"
        "  --preset <name>         AVAssetExportSession preset (export)\n"
        "  --time <t>              Timestamp in seconds or HH:MM:SS (thumbnail)\n"
        "  --times <t1,t2,...>     Comma-separated timestamps (frames)\n"
        "  --time-range <s,d>      Start and duration in seconds, comma-separated\n"
        "  --key <key>             Metadata key to look up (metadata)\n"
        "  --videos <p1,p2,...>    Comma-separated video paths for compose\n"
        "  --voice <id>            Voice identifier for tts\n"
        "  --text <string>         Inline text for tts\n"
        "  --pitch-hop <n>         Hop size in frames for pitch analysis\n"
        "  --debug                 Emit processing_ms in output\n"
    );
}

BOOL MVDispatchAV(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath    = nil;
    NSString *operation    = @"inspect";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSString *artifactsDir = nil;
    NSString *preset       = nil;
    NSString *timeStr      = nil;
    NSString *timesStr     = nil;
    NSString *timeRangeStr = nil;
    NSString *metaKey      = nil;
    NSString *videosStr    = nil;
    NSString *voice        = nil;
    NSString *text         = nil;
    NSInteger pitchHop     = 0;
    BOOL debug = NO;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)          { inputPath    = args[++i]; }
        else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)        { operation    = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output       = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput   = args[++i]; }
        else if ([a isEqualToString:@"--artifacts-dir"] && i+1 < (NSInteger)args.count)    { artifactsDir = args[++i]; }
        else if ([a isEqualToString:@"--preset"] && i+1 < (NSInteger)args.count)           { preset       = args[++i]; }
        else if ([a isEqualToString:@"--time"] && i+1 < (NSInteger)args.count)             { timeStr      = args[++i]; }
        else if ([a isEqualToString:@"--times"] && i+1 < (NSInteger)args.count)            { timesStr     = args[++i]; }
        else if ([a isEqualToString:@"--time-range"] && i+1 < (NSInteger)args.count)       { timeRangeStr = args[++i]; }
        else if ([a isEqualToString:@"--key"] && i+1 < (NSInteger)args.count)              { metaKey      = args[++i]; }
        else if ([a isEqualToString:@"--videos"] && i+1 < (NSInteger)args.count)           { videosStr    = args[++i]; }
        else if ([a isEqualToString:@"--voice"] && i+1 < (NSInteger)args.count)            { voice        = args[++i]; }
        else if ([a isEqualToString:@"--text"] && i+1 < (NSInteger)args.count)             { text         = args[++i]; }
        else if ([a isEqualToString:@"--pitch-hop"] && i+1 < (NSInteger)args.count)        { pitchHop     = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--debug"]) { debug = YES; }
        else {
            fprintf(stderr, "av: unknown option '%s'\n", a.UTF8String);
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"av: unknown option '%@'", a]}];
            return NO;
        }
    }

    AVProcessor *p = [[AVProcessor alloc] init];
    p.operation      = operation;
    p.artifactsDir   = artifactsDir;
    p.preset         = preset;
    p.timeStr        = timeStr;
    p.timesStr       = timesStr;
    p.timeRangeStr   = timeRangeStr;
    p.metaKey        = metaKey;
    p.videosStr      = videosStr;
    p.voice          = voice;
    p.text           = text;
    p.inputFile      = inputPath;
    p.pitchHopFrames = pitchHop;
    p.debug          = debug;

    if ([operation isEqualToString:@"tts"]) {
        p.inputFile = inputPath;
    } else if (inputPath.length) {
        if (looksLikeImage(inputPath)) p.img   = inputPath;
        else                           p.video = inputPath;
    }

    // AV uses a single output property for both media and JSON
    p.output = output.length ? output : jsonOutput;

    return [p runWithError:error];
}
