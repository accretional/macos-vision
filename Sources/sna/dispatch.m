#import "sna/main.h"

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
        "USAGE: macos-vision sna --operation <op> [options]\n"
        "\n"
        "Classify environmental sounds and audio events in recordings.\n"
        "\n"
        "OPERATIONS:\n"
        "  classify        (default) Classify audio with Apple's built-in sound classifier\n"
        "  classify-custom Classify audio with a custom CoreML model (requires --model)\n"
        "  list-labels     List labels supported by Apple's classifier (or a custom --model)\n"
        "\n"
        "OPTIONS:\n"
        "  --input <path>              Audio file to analyse (required for classify)\n"
        "  --operation <op>            Operation to run (default: classify)\n"
        "  --output <path>             Directory or .json file for JSON output\n"
        "  --json-output <path>        Write JSON envelope to this file (default: stdout)\n"
        "  --model <path>              CoreML audio classifier model (classify-custom / list-labels)\n"
        "  --topk <n>                  Top-K results per window (default: 3)\n"
        "  --classify-window <secs>    Analysis window duration in seconds\n"
        "  --classify-overlap <frac>   Overlap factor between windows, [0.0, 1.0)\n"
        "  --debug                     Emit processing_ms in output\n"
    );
}

BOOL MVDispatchSNA(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath    = nil;
    NSString *operation    = @"classify";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSString *modelPath    = nil;
    NSInteger topk         = 3;
    NSTimeInterval window  = 0;
    BOOL windowSet         = NO;
    double overlap         = 0;
    BOOL overlapSet        = NO;
    BOOL debug = NO;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)              { inputPath = args[++i]; }
        else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)            { operation = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)               { output    = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)          { jsonOutput= args[++i]; }
        else if ([a isEqualToString:@"--model"] && i+1 < (NSInteger)args.count)                { modelPath = args[++i]; }
        else if ([a isEqualToString:@"--topk"] && i+1 < (NSInteger)args.count)                 { topk      = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--classify-window"] && i+1 < (NSInteger)args.count)      { window    = [args[++i] doubleValue]; windowSet  = YES; }
        else if ([a isEqualToString:@"--classify-overlap"] && i+1 < (NSInteger)args.count)     { overlap   = [args[++i] doubleValue]; overlapSet = YES; }
        else if ([a isEqualToString:@"--debug"]) { debug = YES; }
        else {
            fprintf(stderr, "sna: unknown option '%s'\n", a.UTF8String);
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"sna: unknown option '%@'", a]}];
            return NO;
        }
    }

    // JSON: <stem>.json naming
    NSString *resolvedJSON = nil;
    if (jsonOutput.length && !isDir(jsonOutput))        resolvedJSON = jsonOutput;
    else if (jsonOutput.length && isDir(jsonOutput))    resolvedJSON = [[jsonOutput stringByAppendingPathComponent:stem(inputPath)] stringByAppendingPathExtension:@"json"];
    else if (output.length && isDir(output))            resolvedJSON = [[output stringByAppendingPathComponent:stem(inputPath)] stringByAppendingPathExtension:@"json"];
    else if ([output.pathExtension.lowercaseString isEqualToString:@"json"]) resolvedJSON = output;

    SNAProcessor *p = [[SNAProcessor alloc] init];
    p.inputPath         = inputPath;
    p.jsonOutput        = resolvedJSON;
    p.operation         = operation;
    p.modelPath         = modelPath;
    p.topk              = topk;
    p.windowDuration    = window;
    p.windowDurationSet = windowSet;
    p.overlapFactor     = overlap;
    p.overlapFactorSet  = overlapSet;
    p.debug             = debug;
    return [p runWithError:error];
}
