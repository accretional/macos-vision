#import "sna/main.h"
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
        "USAGE: macos-vision sna --operation <op> [options]\n"
        "\n"
        "Classify environmental sounds and audio events in recordings.\n"
        "\n"
        "OPERATIONS:\n"
        "  classify        (default) Classify audio with Apple's built-in sound classifier\n"
        "  list-labels     List labels supported by Apple's classifier\n"
        "\n"
        "OPTIONS:\n"
        "  --input <path>              Audio file to analyse (required for classify)\n"
        "  --operation <op>            Operation to run (default: classify)\n"
        "  --output <path>             Directory or .json file for JSON output\n"
        "  --json-output <path>        Write JSON envelope to this file (default: stdout)\n"
        "  --topk <n>                  Top-K results per window (default: 3)\n"
        "  --classify-window <secs>    Analysis window duration in seconds\n"
        "  --classify-overlap <frac>   Overlap factor between windows, [0.0, 1.0)\n"
        "  --sample-rate <hz>          Sample rate for raw PCM stdin (default: 16000)\n"
        "  --channels <n>              Channel count for raw PCM stdin (default: 1)\n"
        "  --bit-depth <n>             Bit depth for raw PCM stdin (default: 16)\n"
        "  --no-stream                 Force file mode even when stdin is piped\n"
        "                              Stream mode auto-detected when stdin is piped (reads MVAU or raw PCM)\n"
        "  --debug                     Emit processing_ms in output\n"
    );
}

BOOL MVDispatchSNA(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath    = nil;
    NSString *operation    = @"classify";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSInteger topk         = 3;
    NSTimeInterval window  = 0;
    BOOL windowSet         = NO;
    double overlap         = 0;
    BOOL overlapSet        = NO;
    uint32_t sampleRate    = 16000;
    uint8_t  channels      = 1;
    uint8_t  bitDepth      = 16;
    BOOL debug = NO, noStream = NO;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)              { inputPath = args[++i]; }
        else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)            { operation = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)               { output    = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)          { jsonOutput= args[++i]; }
        else if ([a isEqualToString:@"--topk"] && i+1 < (NSInteger)args.count)                 { topk      = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--classify-window"] && i+1 < (NSInteger)args.count)      { window    = [args[++i] doubleValue]; windowSet  = YES; }
        else if ([a isEqualToString:@"--classify-overlap"] && i+1 < (NSInteger)args.count)     { overlap   = [args[++i] doubleValue]; overlapSet = YES; }
        else if ([a isEqualToString:@"--sample-rate"] && i+1 < (NSInteger)args.count) { sampleRate = (uint32_t)[args[++i] integerValue]; }
        else if ([a isEqualToString:@"--channels"] && i+1 < (NSInteger)args.count)   { channels   = (uint8_t)[args[++i] integerValue]; }
        else if ([a isEqualToString:@"--bit-depth"] && i+1 < (NSInteger)args.count)  { bitDepth   = (uint8_t)[args[++i] integerValue]; }
        else if ([a isEqualToString:@"--debug"])     { debug    = YES; }
        else if ([a isEqualToString:@"--no-stream"]) { noStream = YES; }
        else {
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

    // Auto-detect stream-in mode: active when stdin is piped and --no-stream not set
    BOOL stdinPiped = !isatty(STDIN_FILENO);
    BOOL streamIn   = !noStream && stdinPiped;

    SNAProcessor *p = [[SNAProcessor alloc] init];
    p.inputPath         = inputPath;
    p.jsonOutput        = resolvedJSON;
    p.operation         = operation;
    p.topk              = topk;
    p.windowDuration    = window;
    p.windowDurationSet = windowSet;
    p.overlapFactor     = overlap;
    p.overlapFactorSet  = overlapSet;
    p.debug             = debug;
    p.streamIn          = streamIn;
    p.sampleRate        = sampleRate;
    p.channels          = channels;
    p.bitDepth          = bitDepth;
    return [p runWithError:error];
}
