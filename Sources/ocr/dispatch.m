#import "ocr/main.h"

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
        "USAGE: macos-vision ocr [options]\n"
        "\n"
        "Extract text from images.\n"
        "\n"
        "OPTIONS:\n"
        "  --input <path>          Image file to process (required unless --lang)\n"
        "  --output <path>         Directory or .json file for JSON output\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
        "  --artifacts-dir <dir>   Write debug overlay image here (requires --debug)\n"
        "  --rec-langs <langs>     Recognition languages, comma-separated (e.g. en-US,fr-FR)\n"
        "  --boxes-format <fmt>    Overlay image format: png (default), jpg, tiff, bmp, gif\n"
        "  --lang                  List supported recognition languages instead of processing\n"
        "  --debug                 Draw bounding boxes and write overlay image\n"
        "  --stream                Read MJPEG from stdin, annotate each frame, write MJPEG to stdout\n"
        "                          Adds X-MV-ocr-recognize header per frame; pipe from streamcapture --stream\n"
    );
}

BOOL MVDispatchOCR(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath    = nil;
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSString *artifactsDir = nil;
    NSString *recLangs     = nil;
    NSString *boxesFormat  = @"png";
    BOOL debug = NO, lang = NO, stream = NO;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)          { inputPath    = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output       = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput   = args[++i]; }
        else if ([a isEqualToString:@"--artifacts-dir"] && i+1 < (NSInteger)args.count)    { artifactsDir = args[++i]; }
        else if ([a isEqualToString:@"--rec-langs"] && i+1 < (NSInteger)args.count)        { recLangs     = args[++i]; }
        else if ([a isEqualToString:@"--boxes-format"] && i+1 < (NSInteger)args.count)     { boxesFormat  = args[++i]; }
        else if ([a isEqualToString:@"--debug"])  { debug  = YES; }
        else if ([a isEqualToString:@"--lang"])   { lang   = YES; }
        else if ([a isEqualToString:@"--stream"]) { stream = YES; }
        else {
            fprintf(stderr, "ocr: unknown option '%s'\n", a.UTF8String);
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"ocr: unknown option '%@'", a]}];
            return NO;
        }
    }

    NSArray<NSString *> *validBoxFmts = @[@"png", @"jpg", @"jpeg", @"tiff", @"tif", @"bmp", @"gif"];
    if (![validBoxFmts containsObject:boxesFormat.lowercaseString]) {
        fprintf(stderr, "ocr: unsupported --boxes-format '%s'\n", boxesFormat.UTF8String);
        if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"ocr: unsupported --boxes-format '%@'", boxesFormat]}];
        return NO;
    }

    // JSON output resolution: <stem>.json naming
    NSString *resolvedJSON = nil;
    if (jsonOutput.length && !isDir(jsonOutput))        resolvedJSON = jsonOutput;
    else if (jsonOutput.length && isDir(jsonOutput))    resolvedJSON = [[jsonOutput stringByAppendingPathComponent:stem(inputPath)] stringByAppendingPathExtension:@"json"];
    else if (output.length && isDir(output))            resolvedJSON = [[output stringByAppendingPathComponent:stem(inputPath)] stringByAppendingPathExtension:@"json"];
    else if ([output.pathExtension.lowercaseString isEqualToString:@"json"]) resolvedJSON = output;

    // Artifacts dir: use --artifacts-dir, else --output if it's a directory
    NSString *resolvedArtifacts = artifactsDir.length ? artifactsDir : (isDir(output) ? output : nil);

    OCRProcessor *p = [[OCRProcessor alloc] init];
    p.inputPath    = inputPath;
    p.jsonOutput   = resolvedJSON;
    p.artifactsDir = resolvedArtifacts;
    p.debug        = debug;
    p.lang         = lang;
    p.recLangs     = recLangs;
    p.boxesFormat  = boxesFormat;
    p.stream       = stream;
    return [p runWithError:error];
}
