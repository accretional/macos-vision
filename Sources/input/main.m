#import "input/main.h"
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

NSString *const InputErrorDomain = @"InputErrorDomain";

typedef NS_ENUM(NSInteger, InputError) {
    InputErrorBadOperation = 1,
    InputErrorBadArgument,
    InputErrorNotTrusted,
    InputErrorPostFailed,
};

// ── Accessibility trust ───────────────────────────────────────────────────────
// Posting synthetic events to other applications requires the process to be
// trusted for Accessibility. Prompt once, then report a clear error if denied.
static BOOL InputEnsureTrusted(NSError **error) {
    NSDictionary *opts = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    if (AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts)) return YES;
    if (error) *error = [NSError errorWithDomain:InputErrorDomain code:InputErrorNotTrusted
        userInfo:@{NSLocalizedDescriptionKey:
            @"input requires Accessibility permission. Grant it in System Settings ▸ "
            @"Privacy & Security ▸ Accessibility (add the terminal or macos-vision), then retry."}];
    return NO;
}

// ── Key name → virtual keycode ────────────────────────────────────────────────
static CGKeyCode InputKeyCode(NSString *name, BOOL *ok) {
    *ok = YES;
    static NSDictionary<NSString *, NSNumber *> *map = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"a": @0, @"s": @1, @"d": @2, @"f": @3, @"h": @4, @"g": @5, @"z": @6,
            @"x": @7, @"c": @8, @"v": @9, @"b": @11, @"q": @12, @"w": @13, @"e": @14,
            @"r": @15, @"y": @16, @"t": @17, @"1": @18, @"2": @19, @"3": @20, @"4": @21,
            @"6": @22, @"5": @23, @"=": @24, @"9": @25, @"7": @26, @"-": @27, @"8": @28,
            @"0": @29, @"]": @30, @"o": @31, @"u": @32, @"[": @33, @"i": @34, @"p": @35,
            @"l": @37, @"j": @38, @"'": @39, @"k": @40, @";": @41, @"\\": @42, @",": @43,
            @"/": @44, @"n": @45, @"m": @46, @".": @47, @"`": @50,
            @"return": @36, @"enter": @36, @"tab": @48, @"space": @49, @"delete": @51,
            @"backspace": @51, @"escape": @53, @"esc": @53, @"forwarddelete": @117,
            @"left": @123, @"right": @124, @"down": @125, @"up": @126,
            @"home": @115, @"end": @119, @"pageup": @116, @"pagedown": @121,
            @"f1": @122, @"f2": @120, @"f3": @99, @"f4": @118, @"f5": @96, @"f6": @97,
            @"f7": @98, @"f8": @100, @"f9": @101, @"f10": @109, @"f11": @103, @"f12": @111,
        };
    });
    NSNumber *code = map[name.lowercaseString];
    if (!code) { *ok = NO; return 0; }
    return (CGKeyCode)code.unsignedShortValue;
}

static CGEventFlags InputModifierFlags(NSString *modifiers) {
    CGEventFlags flags = 0;
    if (!modifiers.length) return flags;
    for (NSString *raw in [modifiers componentsSeparatedByString:@","]) {
        NSString *m = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
        if ([m isEqualToString:@"cmd"] || [m isEqualToString:@"command"] || [m isEqualToString:@"meta"])
            flags |= kCGEventFlagMaskCommand;
        else if ([m isEqualToString:@"ctrl"] || [m isEqualToString:@"control"])
            flags |= kCGEventFlagMaskControl;
        else if ([m isEqualToString:@"alt"] || [m isEqualToString:@"option"] || [m isEqualToString:@"opt"])
            flags |= kCGEventFlagMaskAlternate;
        else if ([m isEqualToString:@"shift"])
            flags |= kCGEventFlagMaskShift;
        else if ([m isEqualToString:@"fn"] || [m isEqualToString:@"function"])
            flags |= kCGEventFlagMaskSecondaryFn;
    }
    return flags;
}

