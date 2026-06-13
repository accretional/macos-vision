#import "window/main.h"
#import <Cocoa/Cocoa.h>
#import <ApplicationServices/ApplicationServices.h>

NSString *const WindowErrorDomain = @"WindowErrorDomain";

typedef NS_ENUM(NSInteger, WindowError) {
    WindowErrorBadOperation = 1,
    WindowErrorBadArgument,
    WindowErrorNotTrusted,
    WindowErrorNoWindow,
    WindowErrorNoDisplay,
};

// ── Coordinate model ──────────────────────────────────────────────────────────
// NSScreen frames use AppKit coordinates (origin bottom-left, y up). The
// Accessibility API and CoreGraphics use a global space whose origin is the
// top-left of the primary display, y down. The primary display is screens[0];
// its AppKit origin is (0,0) and its height is the conversion pivot.
static CGFloat MVPrimaryHeight(void) {
    NSArray<NSScreen *> *screens = NSScreen.screens;
    if (!screens.count) return 0;
    return screens[0].frame.size.height;
}

// Convert an AppKit rect (bottom-left origin) to a CG/AX rect (top-left origin).
static CGRect MVAppKitToCG(NSRect r) {
    CGFloat ph = MVPrimaryHeight();
    return CGRectMake(r.origin.x, ph - (r.origin.y + r.size.height), r.size.width, r.size.height);
}

// ── Accessibility trust ───────────────────────────────────────────────────────
static BOOL WindowEnsureTrusted(NSError **error) {
    NSDictionary *opts = @{(__bridge NSString *)kAXTrustedCheckOptionPrompt: @YES};
    if (AXIsProcessTrustedWithOptions((__bridge CFDictionaryRef)opts)) return YES;
    if (error) *error = [NSError errorWithDomain:WindowErrorDomain code:WindowErrorNotTrusted
        userInfo:@{NSLocalizedDescriptionKey:
            @"window control requires Accessibility permission. Grant it in System Settings ▸ "
            @"Privacy & Security ▸ Accessibility (add the terminal or macos-vision), then retry."}];
    return NO;
}

@implementation WindowProcessor

- (instancetype)init {
    if ((self = [super init])) { _x = NAN; _y = NAN; _w = NAN; _h = NAN; }
    return self;
}

// Displays as CG-space frames, ordered by NSScreen index. Index 0 is primary.
- (NSArray<NSDictionary *> *)displays {
    NSMutableArray *out = [NSMutableArray array];
    NSInteger idx = 0;
    for (NSScreen *s in NSScreen.screens) {
        CGRect cg  = MVAppKitToCG(s.frame);
        CGRect vis = MVAppKitToCG(s.visibleFrame);
        CGFloat scale = s.backingScaleFactor;
        out[out.count] = @{
            @"index": @(idx),
            @"main": @(idx == 0),
            @"frame":        @{@"x": @(cg.origin.x),  @"y": @(cg.origin.y),  @"w": @(cg.size.width),  @"h": @(cg.size.height)},
            @"visibleFrame": @{@"x": @(vis.origin.x), @"y": @(vis.origin.y), @"w": @(vis.size.width), @"h": @(vis.size.height)},
            @"scale": @(scale),
        };
        idx++;
    }
    return out;
}

// CG frame for a display dict's key ("frame" or "visibleFrame").
static CGRect MVRectFromDict(NSDictionary *d, NSString *key) {
    NSDictionary *r = d[key];
    return CGRectMake([r[@"x"] doubleValue], [r[@"y"] doubleValue], [r[@"w"] doubleValue], [r[@"h"] doubleValue]);
}

// Index of the display whose frame contains the given CG center, else max overlap.
- (NSInteger)displayIndexForRect:(CGRect)win displays:(NSArray<NSDictionary *> *)displays {
    CGPoint c = CGPointMake(CGRectGetMidX(win), CGRectGetMidY(win));
    NSInteger best = 0; CGFloat bestArea = -1;
    for (NSDictionary *d in displays) {
        CGRect f = MVRectFromDict(d, @"frame");
        if (CGRectContainsPoint(f, c)) return [d[@"index"] integerValue];
        CGRect inter = CGRectIntersection(f, win);
        CGFloat area = CGRectIsNull(inter) ? 0 : inter.size.width * inter.size.height;
        if (area > bestArea) { bestArea = area; best = [d[@"index"] integerValue]; }
    }
    return best;
}

