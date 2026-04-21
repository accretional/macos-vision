#import "coreimage/main.h"

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
        "USAGE: macos-vision coreimage --operation <op> [options]\n"
        "\n"
        "Apply image filters, explore available effects, and analyse visual properties.\n"
        "\n"
        "OPERATIONS:\n"
        "  apply-filter     (default) Apply a filter to an image and write the result\n"
        "  suggest-filters  Suggest applicable filters for an image (optionally apply them)\n"
        "  list-filters     List available filter names, optionally with category metadata\n"
        "\n"
        "OPTIONS:\n"
        "  --input <path>              Image file to process (required for apply-filter)\n"
        "  --operation <op>            Operation to run (default: apply-filter)\n"
        "  --output <path>             Output image file, directory, or .json path\n"
        "  --json-output <path>        Write JSON envelope to this file (default: stdout)\n"
        "  --artifacts-dir <dir>       Write rendered images here\n"
        "  --filter-name <name>        Filter name, e.g. CISepiaTone (apply-filter)\n"
        "  --filter-params <json>      JSON object of scalar filter parameters,\n"
        "                              e.g. '{\"inputIntensity\":0.8}'\n"
        "  --format <fmt>              Output image format: png (default), jpg, heif, tiff\n"
        "  --apply                     Also render images when using suggest-filters\n"
        "  --category-only             Return category metadata instead of filter names (list-filters)\n"
        "  --debug                     Emit processing_ms in output\n"
    );
}

BOOL MVDispatchCoreImage(NSArray<NSString *> *args, NSError **error) {
    NSString *inputPath    = nil;
    NSString *operation    = @"apply-filter";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSString *artifactsDir = nil;
    NSString *filterName   = nil;
    NSString *filterParams = nil;
    NSString *format       = @"png";
    BOOL applyFilters      = NO;
    BOOL categoryOnly      = NO;
    BOOL debug             = NO;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)          { inputPath    = args[++i]; }
        else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)        { operation    = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output       = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput   = args[++i]; }
        else if ([a isEqualToString:@"--artifacts-dir"] && i+1 < (NSInteger)args.count)    { artifactsDir = args[++i]; }
        else if ([a isEqualToString:@"--filter-name"] && i+1 < (NSInteger)args.count)      { filterName   = args[++i]; }
        else if ([a isEqualToString:@"--filter-params"] && i+1 < (NSInteger)args.count)    { filterParams = args[++i]; }
        else if ([a isEqualToString:@"--format"] && i+1 < (NSInteger)args.count)           { format       = args[++i]; }
        else if ([a isEqualToString:@"--apply"])         { applyFilters = YES; }
        else if ([a isEqualToString:@"--category-only"]) { categoryOnly = YES; }
        else if ([a isEqualToString:@"--debug"])          { debug        = YES; }
        else {
            fprintf(stderr, "coreimage: unknown option '%s'\n", a.UTF8String);
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"coreimage: unknown option '%@'", a]}];
            return NO;
        }
    }

    // JSON: <stem>_<op>.json naming
    NSString *opSlug = [[operation stringByReplacingOccurrencesOfString:@"-" withString:@"_"]
                                   stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *jsonName = [[NSString stringWithFormat:@"%@_%@", stem(inputPath), opSlug] stringByAppendingPathExtension:@"json"];
    NSString *resolvedJSON = nil;
    if (jsonOutput.length && !isDir(jsonOutput))        resolvedJSON = jsonOutput;
    else if (jsonOutput.length && isDir(jsonOutput))    resolvedJSON = [jsonOutput stringByAppendingPathComponent:jsonName];
    else if (output.length && isDir(output))            resolvedJSON = [output stringByAppendingPathComponent:jsonName];
    else if ([output.pathExtension.lowercaseString isEqualToString:@"json"]) resolvedJSON = output;

    // Artifacts: for apply-filter and suggest-filters only
    BOOL opUsesArtifacts = [operation isEqualToString:@"apply-filter"] || [operation isEqualToString:@"suggest-filters"];
    NSString *resolvedArtifacts = artifactsDir.length ? artifactsDir
                                : (opUsesArtifacts && isDir(output)) ? output
                                : nil;

    // Exact image output path: output when not a dir and not .json
    NSString *outputPath = nil;
    if (output.length && !isDir(output) && ![output.pathExtension.lowercaseString isEqualToString:@"json"])
        outputPath = output;

    CIProcessor *p = [[CIProcessor alloc] init];
    p.inputPath        = inputPath;
    p.jsonOutput       = resolvedJSON;
    p.artifactsDir     = resolvedArtifacts;
    p.outputPath       = outputPath;
    p.operation        = operation;
    p.filterName       = filterName;
    p.filterParamsJSON = filterParams;
    p.outputFormat     = format;
    p.applyFilters     = applyFilters;
    p.categoryOnly     = categoryOnly;
    p.debug            = debug;
    return [p runWithError:error];
}