// ── Mouse button parsing ──────────────────────────────────────────────────────
static BOOL InputButtonTypes(NSString *button, CGMouseButton *btn,
                             CGEventType *downType, CGEventType *upType, CGEventType *dragType) {
    NSString *b = button.length ? button.lowercaseString : @"left";
    if ([b isEqualToString:@"left"]) {
        *btn = kCGMouseButtonLeft;
        *downType = kCGEventLeftMouseDown; *upType = kCGEventLeftMouseUp; *dragType = kCGEventLeftMouseDragged;
        return YES;
    } else if ([b isEqualToString:@"right"]) {
        *btn = kCGMouseButtonRight;
        *downType = kCGEventRightMouseDown; *upType = kCGEventRightMouseUp; *dragType = kCGEventRightMouseDragged;
        return YES;
    } else if ([b isEqualToString:@"center"] || [b isEqualToString:@"middle"]) {
        *btn = kCGMouseButtonCenter;
        *downType = kCGEventOtherMouseDown; *upType = kCGEventOtherMouseUp; *dragType = kCGEventOtherMouseDragged;
        return YES;
    }
    return NO;
}

@implementation InputProcessor

- (instancetype)init {
    if ((self = [super init])) {
        _x = NAN; _y = NAN;
        _button = @"left";
        _count = 1;
    }
    return self;
}

- (CGPoint)resolvePoint {
    if (!isnan(_x) && !isnan(_y)) return CGPointMake(_x, _y);
    // Current cursor location (global, top-left origin).
    CGEventRef snapshot = CGEventCreate(NULL);
    CGPoint loc = CGEventGetLocation(snapshot);
    if (snapshot) CFRelease(snapshot);
    return loc;
}

