#import "track/main.h"

static BOOL isDir(NSString *p) {
    if (!p.length) return NO;
    BOOL d = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&d] && d;
}

static void printHelp(void) {
    printf(
        "USAGE: macos-vision track --operation <op> [options]\n"
        "\n"
        "Measure motion and registration across video frames or image sequences.\n"
        "\n"
        "OPERATIONS:\n"
        "  homographic    (default) Estimate a homographic transform between frames\n"
        "  translational  Estimate a translational (2-DOF) transform between frames\n"
        "  optical-flow   Dense per-pixel optical flow; writes flow PNGs to --artifacts-dir\n"
        "  trajectories   Track salient feature point trajectories across frames\n"
        "\n"
        "OPTIONS:\n"
        "  --input <path>          Video file or directory of ordered image frames (required)\n"
        "  --operation <op>        Operation to run (default: homographic)\n"
        "  --output <path>         Directory or .json file for JSON output\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
        "  --artifacts-dir <dir>   Directory for optical-flow PNG frames\n"
    );
}

BOOL MVDispatchTrack(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath    = nil;
    NSString *operation    = @"homographic";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSString *artifactsDir = nil;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)          { inputPath    = args[++i]; }
        else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)        { operation    = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output       = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput   = args[++i]; }
        else if ([a isEqualToString:@"--artifacts-dir"] && i+1 < (NSInteger)args.count)    { artifactsDir = args[++i]; }
        else {
            fprintf(stderr, "track: unknown option '%s'\n", a.UTF8String);
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"track: unknown option '%@'", a]}];
            return NO;
        }
    }

    // JSON: track_<op>.json; optical-flow goes into optical-flow/ subdir
    NSString *opSlug = [[operation stringByReplacingOccurrencesOfString:@"-" withString:@"_"]
                                   stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *jsonName = [[NSString stringWithFormat:@"track_%@", opSlug] stringByAppendingPathExtension:@"json"];
    NSString *resolvedJSON = nil;
    if (jsonOutput.length && !isDir(jsonOutput)) {
        resolvedJSON = jsonOutput;
    } else {
        NSString *dir = (jsonOutput.length && isDir(jsonOutput)) ? jsonOutput
                      : (output.length && isDir(output)) ? output : nil;
        if (dir) {
            if ([operation isEqualToString:@"optical-flow"]) {
                NSString *subdir = [dir stringByAppendingPathComponent:@"optical-flow"];
                resolvedJSON = [subdir stringByAppendingPathComponent:jsonName];
            } else {
                resolvedJSON = [dir stringByAppendingPathComponent:jsonName];
            }
        } else if ([output.pathExtension.lowercaseString isEqualToString:@"json"]) {
            resolvedJSON = output;
        }
    }

    // Artifacts: for optical-flow, use --artifacts-dir or --output if dir; else explicit only
    NSString *resolvedArtifacts = artifactsDir.length ? artifactsDir
                                : ([operation isEqualToString:@"optical-flow"] && isDir(output)) ? output
                                : nil;

    TrackProcessor *p = [[TrackProcessor alloc] init];
    p.inputPath    = inputPath;
    p.jsonOutput   = resolvedJSON;
    p.artifactsDir = resolvedArtifacts;
    p.operation    = operation;
    return [p runWithError:error];
}
