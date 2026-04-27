#import "imagetransfer/main.h"
#include <unistd.h>

static BOOL isDir(NSString *p) {
    if (!p.length) return NO;
    BOOL d = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&d] && d;
}

static void printHelp(void) {
    printf(
        "USAGE: macos-vision imagetransfer --operation <op> [options]\n"
        "\n"
        "List, import, and manage files on connected cameras and scanners.\n"
        "Note: USB webcams are streaming devices — use 'streamcapture list-devices' instead.\n"
        "\n"
        "OPERATIONS:\n"
        "  list-devices       List connected cameras and scanners\n"
        "  camera/files       List files on a camera's media storage\n"
        "  camera/thumbnail   Fetch a thumbnail for a file on the camera\n"
        "  camera/metadata    Fetch EXIF/metadata for a file on the camera\n"
        "  camera/import      Download file(s) from the camera to disk\n"
        "  camera/delete      Delete file(s) from the camera\n"
        "  camera/capture     Fire the shutter remotely for tethered shooting\n"
        "  camera/sync-clock  Synchronise the camera's clock to system time\n"
        "  scanner/preview    Run an overview scan and save the preview image\n"
        "  scanner/scan       Run a full scan and save the result\n"
        "\n"
        "OPTIONS:\n"
        "  --operation <op>        Operation to run (default: list-devices)\n"
        "  --output <path>         Output file or directory (import destination, scan output)\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
        "  --device-index <n>      Which device to use when multiple are found (default: 0)\n"
        "  --file-index <n>        File index within the camera's file list (default: 0)\n"
        "  --all                   Operate on all files instead of a single --file-index\n"
        "  --delete-after          Delete from device after successful import\n"
        "  --sidecars              Also download sidecar files during import\n"
        "  --thumb-size <px>       Max thumbnail dimension in pixels\n"
        "  --dpi <n>               Scan resolution in DPI (default: scanner preferred)\n"
        "  --format <fmt>          Scanner output format: tiff (default), jpeg, png\n"
        "  --catalog-timeout <s>   Seconds to wait for camera file catalog (default: 15)\n"
        "  --debug                 Emit processing_ms in output\n"
    );
}

BOOL MVDispatchImageTransfer(NSArray<NSString *> *args, NSError **error) {
    NSString *operation    = @"list-devices";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSInteger deviceIndex  = 0;
    NSInteger fileIndex    = 0;
    BOOL allFiles          = NO;
    BOOL deleteAfter       = NO;
    BOOL sidecars          = NO;
    NSInteger thumbSize    = 0;
    NSInteger dpi          = 0;
    NSString *format       = nil;  // let ICCProcessor default to "tiff"
    NSTimeInterval catalogTimeout = 15.0;
    BOOL debug             = NO;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)      { operation   = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output      = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput  = args[++i]; }
        else if ([a isEqualToString:@"--device-index"] && i+1 < (NSInteger)args.count)     { deviceIndex = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--file-index"] && i+1 < (NSInteger)args.count)       { fileIndex   = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--thumb-size"] && i+1 < (NSInteger)args.count)       { thumbSize   = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--dpi"] && i+1 < (NSInteger)args.count)              { dpi         = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--catalog-timeout"] && i+1 < (NSInteger)args.count) { catalogTimeout = [args[++i] doubleValue]; }
        else if ([a isEqualToString:@"--format"] && i+1 < (NSInteger)args.count)           { format      = args[++i]; }
        else if ([a isEqualToString:@"--all"])          { allFiles    = YES; }
        else if ([a isEqualToString:@"--delete-after"]) { deleteAfter = YES; }
        else if ([a isEqualToString:@"--sidecars"])     { sidecars    = YES; }
        else if ([a isEqualToString:@"--debug"])        { debug       = YES; }
        else if ([a isEqualToString:@"--no-stream"])    { /* explicit file mode; stream is auto-detected */ }
        else {
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"imagetransfer: unknown option '%@'", a]}];
            return NO;
        }
    }

    // JSON: no input stem; use operation slug as filename in a directory
    NSString *opSlug = [[operation stringByReplacingOccurrencesOfString:@"-" withString:@"_"]
                                   stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    NSString *jsonName = [[NSString stringWithFormat:@"imagetransfer_%@", opSlug] stringByAppendingPathExtension:@"json"];
    NSString *resolvedJSON = nil;
    if (jsonOutput.length && !isDir(jsonOutput))        resolvedJSON = jsonOutput;
    else if (jsonOutput.length && isDir(jsonOutput))    resolvedJSON = [jsonOutput stringByAppendingPathComponent:jsonName];
    else if ([output.pathExtension.lowercaseString isEqualToString:@"json"]) resolvedJSON = output;

    // Stream-out: auto-detect when stdout is piped for device→stream operations
    static NSSet *streamableOps = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        streamableOps = [NSSet setWithArray:@[@"camera/thumbnail", @"scanner/preview", @"scanner/scan"]];
    });
    BOOL stdoutPiped = !isatty(STDOUT_FILENO);
    BOOL streamOut   = stdoutPiped && [streamableOps containsObject:operation];

    ICCProcessor *p = [[ICCProcessor alloc] init];
    p.operation        = operation;
    p.jsonOutput       = resolvedJSON;
    p.deviceIndex      = deviceIndex;
    p.fileIndex        = fileIndex;
    p.allFiles         = allFiles;
    p.deleteAfter      = deleteAfter;
    p.downloadSidecars = sidecars;
    p.thumbSize        = thumbSize;
    p.scanDPI          = (NSUInteger)dpi;
    p.catalogTimeout   = catalogTimeout;
    p.debug            = debug;
    p.streamOut        = streamOut;
    if (format.length)  p.outputFormat = format;
    if (output.length)  p.outputPath   = output;
    return [p runWithError:error];
}