// ── Focused window access ─────────────────────────────────────────────────────
- (AXUIElementRef)copyFocusedWindow:(pid_t *)outPid appName:(NSString **)outName error:(NSError **)error CF_RETURNS_RETAINED {
    NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
    if (!front) {
        if (error) *error = [NSError errorWithDomain:WindowErrorDomain code:WindowErrorNoWindow
            userInfo:@{NSLocalizedDescriptionKey: @"no frontmost application"}];
        return NULL;
    }
    if (outPid)  *outPid  = front.processIdentifier;
    if (outName) *outName = front.localizedName ?: @"";
    AXUIElementRef app = AXUIElementCreateApplication(front.processIdentifier);
    CFTypeRef win = NULL;
    AXError e = AXUIElementCopyAttributeValue(app, kAXFocusedWindowAttribute, &win);
    CFRelease(app);
    if (e != kAXErrorSuccess || !win) {
        if (error) *error = [NSError errorWithDomain:WindowErrorDomain code:WindowErrorNoWindow
            userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
                @"could not read the focused window of '%@' (AXError %d)", front.localizedName ?: @"?", (int)e]}];
        return NULL;
    }
    return (AXUIElementRef)win;
}

static BOOL MVGetWindowFrame(AXUIElementRef win, CGRect *out) {
    CFTypeRef posVal = NULL, sizeVal = NULL;
    CGPoint pos = CGPointZero; CGSize sz = CGSizeZero;
    BOOL ok = YES;
    if (AXUIElementCopyAttributeValue(win, kAXPositionAttribute, &posVal) == kAXErrorSuccess && posVal) {
        AXValueGetValue((AXValueRef)posVal, kAXValueCGPointType, &pos);
        CFRelease(posVal);
    } else ok = NO;
    if (AXUIElementCopyAttributeValue(win, kAXSizeAttribute, &sizeVal) == kAXErrorSuccess && sizeVal) {
        AXValueGetValue((AXValueRef)sizeVal, kAXValueCGSizeType, &sz);
        CFRelease(sizeVal);
    } else ok = NO;
    if (ok) *out = CGRectMake(pos.x, pos.y, sz.width, sz.height);
    return ok;
}

static BOOL MVSetWindowFrame(AXUIElementRef win, CGRect frame, BOOL setPos, BOOL setSize) {
    BOOL ok = YES;
    // Set size first, then position: some apps clamp position against the old size.
    if (setSize) {
        CGSize sz = frame.size;
        AXValueRef v = AXValueCreate(kAXValueCGSizeType, &sz);
        if (AXUIElementSetAttributeValue(win, kAXSizeAttribute, v) != kAXErrorSuccess) ok = NO;
        CFRelease(v);
    }
    if (setPos) {
        CGPoint p = frame.origin;
        AXValueRef v = AXValueCreate(kAXValueCGPointType, &p);
        if (AXUIElementSetAttributeValue(win, kAXPositionAttribute, v) != kAXErrorSuccess) ok = NO;
        CFRelease(v);
    }
    return ok;
}

- (void)emit:(NSDictionary *)payload {
    NSMutableDictionary *env = [@{@"operation": self.operation ?: @""} mutableCopy];
    [env addEntriesFromDictionary:payload];
    NSData *data = [NSJSONSerialization dataWithJSONObject:env options:NSJSONWritingPrettyPrinted error:nil];
    NSString *json = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (self.jsonOutput.length) [json writeToFile:self.jsonOutput atomically:YES encoding:NSUTF8StringEncoding error:nil];
    else printf("%s\n", json.UTF8String);
}

static NSDictionary *MVRectDict(CGRect r) {
    return @{@"x": @(r.origin.x), @"y": @(r.origin.y), @"w": @(r.size.width), @"h": @(r.size.height)};
}

