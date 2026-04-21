#import "speech/main.h"

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
        "USAGE: macos-vision speech --operation <op> [options]\n"
        "\n"
        "Transcribe spoken audio to text and analyse voice characteristics.\n"
        "\n"
        "OPERATIONS:\n"
        "  transcribe       (default) Transcribe an audio file to text\n"
        "  voice-analytics  Emit per-segment voice analytics (pitch, jitter, shimmer, …)\n"
        "  list-locales     List supported recognition locales\n"
        "\n"
        "OPTIONS:\n"
        "  --input <path>          Audio file to process (required for transcribe / voice-analytics)\n"
        "  --operation <op>        Operation to run (default: transcribe)\n"
        "  --output <path>         Directory or .json file for JSON output\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
        "  --audio-lang <lang>     BCP-47 locale for recognition, e.g. en-US (default: en-US)\n"
        "  --offline               Use on-device recognition only (no network)\n"
        "  --debug                 Emit processing_ms in output\n"
    );
}

BOOL MVDispatchSpeech(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath  = nil;
    NSString *operation  = @"transcribe";
    NSString *output     = nil;
    NSString *jsonOutput = nil;
    NSString *audioLang  = @"en-US";
    BOOL offline = NO, debug = NO;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)          { inputPath  = args[++i]; }
        else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)        { operation  = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output     = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput = args[++i]; }
        else if ([a isEqualToString:@"--audio-lang"] && i+1 < (NSInteger)args.count)       { audioLang  = args[++i]; }
        else if ([a isEqualToString:@"--offline"]) { offline = YES; }
        else if ([a isEqualToString:@"--debug"])   { debug   = YES; }
        else {
            fprintf(stderr, "speech: unknown option '%s'\n", a.UTF8String);
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"speech: unknown option '%@'", a]}];
            return NO;
        }
    }

    // JSON: <stem>.json naming
    NSString *resolvedJSON = nil;
    if (jsonOutput.length && !isDir(jsonOutput))        resolvedJSON = jsonOutput;
    else if (jsonOutput.length && isDir(jsonOutput))    resolvedJSON = [[jsonOutput stringByAppendingPathComponent:stem(inputPath)] stringByAppendingPathExtension:@"json"];
    else if (output.length && isDir(output))            resolvedJSON = [[output stringByAppendingPathComponent:stem(inputPath)] stringByAppendingPathExtension:@"json"];
    else if ([output.pathExtension.lowercaseString isEqualToString:@"json"]) resolvedJSON = output;

    SpeechProcessor *p = [[SpeechProcessor alloc] init];
    p.inputPath  = inputPath;
    p.jsonOutput = resolvedJSON;
    p.operation  = operation;
    p.lang       = audioLang;
    p.offline    = offline;
    p.debug      = debug;
    return [p runWithError:error];
}
