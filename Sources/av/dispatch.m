#import "av/main.h"
#include <unistd.h>

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
        "  probe     (default) Inspect tracks, duration, codec, and transform info\n"
        "  tracks    List all tracks with type, codec, dimensions, and frame rate\n"
        "  meta      Read embedded metadata (ID3, iTunes, QuickTime) and chapters\n"
        "  frames    Extract one or more frames as PNG images\n"
        "  encode    Re-encode or remux to a different preset; --audio-only for audio-only output\n"
        "  waveform  Generate normalised waveform sample data from audio\n"
        "  concat    Concatenate multiple video files into one\n"
        "  tts       Synthesise speech from text to an audio file\n"
        "  noise     Compute RMS noise level over 100 ms windows\n"
        "  pitch     Autocorrelation-based pitch detection with note names\n"
        "  stems     Separate vocals from background using a high-pass filter\n"
        "  presets   List available AVAssetExportSession preset names\n"
        "  split     Divide a video into segments at given timestamps\n"
        "  mix       Overlay multiple audio files into a single mixed output\n"
        "  burn      Burn text or an image watermark into a video\n"
        "  fetch     Download a remote media URL to a local file\n"
        "  retime    Change playback speed by a given factor (2.0 = 2x, 0.5 = half)\n"
        "\n"
        "OPTIONS:\n"
        "  --input <path>          Input video, audio, or image file (or URL for fetch)\n"
        "  --operation <op>        Operation to run (default: probe)\n"
        "  --output <path>         Output file or directory\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
        "  --artifacts-dir <dir>   Directory for extracted frames / waveform data\n"
        "  --preset <name>         Export preset: low|medium|high|hevc-1080p|hevc-4k|\n"
        "                          prores-422|prores-4444|m4a|passthrough\n"
        "  --audio-only            Export audio track only (encode)\n"
        "  --time <t>              Timestamp in seconds or HH:MM:SS (frames)\n"
        "  --times <t1,t2,...>     Comma-separated timestamps (frames, split)\n"
        "  --time-range <s,d>      Start and duration in seconds, comma-separated (encode)\n"
        "  --key <key>             Metadata key filter (meta)\n"
        "  --videos <p1,p2,...>    Comma-separated video paths (concat)\n"
        "  --inputs <p1,p2,...>    Comma-separated audio paths (mix)\n"
        "  --overlay <path>        Image file to burn into video (burn)\n"
        "  --text <string>         Inline text for tts or burn\n"
        "  --voice <id>            Voice identifier (tts)\n"
        "  --factor <n>            Speed multiplier, e.g. 2.0 = 2x speed (retime)\n"
        "  --pitch-hop <n>         Hop size in audio frames for pitch analysis\n"
        "  --fps <n>               Frame rate for encode S→F (MJPEG stdin → video file, default: 30)\n"
        "  --no-stream             Disable auto-detection of pipe I/O\n"
        "  --debug                 Emit processing_ms in output\n"
    );
}

BOOL MVDispatchAV(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath    = nil;
    NSString *operation    = @"probe";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSString *artifactsDir = nil;
    NSString *preset       = nil;
    NSString *timeStr      = nil;
    NSString *timesStr     = nil;
    NSString *timeRangeStr = nil;
    NSString *metaKey      = nil;
    NSString *videosStr    = nil;
    NSString *inputsStr    = nil;
    NSString *voice        = nil;
    NSString *text         = nil;
    NSString *overlayPath  = nil;
    NSInteger pitchHop     = 0;
    NSInteger fps          = 30;
    double factor          = 0.0;
    BOOL audioOnly         = NO;
    BOOL noStream          = NO;
    BOOL debug             = NO;

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
        else if ([a isEqualToString:@"--inputs"] && i+1 < (NSInteger)args.count)           { inputsStr    = args[++i]; }
        else if ([a isEqualToString:@"--voice"] && i+1 < (NSInteger)args.count)            { voice        = args[++i]; }
        else if ([a isEqualToString:@"--text"] && i+1 < (NSInteger)args.count)             { text         = args[++i]; }
        else if ([a isEqualToString:@"--overlay"] && i+1 < (NSInteger)args.count)          { overlayPath  = args[++i]; }
        else if ([a isEqualToString:@"--factor"] && i+1 < (NSInteger)args.count)           { factor       = [args[++i] doubleValue]; }
        else if ([a isEqualToString:@"--pitch-hop"] && i+1 < (NSInteger)args.count)        { pitchHop     = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--fps"] && i+1 < (NSInteger)args.count)               { fps          = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--audio-only"])                                       { audioOnly    = YES; }
        else if ([a isEqualToString:@"--no-stream"])                                        { noStream     = YES; }
        else if ([a isEqualToString:@"--debug"])                                            { debug        = YES; }
        else {
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
    p.inputsStr      = inputsStr;
    p.voice          = voice;
    p.text           = text;
    p.overlayPath    = overlayPath;
    p.factor         = factor;
    p.pitchHopFrames = pitchHop;
    p.audioOnly      = audioOnly;
    p.debug          = debug;

    // Route input: tts and fetch take a raw path/URL via inputFile;
    // mix and concat use --inputs/--videos so no single input needed;
    // everything else distinguishes image vs video.
    if ([operation isEqualToString:@"tts"] || [operation isEqualToString:@"fetch"]) {
        p.inputFile = inputPath;
    } else if (![operation isEqualToString:@"mix"] && ![operation isEqualToString:@"concat"]) {
        if (inputPath.length) {
            if (looksLikeImage(inputPath)) p.img   = inputPath;
            else                           p.video = inputPath;
        }
    }

    // AV uses separate properties for media output and JSON envelope output
    p.mediaOutput = output;
    p.jsonOutput  = jsonOutput;
    p.fps         = fps;

    // Stream detection:
    //   frames F→S: stdout piped + frames operation + input file provided
    //   encode S→F: stdin piped + encode operation
    BOOL stdinPiped  = !isatty(STDIN_FILENO);
    BOOL stdoutPiped = !isatty(STDOUT_FILENO);
    if (!noStream) {
        if ([operation isEqualToString:@"frames"] && stdoutPiped && inputPath.length)
            p.streamOut = YES;
        if ([operation isEqualToString:@"encode"] && stdinPiped && !inputPath.length)
            p.stream = YES;
    }

    return [p runWithError:error];
}