// Resolve the target display index from --display (index | next | prev | left | right).
- (NSInteger)resolveTargetIndex:(NSArray<NSDictionary *> *)displays current:(NSInteger)cur currentFrame:(CGRect)curFrame {
    NSString *t = self.displayTarget.lowercaseString ?: @"next";
    NSInteger n = (NSInteger)displays.count;
    if ([t isEqualToString:@"next"]) return (cur + 1) % n;
    if ([t isEqualToString:@"prev"] || [t isEqualToString:@"previous"]) return (cur - 1 + n) % n;
    if ([t isEqualToString:@"left"] || [t isEqualToString:@"right"]) {
        BOOL wantLeft = [t isEqualToString:@"left"];
        CGRect curCG = MVRectFromDict(displays[cur], @"frame");
        NSInteger pick = -1; CGFloat bestDist = CGFLOAT_MAX;
        for (NSDictionary *d in displays) {
            NSInteger di = [d[@"index"] integerValue];
            if (di == cur) continue;
            CGRect f = MVRectFromDict(d, @"frame");
            BOOL isLeft  = f.origin.x < curCG.origin.x;
            BOOL isRight = f.origin.x > curCG.origin.x;
            if ((wantLeft && isLeft) || (!wantLeft && isRight)) {
                CGFloat dist = fabs(f.origin.x - curCG.origin.x);
                if (dist < bestDist) { bestDist = dist; pick = di; }
            }
        }
        // No display in that direction → fall back to cyclic so a throw still moves.
        if (pick < 0) return wantLeft ? (cur - 1 + n) % n : (cur + 1) % n;
        return pick;
    }
    // Numeric index
    NSInteger idx = [self.displayTarget integerValue];
    if (idx < 0 || idx >= n) return cur;
    return idx;
}

