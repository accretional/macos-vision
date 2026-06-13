#import "input/main.h"

static void printHelp(void) {
    printf(
        "USAGE: macos-vision input <operation> [options]\n"
        "\n"
        "Synthesise mouse and keyboard input events via CoreGraphics CGEvent.\n"
        "Requires Accessibility permission (System Settings ▸ Privacy & Security ▸\n"
        "Accessibility). The first run prompts to grant it.\n"
        "\n"
        "OPERATIONS:\n"
        "  mouse-move   Move the cursor to --x --y (or emit a drag with --drag)\n"
        "  click        Click at --x --y or the current location\n"
        "  mouse-down   Press a mouse button (pair with mouse-up for drags)\n"
        "  mouse-up     Release a mouse button\n"
        "  scroll       Scroll by --dx --dy wheel units (positive dy scrolls up)\n"
        "  key          Press --key with optional --modifiers\n"
        "\n"
        "OPTIONS:\n"
        "  --x <px>            Absolute X in global display pixels (top-left origin)\n"
        "  --y <px>            Absolute Y in global display pixels (top-left origin)\n"
        "  --dx <n>            Horizontal delta (scroll)\n"
        "  --dy <n>            Vertical delta (scroll)\n"
        "  --button <name>     left (default) | right | center\n"
        "  --count <n>         Click count (click); 2 = double-click\n"
        "  --drag <button>     mouse-move emits a drag of this button instead of a move\n"
        "  --key <name>        Key name: a-z, 0-9, left/right/up/down, return, space,\n"
        "                      escape, tab, delete, f1-f12, etc.\n"
        "  --modifiers <list>  Comma-separated: cmd, ctrl, alt/option, shift, fn\n"
        "  --json-output <p>   Write JSON envelope to this file (default: stdout)\n"
        "\n"
        "EXAMPLES:\n"
        "  macos-vision input mouse-move --x 1200 --y 400\n"
        "  macos-vision input click --button left\n"
        "  macos-vision input scroll --dy -3\n"
        "  macos-vision input key --key right --modifiers ctrl\n"
    );
}

BOOL MVDispatchInput(NSArray<NSString *> *args, NSError **error) {
    NSString *operation  = nil;
    NSString *button     = @"left";
    NSString *dragButton = nil;
    NSString *key        = nil;
    NSString *modifiers  = nil;
    NSString *jsonOutput = nil;
    double x = NAN, y = NAN, dx = 0, dy = 0;
    NSInteger count = 1;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) { printHelp(); return YES; }
        else if (![a hasPrefix:@"--"] && !operation) { operation = a; }
        else if ([a isEqualToString:@"--x"] && i+1 < (NSInteger)args.count)            { x = [args[++i] doubleValue]; }
        else if ([a isEqualToString:@"--y"] && i+1 < (NSInteger)args.count)            { y = [args[++i] doubleValue]; }
        else if ([a isEqualToString:@"--dx"] && i+1 < (NSInteger)args.count)           { dx = [args[++i] doubleValue]; }
        else if ([a isEqualToString:@"--dy"] && i+1 < (NSInteger)args.count)           { dy = [args[++i] doubleValue]; }
        else if ([a isEqualToString:@"--button"] && i+1 < (NSInteger)args.count)       { button = args[++i]; }
        else if ([a isEqualToString:@"--count"] && i+1 < (NSInteger)args.count)        { count = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--drag"] && i+1 < (NSInteger)args.count)         { dragButton = args[++i]; }
        else if ([a isEqualToString:@"--key"] && i+1 < (NSInteger)args.count)          { key = args[++i]; }
        else if ([a isEqualToString:@"--modifiers"] && i+1 < (NSInteger)args.count)    { modifiers = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)  { jsonOutput = args[++i]; }
        else {
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"input: unknown option '%@'", a]}];
            return NO;
        }
    }

    if (!operation.length) {
        printHelp();
        if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
            userInfo:@{NSLocalizedDescriptionKey: @"input: missing operation"}];
        return NO;
    }

    InputProcessor *p = [[InputProcessor alloc] init];
    p.operation  = operation;
    p.x = x; p.y = y; p.dx = dx; p.dy = dy;
    p.button     = button;
    p.count      = count;
    p.dragButton = dragButton;
    p.key        = key;
    p.modifiers  = modifiers;
    p.jsonOutput = jsonOutput;
    return [p runWithError:error];
}