- (void)emit:(NSDictionary *)payload {
    NSMutableDictionary *env = [@{@"operation": self.operation ?: @""} mutableCopy];
    [env addEntriesFromDictionary:payload];
    NSData *data = [NSJSONSerialization dataWithJSONObject:env options:NSJSONWritingPrettyPrinted error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (self.jsonOutput.length) {
        [json writeToFile:self.jsonOutput atomically:YES encoding:NSUTF8StringEncoding error:nil];
    } else {
        printf("%s\n", json.UTF8String);
    }
}

- (BOOL)runWithError:(NSError **)error {
    NSString *op = self.operation.length ? self.operation : @"";
    if (!InputEnsureTrusted(error)) return NO;

    if ([op isEqualToString:@"mouse-move"]) {
        CGPoint p = [self resolvePoint];
        CGEventType type = kCGEventMouseMoved;
        CGMouseButton btn = kCGMouseButtonLeft;
        if (self.dragButton.length) {
            CGEventType d, u, dr;
            if (!InputButtonTypes(self.dragButton, &btn, &d, &u, &dr)) {
                if (error) *error = [NSError errorWithDomain:InputErrorDomain code:InputErrorBadArgument
                    userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"unknown --drag button '%@'", self.dragButton]}];
                return NO;
            }
            type = dr;
        }
        CGEventRef ev = CGEventCreateMouseEvent(NULL, type, p, btn);
        if (!ev) { if (error) *error = [NSError errorWithDomain:InputErrorDomain code:InputErrorPostFailed userInfo:@{NSLocalizedDescriptionKey:@"failed to create mouse event"}]; return NO; }
        CGEventPost(kCGHIDEventTap, ev);
        CFRelease(ev);
        [self emit:@{@"x": @(p.x), @"y": @(p.y), @"drag": self.dragButton ?: [NSNull null]}];
        return YES;
    }

    if ([op isEqualToString:@"mouse-down"] || [op isEqualToString:@"mouse-up"]) {
        CGPoint p = [self resolvePoint];
        CGMouseButton btn; CGEventType downType, upType, dragType;
        if (!InputButtonTypes(self.button, &btn, &downType, &upType, &dragType)) {
            if (error) *error = [NSError errorWithDomain:InputErrorDomain code:InputErrorBadArgument
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"unknown --button '%@'", self.button]}];
            return NO;
        }
        CGEventType type = [op isEqualToString:@"mouse-down"] ? downType : upType;
        CGEventRef ev = CGEventCreateMouseEvent(NULL, type, p, btn);
        CGEventPost(kCGHIDEventTap, ev);
        CFRelease(ev);
        [self emit:@{@"x": @(p.x), @"y": @(p.y), @"button": self.button ?: @"left"}];
        return YES;
    }

    if ([op isEqualToString:@"click"]) {
        CGPoint p = [self resolvePoint];
        CGMouseButton btn; CGEventType downType, upType, dragType;
        if (!InputButtonTypes(self.button, &btn, &downType, &upType, &dragType)) {
            if (error) *error = [NSError errorWithDomain:InputErrorDomain code:InputErrorBadArgument
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"unknown --button '%@'", self.button]}];
            return NO;
        }
        NSInteger clicks = self.count > 0 ? self.count : 1;
        for (NSInteger c = 1; c <= clicks; c++) {
            CGEventRef down = CGEventCreateMouseEvent(NULL, downType, p, btn);
            CGEventRef up   = CGEventCreateMouseEvent(NULL, upType,   p, btn);
            // Set the click-state field so double-clicks register as such.
            CGEventSetIntegerValueField(down, kCGMouseEventClickState, c);
            CGEventSetIntegerValueField(up,   kCGMouseEventClickState, c);
            CGEventPost(kCGHIDEventTap, down);
            CGEventPost(kCGHIDEventTap, up);
            CFRelease(down); CFRelease(up);
        }
        [self emit:@{@"x": @(p.x), @"y": @(p.y), @"button": self.button ?: @"left", @"count": @(clicks)}];
        return YES;
    }

    if ([op isEqualToString:@"scroll"]) {
        // Wheel units: field 1 = vertical, field 2 = horizontal. Positive dy scrolls up.
        int32_t vy = (int32_t)llround(self.dy);
        int32_t vx = (int32_t)llround(self.dx);
        CGEventRef ev = CGEventCreateScrollWheelEvent(NULL, kCGScrollEventUnitLine, 2, vy, vx);
        if (!ev) { if (error) *error = [NSError errorWithDomain:InputErrorDomain code:InputErrorPostFailed userInfo:@{NSLocalizedDescriptionKey:@"failed to create scroll event"}]; return NO; }
        CGEventPost(kCGHIDEventTap, ev);
        CFRelease(ev);
        [self emit:@{@"dx": @(vx), @"dy": @(vy)}];
        return YES;
    }

    if ([op isEqualToString:@"key"]) {
        if (!self.key.length) {
            if (error) *error = [NSError errorWithDomain:InputErrorDomain code:InputErrorBadArgument
                userInfo:@{NSLocalizedDescriptionKey: @"key requires --key <name>"}];
            return NO;
        }
        BOOL ok = NO;
        CGKeyCode code = InputKeyCode(self.key, &ok);
        if (!ok) {
            if (error) *error = [NSError errorWithDomain:InputErrorDomain code:InputErrorBadArgument
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"unknown --key '%@'", self.key]}];
            return NO;
        }
        CGEventFlags flags = InputModifierFlags(self.modifiers);
        CGEventRef down = CGEventCreateKeyboardEvent(NULL, code, true);
        CGEventRef up   = CGEventCreateKeyboardEvent(NULL, code, false);
        if (flags) { CGEventSetFlags(down, flags); CGEventSetFlags(up, flags); }
        CGEventPost(kCGHIDEventTap, down);
        CGEventPost(kCGHIDEventTap, up);
        CFRelease(down); CFRelease(up);
        [self emit:@{@"key": self.key, @"modifiers": self.modifiers ?: @"", @"keycode": @(code)}];
        return YES;
    }

    if (error) *error = [NSError errorWithDomain:InputErrorDomain code:InputErrorBadOperation
        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"unknown operation '%@'. Supported: mouse-move, click, mouse-down, mouse-up, scroll, key", op]}];
    return NO;
}

@end