- (BOOL)runWithError:(NSError **)error {
    NSString *op = self.operation.length ? self.operation : @"";

    if ([op isEqualToString:@"list-displays"]) {
        [self emit:@{@"displays": [self displays], @"count": @(NSScreen.screens.count)}];
        return YES;
    }

    if (!WindowEnsureTrusted(error)) return NO;

    if ([op isEqualToString:@"info"]) {
        pid_t pid = 0; NSString *appName = nil;
        AXUIElementRef win = [self copyFocusedWindow:&pid appName:&appName error:error];
        if (!win) return NO;
        CGRect frame;
        if (!MVGetWindowFrame(win, &frame)) {
            CFRelease(win);
            if (error) *error = [NSError errorWithDomain:WindowErrorDomain code:WindowErrorNoWindow
                userInfo:@{NSLocalizedDescriptionKey: @"could not read focused window frame"}];
            return NO;
        }
        CFRelease(win);
        NSArray *displays = [self displays];
        NSInteger di = [self displayIndexForRect:frame displays:displays];
        [self emit:@{@"app": appName ?: @"", @"pid": @(pid), @"frame": MVRectDict(frame),
                     @"display": @(di), @"displays": displays}];
        return YES;
    }

    if ([op isEqualToString:@"move"]) {
        AXUIElementRef win = [self copyFocusedWindow:NULL appName:NULL error:error];
        if (!win) return NO;
        CGRect cur;
        if (!MVGetWindowFrame(win, &cur)) { CFRelease(win);
            if (error) *error = [NSError errorWithDomain:WindowErrorDomain code:WindowErrorNoWindow userInfo:@{NSLocalizedDescriptionKey:@"could not read focused window frame"}];
            return NO; }
        CGRect target = cur;
        BOOL setPos = NO, setSize = NO;
        if (!isnan(self.x)) { target.origin.x = self.x; setPos = YES; }
        if (!isnan(self.y)) { target.origin.y = self.y; setPos = YES; }
        if (!isnan(self.w)) { target.size.width = self.w; setSize = YES; }
        if (!isnan(self.h)) { target.size.height = self.h; setSize = YES; }
        BOOL ok = MVSetWindowFrame(win, target, setPos, setSize);
        CGRect after; MVGetWindowFrame(win, &after);
        CFRelease(win);
        if (!ok) {
            if (error) *error = [NSError errorWithDomain:WindowErrorDomain code:WindowErrorNoWindow
                userInfo:@{NSLocalizedDescriptionKey: @"failed to set window frame (the app may restrict resizing/moving)"}];
            return NO;
        }
        [self emit:@{@"before": MVRectDict(cur), @"after": MVRectDict(after)}];
        return YES;
    }

    if ([op isEqualToString:@"maximize"]) {
        AXUIElementRef win = [self copyFocusedWindow:NULL appName:NULL error:error];
        if (!win) return NO;
        CGRect cur;
        if (!MVGetWindowFrame(win, &cur)) { CFRelease(win);
            if (error) *error = [NSError errorWithDomain:WindowErrorDomain code:WindowErrorNoWindow userInfo:@{NSLocalizedDescriptionKey:@"could not read focused window frame"}];
            return NO; }
        NSArray<NSDictionary *> *displays = [self displays];
        NSInteger di = [self displayIndexForRect:cur displays:displays];
        CGRect vis = MVRectFromDict(displays[di], @"visibleFrame");
        BOOL ok = MVSetWindowFrame(win, vis, YES, YES);
        CGRect after; MVGetWindowFrame(win, &after);
        CFRelease(win);
        if (!ok) {
            if (error) *error = [NSError errorWithDomain:WindowErrorDomain code:WindowErrorNoWindow
                userInfo:@{NSLocalizedDescriptionKey: @"failed to maximize window"}];
            return NO;
        }
        [self emit:@{@"display": @(di), @"before": MVRectDict(cur), @"after": MVRectDict(after)}];
        return YES;
    }

    if ([op isEqualToString:@"minimize"]) {
        AXUIElementRef win = [self copyFocusedWindow:NULL appName:NULL error:error];
        if (!win) return NO;
        AXError e = AXUIElementSetAttributeValue(win, kAXMinimizedAttribute, kCFBooleanTrue);
        CFRelease(win);
        if (e != kAXErrorSuccess) {
            if (error) *error = [NSError errorWithDomain:WindowErrorDomain code:WindowErrorNoWindow
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"failed to minimize window (AXError %d)", (int)e]}];
            return NO;
        }
        [self emit:@{@"minimized": @YES}];
        return YES;
    }

    if ([op isEqualToString:@"move-to-display"]) {
        AXUIElementRef win = [self copyFocusedWindow:NULL appName:NULL error:error];
        if (!win) return NO;
        CGRect cur;
        if (!MVGetWindowFrame(win, &cur)) { CFRelease(win);
            if (error) *error = [NSError errorWithDomain:WindowErrorDomain code:WindowErrorNoWindow userInfo:@{NSLocalizedDescriptionKey:@"could not read focused window frame"}];
            return NO; }
        NSArray<NSDictionary *> *displays = [self displays];
        if (displays.count < 2 && ![self.displayTarget length]) {
            // Only one display: nothing to throw to.
        }
        NSInteger curIdx = [self displayIndexForRect:cur displays:displays];
        NSInteger tgtIdx = [self resolveTargetIndex:displays current:curIdx currentFrame:cur];

        CGRect curCG = MVRectFromDict(displays[curIdx], @"frame");
        CGRect tgtVis = MVRectFromDict(displays[tgtIdx], @"visibleFrame");

        // Preserve the window's relative top-left within its current display,
        // then clamp the size to fit the target's usable area.
        CGFloat relX = curCG.size.width  > 0 ? (cur.origin.x - curCG.origin.x) / curCG.size.width  : 0;
        CGFloat relY = curCG.size.height > 0 ? (cur.origin.y - curCG.origin.y) / curCG.size.height : 0;

        CGRect target;
        target.size.width  = MIN(cur.size.width,  tgtVis.size.width);
        target.size.height = MIN(cur.size.height, tgtVis.size.height);
        target.origin.x = tgtVis.origin.x + relX * tgtVis.size.width;
        target.origin.y = tgtVis.origin.y + relY * tgtVis.size.height;
        // Keep fully on-screen.
        target.origin.x = MIN(MAX(target.origin.x, tgtVis.origin.x), CGRectGetMaxX(tgtVis) - target.size.width);
        target.origin.y = MIN(MAX(target.origin.y, tgtVis.origin.y), CGRectGetMaxY(tgtVis) - target.size.height);

        BOOL ok = MVSetWindowFrame(win, target, YES, YES);
        CGRect after; MVGetWindowFrame(win, &after);
        CFRelease(win);
        if (!ok) {
            if (error) *error = [NSError errorWithDomain:WindowErrorDomain code:WindowErrorNoWindow
                userInfo:@{NSLocalizedDescriptionKey: @"failed to move window to display"}];
            return NO;
        }
        [self emit:@{@"fromDisplay": @(curIdx), @"toDisplay": @(tgtIdx),
                     @"before": MVRectDict(cur), @"after": MVRectDict(after)}];
        return YES;
    }

    if (error) *error = [NSError errorWithDomain:WindowErrorDomain code:WindowErrorBadOperation
        userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:
            @"unknown operation '%@'. Supported: list-displays, info, move, move-to-display, maximize, minimize", op]}];
    return NO;
}

@end
