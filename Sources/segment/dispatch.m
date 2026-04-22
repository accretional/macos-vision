#import "segment/main.h"
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
        "USAGE: macos-vision segment --operation <op> [options]\n"
        "\n"
        "Separate subjects from backgrounds and generate saliency maps.\n"
        "\n"
        "OPERATIONS:\n"
        "  foreground-mask      (default) Foreground subject mask\n"
        "  person-segment       Full-body person segmentation mask\n"
        "  person-mask          Fine-grained person instance mask\n"
        "  attention-saliency   Heatmap of visually salient regions\n"
        "  objectness-saliency  Heatmap of object-like regions\n"
        "\n"
        "OPTIONS:\n"
        "  --input <path>          Image file to process (required)\n"
        "  --operation <op>        Operation to run (default: foreground-mask)\n"
        "  --output <path>         Output mask image file, directory, or .json path\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
        "  --artifacts-dir <dir>   Write mask images here\n"
        "  --no-stream             Force file mode even when stdin is piped (future stream mode)\n"
    );
}

BOOL MVDispatchSegment(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath    = nil;
    NSString *operation    = @"foreground-mask";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSString *artifactsDir = nil;
    BOOL noStream          = NO;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)          { inputPath    = args[++i]; }
        else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)        { operation    = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output       = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput   = args[++i]; }
        else if ([a isEqualToString:@"--artifacts-dir"] && i+1 < (NSInteger)args.count)    { artifactsDir = args[++i]; }
        else if ([a isEqualToString:@"--no-stream"]) { noStream = YES; }
        else if ([a isEqualToString:@"--stream"]) {
            fprintf(stderr, "warning: --stream is deprecated; stream mode is now detected automatically\n");
        }
        else {
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"segment: unknown option '%@'", a]}];
            return NO;
        }
    }

    NSString *opSlug = [[operation stringByReplacingOccurrencesOfString:@"-" withString:@"_"]
                                   stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *jsonName = [[NSString stringWithFormat:@"%@_%@", stem(inputPath), opSlug] stringByAppendingPathExtension:@"json"];
    NSString *resolvedJSON = nil;
    if (jsonOutput.length && !isDir(jsonOutput))        resolvedJSON = jsonOutput;
    else if (jsonOutput.length && isDir(jsonOutput))    resolvedJSON = [jsonOutput stringByAppendingPathComponent:jsonName];
    else if (output.length && isDir(output))            resolvedJSON = [output stringByAppendingPathComponent:jsonName];
    else if ([output.pathExtension.lowercaseString isEqualToString:@"json"]) resolvedJSON = output;

    // Artifacts: explicit dir, else output if it's a dir
    NSString *resolvedArtifacts = artifactsDir.length ? artifactsDir : (isDir(output) ? output : nil);

    // Exact media output file: output when it's not a dir and not .json
    NSString *outputPath = nil;
    if (output.length && !isDir(output) && ![output.pathExtension.lowercaseString isEqualToString:@"json"])
        outputPath = output;

    BOOL stdinPiped  = !isatty(STDIN_FILENO);
    BOOL stdoutPiped = !isatty(STDOUT_FILENO);
    BOOL streamIn    = !noStream && stdinPiped && !inputPath.length;
    BOOL streamOut   = !noStream && stdoutPiped;

    SegmentProcessor *p = [[SegmentProcessor alloc] init];
    p.inputPath    = inputPath;
    p.jsonOutput   = resolvedJSON;
    p.artifactsDir = resolvedArtifacts;
    p.outputPath   = outputPath;
    p.operation    = operation;
    p.stream       = streamIn;
    p.streamOut    = streamOut;
    if ((streamIn || streamOut) && output.length) p.ndjsonOutput = output;
    return [p runWithError:error];
}
