#import "speech/main.h"
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
        "  --sample-rate <hz>      Sample rate for raw PCM stdin (default: 16000)\n"
        "  --channels <n>          Channel count for raw PCM stdin (default: 1)\n"
        "  --bit-depth <n>         Bit depth for raw PCM stdin (default: 16)\n"
        "  --no-header             Force raw PCM mode, ignoring any MVAU header\n"
        "  --no-stream             Force file mode even when stdin is piped\n"
        "                          Stream mode auto-detected when stdin is piped (reads MVAU or raw PCM)\n"
        "  --debug                 Emit processing_ms in output\n"
    );
}

BOOL MVDispatchSpeech(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath  = nil;
    NSString *operation  = @"transcribe";
    NSString *output     = nil;
    NSString *jsonOutput = nil;
    NSString *audioLang  = @"en-US";
    uint32_t sampleRate  = 16000;
    uint8_t  channels    = 1;
    uint8_t  bitDepth    = 16;
    BOOL offline = NO, debug = NO, noHeader = NO, noStream = NO;
    BOOL appContext = NO;
    NSString *audioPipe  = nil;
    NSString *resultPipe = nil;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)          { inputPath  = args[++i]; }
        else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)        { operation  = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output     = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput = args[++i]; }
        else if ([a isEqualToString:@"--audio-lang"] && i+1 < (NSInteger)args.count)       { audioLang  = args[++i]; }
        else if ([a isEqualToString:@"--sample-rate"] && i+1 < (NSInteger)args.count)    { sampleRate = (uint32_t)[args[++i] integerValue]; }
        else if ([a isEqualToString:@"--channels"] && i+1 < (NSInteger)args.count)       { channels   = (uint8_t)[args[++i] integerValue]; }
        else if ([a isEqualToString:@"--bit-depth"] && i+1 < (NSInteger)args.count)      { bitDepth   = (uint8_t)[args[++i] integerValue]; }
        else if ([a isEqualToString:@"--offline"])    { offline    = YES; }
        else if ([a isEqualToString:@"--debug"])      { debug      = YES; }
        else if ([a isEqualToString:@"--no-header"])  { noHeader   = YES; }
        else if ([a isEqualToString:@"--no-stream"])  { noStream   = YES; }
        // Internal args injected by the self-relaunch path — not shown in --help
        else if ([a isEqualToString:@"--_app-context"])                                    { appContext  = YES; }
        else if ([a isEqualToString:@"--_audio-pipe"]  && i+1 < (NSInteger)args.count)    { audioPipe  = args[++i]; }
        else if ([a isEqualToString:@"--_result-pipe"] && i+1 < (NSInteger)args.count)    { resultPipe = args[++i]; }
        else {
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

    // Auto-detect stream-in mode: active when stdin is piped and --no-stream not set
    BOOL stdinPiped = !isatty(STDIN_FILENO);
    BOOL streamIn   = !noStream && stdinPiped;

    SpeechProcessor *p = [[SpeechProcessor alloc] init];
    p.inputPath  = inputPath;
    p.jsonOutput = resolvedJSON;
    p.operation  = operation;
    p.lang       = audioLang;
    p.offline    = offline;
    p.debug      = debug;
    p.streamIn   = streamIn;
    p.sampleRate = sampleRate;
    p.channels   = channels;
    p.bitDepth   = bitDepth;
    p.noHeader   = noHeader;
    p.appContext  = appContext;
    p.audioPipe  = audioPipe;
    p.resultPipe = resultPipe;

    return [p runWithError:error];
}
