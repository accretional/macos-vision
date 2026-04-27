#import "shazam/main.h"
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
        "USAGE: macos-vision shazam --operation <op> [options]\n"
        "\n"
        "Identify songs and audio clips, or build a custom recognition catalogue.\n"
        "\n"
        "OPERATIONS:\n"
        "  match         (default) Identify a song from an audio file\n"
        "  match-custom  Match against a custom .shazamcatalog (requires --catalog)\n"
        "  build         Build a .shazamcatalog from a directory of audio files\n"
        "\n"
        "OPTIONS:\n"
        "  --input <path>          Audio file, or directory of audio files (build)\n"
        "  --operation <op>        Operation to run (default: match)\n"
        "  --output <path>         Directory or .json file for JSON output\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
        "  --artifacts-dir <dir>   Output directory for built catalog (build)\n"
        "  --catalog <path>        Path to .shazamcatalog file (match-custom)\n"
        "  --sample-rate <hz>      Sample rate for raw PCM stdin (default: 16000)\n"
        "  --channels <n>          Channel count for raw PCM stdin (default: 1)\n"
        "  --bit-depth <n>         Bit depth for raw PCM stdin (default: 16)\n"
        "  --no-stream             Force file mode even when stdin is piped\n"
        "                          Stream mode auto-detected when stdin is piped (reads MVAU or raw PCM)\n"
        "  --debug                 Emit processing_ms in output\n"
    );
}

BOOL MVDispatchShazam(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath    = nil;
    NSString *operation    = @"match";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSString *artifactsDir = nil;
    NSString *catalog      = nil;
    uint32_t sampleRate    = 16000;
    uint8_t  channels      = 1;
    uint8_t  bitDepth      = 16;
    BOOL debug = NO, noStream = NO;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)          { inputPath    = args[++i]; }
        else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)        { operation    = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output       = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput   = args[++i]; }
        else if ([a isEqualToString:@"--artifacts-dir"] && i+1 < (NSInteger)args.count)    { artifactsDir = args[++i]; }
        else if ([a isEqualToString:@"--catalog"] && i+1 < (NSInteger)args.count)          { catalog      = args[++i]; }
        else if ([a isEqualToString:@"--sample-rate"] && i+1 < (NSInteger)args.count) { sampleRate = (uint32_t)[args[++i] integerValue]; }
        else if ([a isEqualToString:@"--channels"] && i+1 < (NSInteger)args.count)   { channels   = (uint8_t)[args[++i] integerValue]; }
        else if ([a isEqualToString:@"--bit-depth"] && i+1 < (NSInteger)args.count)  { bitDepth   = (uint8_t)[args[++i] integerValue]; }
        else if ([a isEqualToString:@"--debug"])     { debug    = YES; }
        else if ([a isEqualToString:@"--no-stream"]) { noStream = YES; }
        else {
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"shazam: unknown option '%@'", a]}];
            return NO;
        }
    }

    // JSON: <stem>.json naming
    NSString *resolvedJSON = nil;
    if (jsonOutput.length && !isDir(jsonOutput))        resolvedJSON = jsonOutput;
    else if (jsonOutput.length && isDir(jsonOutput))    resolvedJSON = [[jsonOutput stringByAppendingPathComponent:stem(inputPath)] stringByAppendingPathExtension:@"json"];
    else if (output.length && isDir(output))            resolvedJSON = [[output stringByAppendingPathComponent:stem(inputPath)] stringByAppendingPathExtension:@"json"];
    else if ([output.pathExtension.lowercaseString isEqualToString:@"json"]) resolvedJSON = output;

    NSString *resolvedArtifacts = artifactsDir.length ? artifactsDir : (isDir(output) ? output : nil);

    // Auto-detect stream-in mode: active when stdin is piped, no explicit --input
    // file was provided, and --no-stream is not set. An explicit --input always
    // takes precedence over piped stdin.
    BOOL stdinPiped = !isatty(STDIN_FILENO);
    BOOL streamIn   = !noStream && stdinPiped && !inputPath.length;

    ShazamProcessor *p = [[ShazamProcessor alloc] init];
    p.inputPath    = inputPath;
    p.jsonOutput   = resolvedJSON;
    p.artifactsDir = resolvedArtifacts;
    p.operation    = operation;
    p.catalog      = catalog;
    p.debug        = debug;
    p.streamIn     = streamIn;
    p.sampleRate   = sampleRate;
    p.channels     = channels;
    p.bitDepth     = bitDepth;
    BOOL ok = [p runWithError:error];
    // SHSession keeps internal networking threads alive even after the match
    // completes or times out, causing the process to hang for the TCP connection
    // timeout (~60 s) during ARC teardown. Print any error and force-exit to
    // avoid blocking on session teardown.
    if (!ok && error && *error)
        fprintf(stderr, "Error: %s\n", (*error).localizedDescription.UTF8String);
    fflush(stdout);
    fflush(stderr);
    _exit(ok ? 0 : 1);
}
