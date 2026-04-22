#import "classify/main.h"

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
        "USAGE: macos-vision classify --operation <op> [options]\n"
        "\n"
        "Classify scenes, objects, animals, and other content in images.\n"
        "\n"
        "OPERATIONS:\n"
        "  classify      (default) Top scene/object classifications for an image\n"
        "  animals       Detect and classify animals with bounding boxes\n"
        "  rectangles    Detect salient rectangular regions (documents, screens)\n"
        "  horizon       Detect horizon angle\n"
        "  contours      Detect contour paths in the image\n"
        "  aesthetics    Aesthetic quality scores (overall, composition, lighting)\n"
        "  feature-print Compute a perceptual feature vector for similarity search\n"
        "\n"
        "OPTIONS:\n"
        "  --input <path>          Image file to process (required)\n"
        "  --operation <op>        Operation to run (default: classify)\n"
        "  --output <path>         Directory or .json file for JSON output\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
        "  --artifacts-dir <dir>   Write debug overlay images here (requires --debug)\n"
        "  --boxes-format <fmt>    Overlay image format: png (default), jpg, tiff, bmp, gif\n"
        "  --debug                 Draw detection boxes and write overlay image\n"
        "  --stream                Read MJPEG from stdin, annotate each frame, write MJPEG to stdout\n"
        "                          Adds X-MV-classify-<op> header per frame; pipe from streamcapture --stream\n"
    );
}

BOOL MVDispatchClassify(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath    = nil;
    NSString *operation    = @"classify";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSString *artifactsDir = nil;
    NSString *boxesFormat  = @"png";
    BOOL debug = NO, stream = NO;

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
        else if ([a isEqualToString:@"--debug"])  { debug  = YES; }
        else if ([a isEqualToString:@"--stream"]) { stream = YES; }
        else {
            fprintf(stderr, "classify: unknown option '%s'\n", a.UTF8String);
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"classify: unknown option '%@'", a]}];
            return NO;
        }
    }

    NSArray<NSString *> *validBoxFmts = @[@"png", @"jpg", @"jpeg", @"tiff", @"tif", @"bmp", @"gif"];
    if (![validBoxFmts containsObject:boxesFormat.lowercaseString]) {
        fprintf(stderr, "classify: unsupported --boxes-format '%s'\n", boxesFormat.UTF8String);
        if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"classify: unsupported --boxes-format '%@'", boxesFormat]}];
        return NO;
    }

    NSString *opSlug = [[operation stringByReplacingOccurrencesOfString:@"-" withString:@"_"]
                                   stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *jsonName = [[NSString stringWithFormat:@"%@_%@", stem(inputPath), opSlug] stringByAppendingPathExtension:@"json"];
    NSString *resolvedJSON = nil;
    if (jsonOutput.length && !isDir(jsonOutput))        resolvedJSON = jsonOutput;
    else if (jsonOutput.length && isDir(jsonOutput))    resolvedJSON = [jsonOutput stringByAppendingPathComponent:jsonName];
    else if (output.length && isDir(output))            resolvedJSON = [output stringByAppendingPathComponent:jsonName];
    else if ([output.pathExtension.lowercaseString isEqualToString:@"json"]) resolvedJSON = output;

    NSString *resolvedArtifacts = artifactsDir.length ? artifactsDir : (isDir(output) ? output : nil);

    ClassifyProcessor *p = [[ClassifyProcessor alloc] init];
    p.inputPath    = inputPath;
    p.jsonOutput   = resolvedJSON;
    p.artifactsDir = resolvedArtifacts;
    p.debug        = debug;
    p.boxesFormat  = boxesFormat;
    p.operation    = operation;
    p.stream       = stream;
    return [p runWithError:error];
}
