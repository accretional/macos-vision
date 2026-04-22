#import "streamcapture/main.h"
#include <unistd.h>

static BOOL isDir(NSString *p) {
    if (!p.length) return NO;
    BOOL d = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&d] && d;
}

static void printHelp(void) {
    printf(
        "USAGE: macos-vision streamcapture --operation <op> [options]\n"
        "\n"
        "Capture stills, video, and audio from cameras, microphones, and displays.\n"
        "\n"
        "OPERATIONS:\n"
        "  screenshot    (default) Capture a still image of a display\n"
        "  photo         Capture a still photo from a camera\n"
        "  audio         Record audio from the microphone (runs until Ctrl+C)\n"
        "  video         Record video with audio from a camera (runs until Ctrl+C)\n"
        "  screen-record Record a display to a video file (runs until Ctrl+C)\n"
        "  barcode       Scan for barcodes/QR codes and stream results as NDJSON\n"
        "  list-devices  List available cameras and microphones\n"
        "\n"
        "OPTIONS:\n"
        "  --operation <op>        Operation to run (default: screenshot)\n"
        "  --output <path>         Output file path for captured media\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
        "  --artifacts-dir <dir>   Directory for captured media when --output is not set\n"
        "  --display-index <n>     Display to use for screenshot / screen-record (default: 0)\n"
        "  --device-index <n>      Camera or mic to use for photo / video / mic / barcode (default: 0)\n"
        "  --duration <secs>       Stop recording after this many seconds (mic, video, screen-record)\n"
        "  --format <fmt>          Video container format: mp4 (default), mov\n"
        "  --no-audio              Omit microphone when recording video\n"
        "  --types <list>          Comma-separated barcode types to scan for (default: all)\n"
        "                          Supported: qr, ean13, ean8, upce, code128, code39, code93,\n"
        "                                     pdf417, aztec, datamatrix, itf14, i2of5\n"
        "  --preview               Show a live preview window before/during capture\n"
        "                          photo: window shows feed, press ENTER to shoot\n"
        "                          video/screen-record: press ENTER to start, ENTER to stop\n"
        "  --fps <n>               Target frame rate for video stream (default: 30)\n"
        "  --jpeg-quality <0-1>    JPEG quality for MJPEG stream (default: 0.85)\n"
        "  --sample-rate <hz>      Audio sample rate for audio stream (default: 16000)\n"
        "  --channels <n>          Audio channel count for audio stream (default: 1)\n"
        "  --bit-depth <n>         Audio bit depth for audio stream (default: 16)\n"
        "  --no-stream             Force file mode even when stdout is piped\n"
        "                          Stream mode is detected automatically when stdout is piped.\n"
        "                          Streams MJPEG (video) or MVAU (audio) to stdout; pipe into face/overlay\n"
        "  --debug                 Emit processing_ms in output\n"
    );
}

BOOL MVDispatchStreamCapture(NSArray<NSString *> *args, NSError **error) {
    NSString *operation    = @"screenshot";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSString *artifactsDir = nil;
    NSInteger displayIndex = 0;
    NSInteger deviceIndex  = 0;
    NSTimeInterval duration = 0;
    NSString *format       = @"mp4";
    NSString *types        = nil;
    NSInteger fps          = 30;
    double jpegQuality     = 0.85;
    uint32_t sampleRate    = 16000;
    uint8_t  audioChannels = 1;
    uint8_t  audioBitDepth = 16;
    BOOL noAudio  = NO;
    BOOL preview  = NO;
    BOOL debug    = NO;
    BOOL noStream = NO;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)      { operation    = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output       = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput   = args[++i]; }
        else if ([a isEqualToString:@"--artifacts-dir"] && i+1 < (NSInteger)args.count)    { artifactsDir = args[++i]; }
        else if ([a isEqualToString:@"--display-index"] && i+1 < (NSInteger)args.count)    { displayIndex = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--device-index"] && i+1 < (NSInteger)args.count)     { deviceIndex  = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--duration"] && i+1 < (NSInteger)args.count)         { duration     = [args[++i] doubleValue]; }
        else if ([a isEqualToString:@"--format"] && i+1 < (NSInteger)args.count)           { format       = args[++i]; }
        else if ([a isEqualToString:@"--types"] && i+1 < (NSInteger)args.count)            { types        = args[++i]; }
        else if ([a isEqualToString:@"--fps"] && i+1 < (NSInteger)args.count)             { fps          = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--jpeg-quality"] && i+1 < (NSInteger)args.count)   { jpegQuality  = [args[++i] doubleValue]; }
        else if ([a isEqualToString:@"--sample-rate"] && i+1 < (NSInteger)args.count)    { sampleRate   = (uint32_t)[args[++i] integerValue]; }
        else if ([a isEqualToString:@"--channels"] && i+1 < (NSInteger)args.count)       { audioChannels= (uint8_t)[args[++i] integerValue]; }
        else if ([a isEqualToString:@"--bit-depth"] && i+1 < (NSInteger)args.count)      { audioBitDepth= (uint8_t)[args[++i] integerValue]; }
        else if ([a isEqualToString:@"--no-audio"])  { noAudio  = YES; }
        else if ([a isEqualToString:@"--preview"])   { preview  = YES; }
        else if ([a isEqualToString:@"--debug"])     { debug    = YES; }
        else if ([a isEqualToString:@"--no-stream"]) { noStream = YES; }
        else if ([a isEqualToString:@"--stream"]) {
            // deprecated: stream is now auto-detected
            fprintf(stderr, "warning: --stream is deprecated; stream mode is now detected automatically\n");
        }
        else {
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"streamcapture: unknown option '%@'", a]}];
            return NO;
        }
    }

    // JSON output: explicit --json-output wins; for list-devices --output can serve as json path
    NSString *resolvedJSON = nil;
    if (jsonOutput.length)                                                  resolvedJSON = jsonOutput;
    else if ([operation isEqualToString:@"list-devices"] && output.length) resolvedJSON = output;

    NSString *resolvedArtifacts = artifactsDir.length ? artifactsDir
                                : (![operation isEqualToString:@"list-devices"] && isDir(output)) ? output
                                : nil;

    // streamcapture is a source (only produces output), so use stdoutPiped for stream detection
    BOOL stdoutPiped = !isatty(STDOUT_FILENO);
    BOOL stream      = !noStream && stdoutPiped;

    CaptureProcessor *p = [[CaptureProcessor alloc] init];
    p.operation        = operation;
    p.mediaOutput      = output;
    p.artifactsDir     = resolvedArtifacts;
    p.jsonOutput       = resolvedJSON;
    p.displayIndex     = displayIndex;
    p.deviceIndex      = deviceIndex;
    p.duration         = duration;
    p.format           = format;
    p.types            = types;
    p.noAudio          = noAudio;
    p.preview          = preview;
    p.debug            = debug;
    p.stream           = stream;
    p.fps              = fps;
    p.jpegQuality      = jpegQuality;
    p.audioSampleRate  = sampleRate;
    p.audioChannels    = audioChannels;
    p.audioBitDepth    = audioBitDepth;
    return [p runWithError:error];
}
