#import "overlay/main.h"

static BOOL isDir(NSString *p) {
    if (!p.length) return NO;
    BOOL d = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&d] && d;
}
static NSString *stem(NSString *p) {
    NSString *s = p.lastPathComponent.stringByDeletingPathExtension;
    return s.length ? s : @"overlay";
}

static void printHelp(void) {
    printf(
        "USAGE: macos-vision overlay --json <path> [options]\n"
        "\n"
        "Render analysis results from any subcommand as an interactive SVG overlay.\n"
        "\n"
        "OPTIONS:\n"
        "  --json <path>           JSON result file to render (required)\n"
        "  --input <path>          Override the image path embedded in the JSON\n"
        "  --output <path>         Output .svg file path (default: <json-basename>.svg)\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
    );
}

BOOL MVDispatchOverlay(NSArray<NSString *> *args, NSError **error) {
    NSString *jsonPath   = nil;
    NSString *inputPath  = nil;
    NSString *output     = nil;
    NSString *jsonOutput = nil;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--json"] && i+1 < (NSInteger)args.count)           { jsonPath   = args[++i]; }
        else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)            { inputPath  = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output     = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput = args[++i]; }
        else {
            fprintf(stderr, "overlay: unknown option '%s'\n", a.UTF8String);
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"overlay: unknown option '%@'", a]}];
            return NO;
        }
    }

    // JSON envelope: <stem>_overlay.json naming
    NSString *jsonStem = stem(jsonPath);
    NSString *jsonName = [[jsonStem stringByAppendingString:@"_overlay"] stringByAppendingPathExtension:@"json"];
    NSString *resolvedJSON = nil;
    if (jsonOutput.length && !isDir(jsonOutput))        resolvedJSON = jsonOutput;
    else if (jsonOutput.length && isDir(jsonOutput))    resolvedJSON = [jsonOutput stringByAppendingPathComponent:jsonName];
    else if (output.length && isDir(output))            resolvedJSON = [output stringByAppendingPathComponent:jsonName];
    else if ([output.pathExtension.lowercaseString isEqualToString:@"json"]) resolvedJSON = output;

    OverlayProcessor *p = [[OverlayProcessor alloc] init];
    p.jsonPath   = jsonPath;
    p.inputPath  = inputPath;
    p.svgOutput  = output;
    p.jsonOutput = resolvedJSON;
    return [p runWithError:error];
}
