#import "face/main.h"
#include <unistd.h>

static BOOL isDir(NSString *p) {
    if (!p.length) return NO;
    BOOL d = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&d] && d;
}
static NSString *stem(NSString *p) {
    NSString *s = p.lastPathComponent.stringByDeletingPathExtension;
    return s.length ? s : @"result";
}

static void printHelp(void) {
    printf(
        "USAGE: macos-vision face --operation <op> [options]\n"
        "\n"
        "Detect faces, bodies, and poses in images.\n"
        "\n"
        "OPERATIONS:\n"
        "  face-rectangles   (default) Bounding boxes around detected faces\n"
        "  face-landmarks    68-point facial landmark geometry\n"
        "  face-quality      Per-face capture quality score\n"
        "  human-rectangles  Bounding boxes around detected human bodies\n"
        "  body-pose         17-joint human body pose skeleton\n"
        "  hand-pose         21-point hand pose landmarks\n"
        "  animal-pose       Animal body pose landmarks\n"
        "\n"
        "OPTIONS:\n"
        "  --input <path>          Image file to process (required unless streaming)\n"
        "  --operation <op>        Operation to run (default: face-rectangles)\n"
        "                          Comma-separated operations supported (e.g. face-rectangles,face-landmarks)\n"
        "  --output <path>         Directory or .json file for JSON output; in stream mode,\n"
        "                          writes NDJSON results to this file alongside MJPEG stdout\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
        "  --artifacts-dir <dir>   Write debug overlay images here (requires --debug)\n"
        "  --boxes-format <fmt>    Overlay image format: png (default), jpg, tiff, bmp, gif\n"
        "  --debug                 Draw detection boxes and write overlay image\n"
        "  --no-stream             Force file mode even when stdin/stdout are piped\n"
        "  --max-lag <n>           Max queued frames before dropping (stream mode, default: 1)\n"
        "                          Stream mode is detected automatically when stdin is piped.\n"
        "                          Adds X-MV-face-<op> header per frame; pipe from streamcapture\n"
    );
}

BOOL MVDispatchFace(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath    = nil;
    NSString *operation    = @"face-rectangles";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSString *artifactsDir = nil;
    NSString *boxesFormat  = @"png";
    NSInteger maxLag       = 1;
    BOOL debug    = NO;
    BOOL noStream = NO;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)          { inputPath    = args[++i]; }
        else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)        { operation    = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output       = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput   = args[++i]; }
        else if ([a isEqualToString:@"--artifacts-dir"] && i+1 < (NSInteger)args.count)    { artifactsDir = args[++i]; }
        else if ([a isEqualToString:@"--boxes-format"] && i+1 < (NSInteger)args.count)     { boxesFormat  = args[++i]; }
        else if ([a isEqualToString:@"--max-lag"] && i+1 < (NSInteger)args.count)          { maxLag       = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--debug"])     { debug    = YES; }
        else if ([a isEqualToString:@"--no-stream"]) { noStream = YES; }
        else if ([a isEqualToString:@"--stream"]) {
            // deprecated: stream is now auto-detected
            fprintf(stderr, "warning: --stream is deprecated; stream mode is now detected automatically\n");
        }
        else {
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"face: unknown option '%@'", a]}];
            return NO;
        }
    }

    NSArray<NSString *> *validBoxFmts = @[@"png", @"jpg", @"jpeg", @"tiff", @"tif", @"bmp", @"gif"];
    if (![validBoxFmts containsObject:boxesFormat.lowercaseString]) {
        if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"face: unsupported --boxes-format '%@'. Valid: png, jpg, tiff, bmp, gif", boxesFormat]}];
        return NO;
    }

    // JSON: <stem>_<op>.json
    NSString *opSlug = [[operation stringByReplacingOccurrencesOfString:@"-" withString:@"_"]
                                   stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    // For comma-separated ops use the first op for the json name
    NSString *firstOp = [operation componentsSeparatedByString:@","].firstObject ?: operation;
    NSString *firstSlug = [[firstOp stringByReplacingOccurrencesOfString:@"-" withString:@"_"]
                                    stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *jsonName = [[NSString stringWithFormat:@"%@_%@", stem(inputPath), firstSlug] stringByAppendingPathExtension:@"json"];
    (void)opSlug; // kept for reference
    NSString *resolvedJSON = nil;
    if (jsonOutput.length && !isDir(jsonOutput))        resolvedJSON = jsonOutput;
    else if (jsonOutput.length && isDir(jsonOutput))    resolvedJSON = [jsonOutput stringByAppendingPathComponent:jsonName];
    else if (output.length && isDir(output))            resolvedJSON = [output stringByAppendingPathComponent:jsonName];
    else if ([output.pathExtension.lowercaseString isEqualToString:@"json"]) resolvedJSON = output;

    NSString *resolvedArtifacts = artifactsDir.length ? artifactsDir : (isDir(output) ? output : nil);

    // Auto-detect stream mode from pipe state and whether explicit --input is given.
    // streamIn (S→S / S→F): stdin piped AND no explicit --input → read MJPEG from stdin.
    // streamOut (F→S / S→S): stdout piped → write MJPEG to stdout.
    BOOL stdinPiped  = !isatty(STDIN_FILENO);
    BOOL stdoutPiped = !isatty(STDOUT_FILENO);
    BOOL streamIn    = !noStream && stdinPiped && !inputPath.length;
    BOOL streamOut   = !noStream && stdoutPiped;

    FaceProcessor *p = [[FaceProcessor alloc] init];
    p.inputPath    = inputPath;
    p.jsonOutput   = resolvedJSON;
    p.artifactsDir = resolvedArtifacts;
    p.debug        = debug;
    p.boxesFormat  = boxesFormat;
    p.operation    = operation;
    p.stream       = streamIn;
    p.streamOut    = streamOut;
    p.maxLag       = maxLag;

    // Dual-write: in stream mode with --output set, write NDJSON to that file
    if ((p.stream || p.streamOut) && output.length) {
        p.ndjsonOutput = output;
    }

    return [p runWithError:error];
}
