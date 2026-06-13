#import "window/main.h"

static void printHelp(void) {
    printf(
        "USAGE: macos-vision window <operation> [options]\n"
        "\n"
        "Inspect display geometry and reposition the focused window via the\n"
        "Accessibility API. move / move-to-display require Accessibility permission\n"
        "(System Settings ▸ Privacy & Security ▸ Accessibility).\n"
        "\n"
        "OPERATIONS:\n"
        "  list-displays    List displays with CG-space frames and scale\n"
        "  info             Report the focused window frame and its display\n"
        "  move             Move/resize the focused window (--x --y --w --h)\n"
        "  move-to-display  Move the focused window to another display\n"
        "  maximize         Resize the focused window to fill its display\n"
        "  minimize         Minimize the focused window\n"
        "\n"
        "OPTIONS:\n"
        "  --display <t>     move-to-display target: index | next | prev | left | right\n"
        "  --x <px>          New X (move), global pixels, top-left origin\n"
        "  --y <px>          New Y (move)\n"
        "  --w <px>          New width (move)\n"
        "  --h <px>          New height (move)\n"
        "  --json-output <p> Write JSON envelope to this file (default: stdout)\n"
        "\n"
        "EXAMPLES:\n"
        "  macos-vision window list-displays\n"
        "  macos-vision window info\n"
        "  macos-vision window move --x 100 --y 100 --w 1280 --h 800\n"
        "  macos-vision window move-to-display --display right\n"
    );
}

BOOL MVDispatchWindow(NSArray<NSString *> *args, NSError **error) {
    NSString *operation     = nil;
    NSString *displayTarget = nil;
    NSString *jsonOutput    = nil;
    double x = NAN, y = NAN, w = NAN, h = NAN;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) { printHelp(); return YES; }
        else if (![a hasPrefix:@"--"] && !operation) { operation = a; }
        else if ([a isEqualToString:@"--display"] && i+1 < (NSInteger)args.count)      { displayTarget = args[++i]; }
        else if ([a isEqualToString:@"--x"] && i+1 < (NSInteger)args.count)            { x = [args[++i] doubleValue]; }
        else if ([a isEqualToString:@"--y"] && i+1 < (NSInteger)args.count)            { y = [args[++i] doubleValue]; }
        else if ([a isEqualToString:@"--w"] && i+1 < (NSInteger)args.count)            { w = [args[++i] doubleValue]; }
        else if ([a isEqualToString:@"--h"] && i+1 < (NSInteger)args.count)            { h = [args[++i] doubleValue]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)  { jsonOutput = args[++i]; }
        else {
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"window: unknown option '%@'", a]}];
            return NO;
        }
    }

    if (!operation.length) {
        printHelp();
        if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"window: missing operation"}];
        return NO;
    }

    WindowProcessor *p = [[WindowProcessor alloc] init];
    p.operation     = operation;
    p.displayTarget = displayTarget;
    p.x = x; p.y = y; p.w = w; p.h = h;
    p.jsonOutput    = jsonOutput;
    return [p runWithError:error];
}
