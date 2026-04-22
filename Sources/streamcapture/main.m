#import "main.h"
#import "common/MVJsonEmit.h"
#import "common/MVMjpegStream.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <Cocoa/Cocoa.h>
#import <signal.h>

static NSString *const CaptureErrorDomain = @"CaptureError";

// ── Signal handler ────────────────────────────────────────────────────────────

static volatile sig_atomic_t gStopCapture = 0;
static void captureSignalHandler(int sig) { gStopCapture = 1; }

// ── JSON helpers ──────────────────────────────────────────────────────────────

static void CPrintJSON(id obj) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    if (data) printf("%s\n", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}

static void CPrintNDJSON(NSDictionary *obj) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    if (data) {
        printf("%s\n", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
        fflush(stdout);
    }
}

// ── Frame capture delegate ────────────────────────────────────────────────────

@interface CaptureFrameDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (atomic) BOOL shouldCapture;
@property (nonatomic) dispatch_semaphore_t doneSemaphore;
@property (nonatomic, strong, nullable) CIImage *capturedImage;
- (instancetype)initWithSemaphore:(dispatch_semaphore_t)sem;
@end

@implementation CaptureFrameDelegate
- (instancetype)initWithSemaphore:(dispatch_semaphore_t)sem {
    if (self = [super init]) { _doneSemaphore = sem; }
    return self;
}
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
         fromConnection:(AVCaptureConnection *)connection {
    if (!self.shouldCapture) return;
    self.shouldCapture = NO;
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (pixelBuffer) {
        self.capturedImage = [[CIImage alloc] initWithCVImageBuffer:pixelBuffer];
    }
    dispatch_semaphore_signal(self.doneSemaphore);
}
@end

// ── Movie file output delegate ────────────────────────────────────────────────

@interface CaptureMovieDelegate : NSObject <AVCaptureFileOutputRecordingDelegate>
@property (nonatomic) BOOL finished;
@property (nonatomic, strong, nullable) NSError *recordingError;
@end

@implementation CaptureMovieDelegate
- (void)captureOutput:(AVCaptureFileOutput *)output
    didFinishRecordingToOutputFileAtURL:(NSURL *)url
                        fromConnections:(NSArray<AVCaptureConnection *> *)connections
                                  error:(NSError *)error {
    self.recordingError = error;
    self.finished = YES;
}
@end

// ── Stream video delegate ─────────────────────────────────────────────────────

@interface CaptureStreamDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) MVMjpegWriter *writer;
@property (nonatomic, strong) CIContext *ciContext;
@end

@implementation CaptureStreamDelegate
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
         fromConnection:(AVCaptureConnection *)connection {
    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;
    CIImage *ciImage = [[CIImage alloc] initWithCVImageBuffer:pixelBuffer];
    // Correct built-in camera orientation (frames arrive rotated 180°)
    // ciImage = [ciImage imageByApplyingCGOrientation:kCGImagePropertyOrientationDown];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSData *jpeg = [self.ciContext
        JPEGRepresentationOfImage:ciImage
                      colorSpace:cs
                         options:@{(id)kCGImageDestinationLossyCompressionQuality: @0.85}];
    CGColorSpaceRelease(cs);
    if (jpeg) [self.writer writeFrame:jpeg extraHeaders:nil];
}
@end

// ── Barcode delegate ──────────────────────────────────────────────────────────

@interface CaptureBarcodeDelegate : NSObject <AVCaptureMetadataOutputObjectsDelegate>
@end

@implementation CaptureBarcodeDelegate
- (void)captureOutput:(AVCaptureOutput *)output
    didOutputMetadataObjects:(NSArray<__kindof AVMetadataObject *> *)objects
             fromConnection:(AVCaptureConnection *)connection {
    for (AVMetadataObject *obj in objects) {
        if (![obj isKindOfClass:[AVMetadataMachineReadableCodeObject class]]) continue;
        AVMetadataMachineReadableCodeObject *code = (AVMetadataMachineReadableCodeObject *)obj;
        NSMutableDictionary *line = [NSMutableDictionary dictionary];
        line[@"timestamp"] = @([[NSDate date] timeIntervalSince1970]);
        // Strip AVMetadataObjectType prefix for readable type names
        NSString *rawType = code.type ?: @"unknown";
        line[@"type"] = rawType;
        if (code.stringValue) line[@"value"] = code.stringValue;
        CGRect b = code.bounds;
        line[@"bounds"] = @{@"x": @(b.origin.x), @"y": @(b.origin.y),
                             @"w": @(b.size.width), @"h": @(b.size.height)};
        CPrintNDJSON(line);
    }
}
@end

// ── Helpers ───────────────────────────────────────────────────────────────────

// Map user-friendly barcode type name → AVFoundation metadata object type string.
static NSString * _Nullable CAVBarcodeType(NSString *name) {
    static NSDictionary<NSString *, NSString *> *map;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        map = @{
            @"qr":          AVMetadataObjectTypeQRCode,
            @"ean13":       AVMetadataObjectTypeEAN13Code,
            @"ean8":        AVMetadataObjectTypeEAN8Code,
            @"upce":        AVMetadataObjectTypeUPCECode,
            @"code128":     AVMetadataObjectTypeCode128Code,
            @"code39":      AVMetadataObjectTypeCode39Code,
            @"code93":      AVMetadataObjectTypeCode93Code,
            @"pdf417":      AVMetadataObjectTypePDF417Code,
            @"aztec":       AVMetadataObjectTypeAztecCode,
            @"datamatrix":  AVMetadataObjectTypeDataMatrixCode,
            @"itf14":       AVMetadataObjectTypeITF14Code,
            @"i2of5":       AVMetadataObjectTypeInterleaved2of5Code,
        };
    });
    return map[name.lowercaseString];
}

// Map --format string → (AVFileType, file extension).
static NSString *CAVFileType(NSString *fmt, NSString * _Nullable * _Nullable ext) {
    if ([fmt.lowercaseString isEqualToString:@"mov"]) {
        if (ext) *ext = @"mov";
        return AVFileTypeQuickTimeMovie;
    }
    if (ext) *ext = @"mp4";
    return AVFileTypeMPEG4;
}

// Pick a video capture device by index from the discovery session list.
static AVCaptureDevice * _Nullable CAVVideoDevice(NSInteger index) {
    NSMutableArray *types = [NSMutableArray arrayWithObject:AVCaptureDeviceTypeBuiltInWideAngleCamera];
    [types addObject:AVCaptureDeviceTypeExternalUnknown];
    if (@available(macOS 14.0, *)) [types addObject:AVCaptureDeviceTypeExternal];
    AVCaptureDeviceDiscoverySession *ds =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:types
                                                               mediaType:AVMediaTypeVideo
                                                                position:AVCaptureDevicePositionUnspecified];
    if (index < (NSInteger)ds.devices.count) return ds.devices[index];
    return [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
}

// Spin (sleep-based) until *flag, gStopCapture, or duration fires.
static void CSpinUntilFlagOrStop(volatile BOOL *flag, NSTimeInterval duration) {
    NSDate *deadline = duration > 0
        ? [NSDate dateWithTimeIntervalSinceNow:duration]
        : [NSDate distantFuture];
    while (!*flag && !gStopCapture && [[NSDate date] compare:deadline] == NSOrderedAscending) {
        [NSThread sleepForTimeInterval:0.05];
    }
}

// ── CaptureProcessor ──────────────────────────────────────────────────────────

@implementation CaptureProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation    = @"screenshot";
        _format       = @"mp4";
        _displayIndex = 0;
        _deviceIndex  = 0;
        _duration     = 0;
    }
    return self;
}

- (BOOL)runWithError:(NSError **)error {
    NSArray *validOps = @[@"screenshot", @"photo", @"audio", @"video", @"screen-record", @"barcode", @"list-devices"];
    if (![validOps containsObject:self.operation]) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:1
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Unknown operation '%@'. Valid: %@",
                 self.operation, [validOps componentsJoinedByString:@", "]]}];
        return NO;
    }
    if ([self.operation isEqualToString:@"screenshot"])   return [self runScreenshotWithError:error];
    if ([self.operation isEqualToString:@"photo"])        return [self runPhotoWithError:error];
    if ([self.operation isEqualToString:@"audio"])        return [self runAudioWithError:error];
    if ([self.operation isEqualToString:@"video"])
        return self.stream ? [self runVideoStreamWithError:error] : [self runVideoWithError:error];
    if ([self.operation isEqualToString:@"screen-record"])return [self runScreenRecordWithError:error];
    if ([self.operation isEqualToString:@"barcode"])      return [self runBarcodeWithError:error];
    if ([self.operation isEqualToString:@"list-devices"]) return [self runListDevicesWithError:error];
    return YES;
}

// ── Output path helpers ───────────────────────────────────────────────────────

- (NSURL *)resolveMediaURLWithName:(NSString *)autoName {
    if (self.mediaOutput.length) return [NSURL fileURLWithPath:self.mediaOutput];
    NSURL *dir = self.artifactsDir.length
        ? [NSURL fileURLWithPath:self.artifactsDir]
        : [NSURL fileURLWithPath:[[NSFileManager defaultManager] currentDirectoryPath]];
    return [dir URLByAppendingPathComponent:autoName];
}

- (BOOL)saveResult:(NSDictionary *)result mediaURL:(NSURL *)mediaURL error:(NSError **)error {
    NSArray *arts = mediaURL.path.length ? @[MVArtifactEntry(mediaURL.path, @"media")] : @[];
    NSDictionary *merged = MVResultByMergingArtifacts(result, arts);
    NSDictionary *env = MVMakeEnvelope(@"streamcapture", self.operation, mediaURL.path, merged);
    return MVEmitEnvelope(env, self.jsonOutput, error);
}

// ── AppKit event pump (required for windows to render in CLI tools) ───────────

static void CInitAppKit(void) {
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        [NSApplication sharedApplication];
        [NSApp setActivationPolicy:NSApplicationActivationPolicyRegular];
        [NSApp finishLaunching];
    });
}

// Pump the AppKit event queue for one pass, processing all pending events.
static void CPumpAppKit(void) {
    NSEvent *evt;
    while ((evt = [NSApp nextEventMatchingMask:NSEventMaskAny
                                     untilDate:[NSDate distantPast]
                                        inMode:NSDefaultRunLoopMode
                                       dequeue:YES])) {
        [NSApp sendEvent:evt];
    }
    [NSApp updateWindows];
}

// Pump AppKit until *flag, gStopCapture, or duration fires.
static void CSpinAppKitUntilFlagOrStop(volatile BOOL *flag, NSTimeInterval duration) {
    NSDate *deadline = duration > 0
        ? [NSDate dateWithTimeIntervalSinceNow:duration]
        : [NSDate distantFuture];
    while (!*flag && !gStopCapture && [[NSDate date] compare:deadline] == NSOrderedAscending) {
        CPumpAppKit();
        [NSThread sleepForTimeInterval:0.02];
    }
}
static void CSpinAppKitUntilFlag(volatile BOOL *flag) {
    CSpinAppKitUntilFlagOrStop(flag, 0);
}

// ── Preview window ────────────────────────────────────────────────────────────

- (NSWindow *)createPreviewWindowForSession:(AVCaptureSession *)session title:(NSString *)title {
    CInitAppKit();

    NSScreen *screen = [NSScreen mainScreen];
    CGFloat w = 640, h = 480;
    NSRect frame = NSMakeRect(
        NSMidX(screen.visibleFrame) - w / 2.0,
        NSMidY(screen.visibleFrame) - h / 2.0,
        w, h
    );
    NSWindow *win = [[NSWindow alloc]
        initWithContentRect:frame
                  styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable
                    backing:NSBackingStoreBuffered
                      defer:NO];
    win.title = title;
    win.releasedWhenClosed = NO;

    NSView *contentView = win.contentView;
    contentView.wantsLayer = YES;

    AVCaptureVideoPreviewLayer *layer = [AVCaptureVideoPreviewLayer layerWithSession:session];
    layer.frame = contentView.bounds;
    layer.autoresizingMask = kCALayerWidthSizable | kCALayerHeightSizable;
    layer.videoGravity = AVLayerVideoGravityResizeAspect;
    // AVCaptureVideoPreviewLayer is video-only — audio never routes to speakers
    [contentView.layer addSublayer:layer];

    [win orderFrontRegardless];
    [NSApp activateIgnoringOtherApps:YES];
    // Pump a few frames so the window actually appears before returning
    for (int i = 0; i < 5; i++) { CPumpAppKit(); [NSThread sleepForTimeInterval:0.02]; }
    return win;
}

// ── list-devices ──────────────────────────────────────────────────────────────

- (BOOL)runListDevicesWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    NSMutableArray *types = [NSMutableArray arrayWithObject:AVCaptureDeviceTypeBuiltInWideAngleCamera];
    [types addObject:AVCaptureDeviceTypeExternalUnknown];
    if (@available(macOS 14.0, *)) [types addObject:AVCaptureDeviceTypeExternal];

    NSMutableArray *cameras = [NSMutableArray array];
    AVCaptureDeviceDiscoverySession *vds =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:types
                                                               mediaType:AVMediaTypeVideo
                                                                position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *d in vds.devices) {
        [cameras addObject:@{@"uniqueID": d.uniqueID, @"localizedName": d.localizedName,
                              @"position": @(d.position), @"deviceType": d.deviceType,
                              @"mediaType": @"video", @"hasVideo": @([d hasMediaType:AVMediaTypeVideo])}];
    }

    NSMutableArray *mics = [NSMutableArray array];
    if (@available(macOS 14.0, *)) {
        AVCaptureDeviceDiscoverySession *ads =
            [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeMicrophone]
                                                                   mediaType:AVMediaTypeAudio
                                                                    position:AVCaptureDevicePositionUnspecified];
        for (AVCaptureDevice *d in ads.devices) {
            [mics addObject:@{@"uniqueID": d.uniqueID, @"localizedName": d.localizedName,
                               @"deviceType": d.deviceType, @"mediaType": @"audio"}];
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio]) {
            [mics addObject:@{@"uniqueID": d.uniqueID, @"localizedName": d.localizedName,
                               @"deviceType": d.deviceType ?: @"", @"mediaType": @"audio"}];
        }
#pragma clang diagnostic pop
    }

    NSMutableDictionary *result = [@{@"cameras": cameras, @"microphones": mics} mutableCopy];
    if (self.debug) result[@"processing_ms"] = @((NSInteger)(-[start timeIntervalSinceNow] * 1000.0));
    NSDictionary *env = MVMakeEnvelope(@"streamcapture", @"list-devices", nil, result);
    return MVEmitEnvelope(env, self.jsonOutput, error);
}

// ── screenshot ────────────────────────────────────────────────────────────────

- (BOOL)runScreenshotWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    NSString *autoName = [NSString stringWithFormat:@"shot_%ld.png", (long)[[NSDate date] timeIntervalSince1970]];
    NSURL *mediaURL = [self resolveMediaURLWithName:autoName];
    [[NSFileManager defaultManager] createDirectoryAtURL:mediaURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];

    CGDirectDisplayID displayID = CGMainDisplayID();
    if (self.displayIndex > 0) {
        uint32_t count = 0;
        CGGetActiveDisplayList(0, NULL, &count);
        if ((NSInteger)count <= self.displayIndex) {
            if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:71
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Display index %ld not found (%u active display(s))",
                     (long)self.displayIndex, count]}];
            return NO;
        }
        CGDirectDisplayID displays[32];
        CGGetActiveDisplayList(32, displays, &count);
        displayID = displays[self.displayIndex];
    }

    CGImageRef cgi = CGDisplayCreateImage(displayID);
    if (!cgi) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:70
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to capture display image"}];
        return NO;
    }
    NSBitmapImageRep *rep = [[NSBitmapImageRep alloc] initWithCGImage:cgi];
    CGImageRelease(cgi);
    NSData *png = [rep representationUsingType:NSBitmapImageFileTypePNG properties:@{}];
    if (![png writeToURL:mediaURL options:NSDataWritingAtomic error:error]) return NO;

    fprintf(stderr, "Saved %s\n", mediaURL.path.UTF8String);
    NSMutableDictionary *result = [@{@"path": mediaURL.path,
                                      @"width": @(rep.pixelsWide), @"height": @(rep.pixelsHigh)} mutableCopy];
    if (self.debug) result[@"processing_ms"] = @((NSInteger)(-[start timeIntervalSinceNow] * 1000.0));
    return [self saveResult:result mediaURL:mediaURL error:error];
}

// ── photo ─────────────────────────────────────────────────────────────────────

- (BOOL)runPhotoWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    // Request camera TCC permission — triggers the system dialog on first use
    dispatch_semaphore_t permSem = dispatch_semaphore_create(0);
    __block BOOL permGranted = NO;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        permGranted = granted;
        dispatch_semaphore_signal(permSem);
    }];
    dispatch_semaphore_wait(permSem, DISPATCH_TIME_FOREVER);
    if (!permGranted) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:80
            userInfo:@{NSLocalizedDescriptionKey:
                @"Camera access denied — grant permission in System Settings > Privacy & Security > Camera"}];
        return NO;
    }

    AVCaptureDevice *device = CAVVideoDevice(self.deviceIndex);
    if (!device) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:80
            userInfo:@{NSLocalizedDescriptionKey: @"No camera available"}];
        return NO;
    }
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:error];
    if (!input) return NO;

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPresetPhoto;
    [session addInput:input];

    dispatch_semaphore_t capSem = dispatch_semaphore_create(0);
    CaptureFrameDelegate *delegate = [[CaptureFrameDelegate alloc] initWithSemaphore:capSem];

    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoOutput.alwaysDiscardsLateVideoFrames = YES;
    dispatch_queue_t captureQ = dispatch_queue_create("mv.capture.photo", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:delegate queue:captureQ];
    [session addOutput:videoOutput];

    NSWindow *previewWindow = nil;
    if (self.preview) {
        previewWindow = [self createPreviewWindowForSession:session
            title:[NSString stringWithFormat:@"Preview — %@", device.localizedName]];
    }

    [session startRunning];

    if (self.preview) {
        // Warmup: pump AppKit so the window renders and camera stabilises
        NSDate *warmup = [NSDate dateWithTimeIntervalSinceNow:1.5];
        while ([[NSDate date] compare:warmup] == NSOrderedAscending) {
            CPumpAppKit();
            [NSThread sleepForTimeInterval:0.02];
        }
        fprintf(stderr, "Press ENTER to capture photo from '%s'...\n", device.localizedName.UTF8String);
        __block volatile BOOL enterPressed = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            char buf[256]; fgets(buf, sizeof(buf), stdin);
            enterPressed = YES;
        });
        CSpinAppKitUntilFlag(&enterPressed);
    } else {
        // Headless: block on sleep + fgets; run loop not needed
        [NSThread sleepForTimeInterval:1.5];
        fprintf(stderr, "Press ENTER to capture photo from '%s'...\n", device.localizedName.UTF8String);
        char lb[256]; fgets(lb, sizeof(lb), stdin);
    }

    delegate.shouldCapture = YES;
    dispatch_semaphore_wait(capSem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    [session stopRunning];
    [previewWindow close];

    if (!delegate.capturedImage) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:81
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to capture photo frame"}];
        return NO;
    }

    NSString *autoName = [NSString stringWithFormat:@"photo_%ld.jpg", (long)[[NSDate date] timeIntervalSince1970]];
    NSURL *mediaURL = [self resolveMediaURLWithName:autoName];
    [[NSFileManager defaultManager] createDirectoryAtURL:mediaURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];

    CIContext *ctx = [CIContext context];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSData *jpegData = [ctx JPEGRepresentationOfImage:delegate.capturedImage
                                           colorSpace:cs
                                              options:@{(id)kCGImageDestinationLossyCompressionQuality: @0.9}];
    CGColorSpaceRelease(cs);
    if (!jpegData || ![jpegData writeToURL:mediaURL options:NSDataWritingAtomic error:error]) {
        if (error && !*error) *error = [NSError errorWithDomain:CaptureErrorDomain code:82
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode JPEG"}];
        return NO;
    }

    fprintf(stderr, "Saved %s\n", mediaURL.path.UTF8String);
    NSMutableDictionary *result = [@{@"path": mediaURL.path, @"device": device.localizedName} mutableCopy];
    if (self.debug) result[@"processing_ms"] = @((NSInteger)(-[start timeIntervalSinceNow] * 1000.0));
    return [self saveResult:result mediaURL:mediaURL error:error];
}

// ── audio ─────────────────────────────────────────────────────────────────────

- (BOOL)runAudioWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    AVCaptureDevice *micDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    if (!micDevice) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:82
            userInfo:@{NSLocalizedDescriptionKey: @"No microphone available"}];
        return NO;
    }

    NSString *autoName = [NSString stringWithFormat:@"audio_%ld.m4a", (long)[[NSDate date] timeIntervalSince1970]];
    NSURL *mediaURL = [self resolveMediaURLWithName:autoName];
    [[NSFileManager defaultManager] createDirectoryAtURL:mediaURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *settings = @{
        AVFormatIDKey:         @(kAudioFormatMPEG4AAC),
        AVSampleRateKey:       @44100.0,
        AVNumberOfChannelsKey: @1,
        AVEncoderBitRateKey:   @128000,
    };
    AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:mediaURL settings:settings error:error];
    if (!recorder) return NO;

    gStopCapture = 0;
    signal(SIGINT, captureSignalHandler);

    if (self.duration > 0) {
        // Headless: start immediately, auto-stop after duration (ENTER or Ctrl+C stop early)
        [recorder record];
        fprintf(stderr, "Recording audio for %.0f seconds... (ENTER or Ctrl+C to stop early)\n", self.duration);
        __block volatile BOOL enter = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            char buf[256]; fgets(buf, sizeof(buf), stdin); enter = YES;
        });
        CSpinUntilFlagOrStop(&enter, self.duration);
    } else {
        // Interactive: ENTER to start, ENTER to stop
        fprintf(stderr, "Press ENTER to start recording...\n");
        __block volatile BOOL enter1 = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            char buf[256]; fgets(buf, sizeof(buf), stdin); enter1 = YES;
        });
        CSpinUntilFlagOrStop(&enter1, 0);
        if (!gStopCapture) {
            [recorder record];
            fprintf(stderr, "Recording... press ENTER to stop (or Ctrl+C)\n");
            __block volatile BOOL enter2 = NO;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                char buf[256]; fgets(buf, sizeof(buf), stdin); enter2 = YES;
            });
            CSpinUntilFlagOrStop(&enter2, 0);
        }
    }

    NSTimeInterval recDuration = recorder.currentTime;
    [recorder stop];
    signal(SIGINT, SIG_DFL);

    fprintf(stderr, "Saved %s\n", mediaURL.path.UTF8String);
    NSMutableDictionary *result = [@{@"path": mediaURL.path,
                                      @"duration_s": @(round(recDuration * 100.0) / 100.0)} mutableCopy];
    if (self.debug) result[@"processing_ms"] = @((NSInteger)(-[start timeIntervalSinceNow] * 1000.0));
    return [self saveResult:result mediaURL:mediaURL error:error];
}

// ── video ─────────────────────────────────────────────────────────────────────

- (BOOL)runVideoWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    AVCaptureDevice *device = CAVVideoDevice(self.deviceIndex);
    if (!device) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:83
            userInfo:@{NSLocalizedDescriptionKey: @"No camera available"}];
        return NO;
    }

    NSString *ext = nil;
    NSString *avType = CAVFileType(self.format, &ext);
    NSString *autoName = [NSString stringWithFormat:@"video_%ld.%@", (long)[[NSDate date] timeIntervalSince1970], ext];
    NSURL *mediaURL = [self resolveMediaURLWithName:autoName];
    [[NSFileManager defaultManager] createDirectoryAtURL:mediaURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:error];
    if (!input) return NO;
    [session addInput:input];

    if (!self.noAudio) {
        AVCaptureDevice *micDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
        if (micDevice) {
            AVCaptureDeviceInput *audioInput = [AVCaptureDeviceInput deviceInputWithDevice:micDevice error:nil];
            if (audioInput && [session canAddInput:audioInput]) [session addInput:audioInput];
        }
    }

    AVCaptureMovieFileOutput *movieOutput = [[AVCaptureMovieFileOutput alloc] init];
    [session addOutput:movieOutput];

    CaptureMovieDelegate *delegate = [[CaptureMovieDelegate alloc] init];
    NSURL *tmpURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                     URLByAppendingPathComponent:mediaURL.lastPathComponent];
    [[NSFileManager defaultManager] removeItemAtURL:tmpURL error:nil];

    gStopCapture = 0;
    signal(SIGINT, captureSignalHandler);

    NSWindow *previewWindow = nil;
    if (self.preview) {
        previewWindow = [self createPreviewWindowForSession:session
            title:[NSString stringWithFormat:@"Preview — %@", device.localizedName]];
        [session startRunning];

        fprintf(stderr, "Press ENTER to start recording from '%s'...\n", device.localizedName.UTF8String);
        __block volatile BOOL enter1 = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            char buf[256]; fgets(buf, sizeof(buf), stdin);
            enter1 = YES;
        });
        CSpinAppKitUntilFlag(&enter1);

        if (!gStopCapture) {
            [movieOutput startRecordingToOutputFileURL:tmpURL recordingDelegate:delegate];
            fprintf(stderr, "Recording... press ENTER to stop (or Ctrl+C)\n");
            __block volatile BOOL enter2 = NO;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                char buf[256]; fgets(buf, sizeof(buf), stdin);
                enter2 = YES;
            });
            CSpinAppKitUntilFlagOrStop(&enter2, self.duration);
            [movieOutput stopRecording];
        }
    } else {
        [session startRunning];
        if (self.duration > 0) {
            // Headless: start immediately, auto-stop after duration
            [movieOutput startRecordingToOutputFileURL:tmpURL recordingDelegate:delegate];
            fprintf(stderr, "Recording video for %.0f seconds from '%s'... (ENTER or Ctrl+C to stop early)\n",
                    self.duration, device.localizedName.UTF8String);
            __block volatile BOOL enter = NO;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                char buf[256]; fgets(buf, sizeof(buf), stdin); enter = YES;
            });
            CSpinUntilFlagOrStop(&enter, self.duration);
        } else {
            // Interactive: ENTER to start, ENTER to stop
            fprintf(stderr, "Press ENTER to start recording from '%s'...\n", device.localizedName.UTF8String);
            __block volatile BOOL enter1 = NO;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                char buf[256]; fgets(buf, sizeof(buf), stdin); enter1 = YES;
            });
            CSpinUntilFlagOrStop(&enter1, 0);
            if (!gStopCapture) {
                [movieOutput startRecordingToOutputFileURL:tmpURL recordingDelegate:delegate];
                fprintf(stderr, "Recording... press ENTER to stop (or Ctrl+C)\n");
                __block volatile BOOL enter2 = NO;
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    char buf[256]; fgets(buf, sizeof(buf), stdin); enter2 = YES;
                });
                CSpinUntilFlagOrStop(&enter2, 0);
            }
        }
        [movieOutput stopRecording];
    }
    signal(SIGINT, SIG_DFL);

    // Wait for file to be finalized
    NSDate *finDeadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while (!delegate.finished && [[NSDate date] compare:finDeadline] == NSOrderedAscending) {
        [NSThread sleepForTimeInterval:0.05];
    }
    [session stopRunning];
    [previewWindow close];

    if (delegate.recordingError) {
        if (error) *error = delegate.recordingError;
        return NO;
    }

    [[NSFileManager defaultManager] moveItemAtURL:tmpURL toURL:mediaURL error:nil];
    fprintf(stderr, "Saved %s\n", mediaURL.path.UTF8String);

    NSTimeInterval recDuration = movieOutput.recordedDuration.value > 0
        ? CMTimeGetSeconds(movieOutput.recordedDuration) : 0;
    NSMutableDictionary *result = [@{@"path": mediaURL.path,
                                      @"device": device.localizedName,
                                      @"format": avType,
                                      @"duration_s": @(round(recDuration * 100.0) / 100.0)} mutableCopy];
    if (self.debug) result[@"processing_ms"] = @((NSInteger)(-[start timeIntervalSinceNow] * 1000.0));
    return [self saveResult:result mediaURL:mediaURL error:error];
}

// ── screen-record ─────────────────────────────────────────────────────────────

- (BOOL)runScreenRecordWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    CGDirectDisplayID displayID = CGMainDisplayID();
    if (self.displayIndex > 0) {
        uint32_t count = 0;
        CGGetActiveDisplayList(0, NULL, &count);
        if ((NSInteger)count <= self.displayIndex) {
            if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:71
                userInfo:@{NSLocalizedDescriptionKey:
                    [NSString stringWithFormat:@"Display index %ld not found (%u active display(s))",
                     (long)self.displayIndex, count]}];
            return NO;
        }
        CGDirectDisplayID displays[32];
        CGGetActiveDisplayList(32, displays, &count);
        displayID = displays[self.displayIndex];
    }

    NSString *ext = nil;
    NSString *avType = CAVFileType(self.format, &ext);
    NSString *autoName = [NSString stringWithFormat:@"screen_%ld.%@", (long)[[NSDate date] timeIntervalSince1970], ext];
    NSURL *mediaURL = [self resolveMediaURLWithName:autoName];
    [[NSFileManager defaultManager] createDirectoryAtURL:mediaURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    AVCaptureScreenInput *screenInput = [[AVCaptureScreenInput alloc] initWithDisplayID:displayID];
    if (![session canAddInput:screenInput]) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:84
            userInfo:@{NSLocalizedDescriptionKey: @"Cannot add screen input — check Screen Recording permission in System Settings"}];
        return NO;
    }
    [session addInput:screenInput];

    AVCaptureMovieFileOutput *movieOutput = [[AVCaptureMovieFileOutput alloc] init];
    [session addOutput:movieOutput];

    CaptureMovieDelegate *delegate = [[CaptureMovieDelegate alloc] init];
    NSURL *tmpURL = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                     URLByAppendingPathComponent:mediaURL.lastPathComponent];
    [[NSFileManager defaultManager] removeItemAtURL:tmpURL error:nil];

    gStopCapture = 0;
    signal(SIGINT, captureSignalHandler);

    NSWindow *previewWindow = nil;
    if (self.preview) {
        previewWindow = [self createPreviewWindowForSession:session
            title:[NSString stringWithFormat:@"Preview — Display %ld", (long)self.displayIndex]];
        [session startRunning];

        fprintf(stderr, "Press ENTER to start recording display %ld...\n", (long)self.displayIndex);
        __block volatile BOOL enter1 = NO;
        dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            char buf[256]; fgets(buf, sizeof(buf), stdin);
            enter1 = YES;
        });
        CSpinAppKitUntilFlag(&enter1);

        if (!gStopCapture) {
            [movieOutput startRecordingToOutputFileURL:tmpURL recordingDelegate:delegate];
            fprintf(stderr, "Recording... press ENTER to stop (or Ctrl+C)\n");
            __block volatile BOOL enter2 = NO;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                char buf[256]; fgets(buf, sizeof(buf), stdin);
                enter2 = YES;
            });
            CSpinAppKitUntilFlag(&enter2);
            [movieOutput stopRecording];
        }
    } else {
        [session startRunning];
        if (self.duration > 0) {
            // Headless: start immediately, auto-stop after duration
            [movieOutput startRecordingToOutputFileURL:tmpURL recordingDelegate:delegate];
            fprintf(stderr, "Recording screen for %.0f seconds... (ENTER or Ctrl+C to stop early)\n", self.duration);
            __block volatile BOOL enter = NO;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                char buf[256]; fgets(buf, sizeof(buf), stdin); enter = YES;
            });
            CSpinUntilFlagOrStop(&enter, self.duration);
        } else {
            // Interactive: ENTER to start, ENTER to stop
            fprintf(stderr, "Press ENTER to start recording display %ld...\n", (long)self.displayIndex);
            __block volatile BOOL enter1 = NO;
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                char buf[256]; fgets(buf, sizeof(buf), stdin); enter1 = YES;
            });
            CSpinUntilFlagOrStop(&enter1, 0);
            if (!gStopCapture) {
                [movieOutput startRecordingToOutputFileURL:tmpURL recordingDelegate:delegate];
                fprintf(stderr, "Recording... press ENTER to stop (or Ctrl+C)\n");
                __block volatile BOOL enter2 = NO;
                dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
                    char buf[256]; fgets(buf, sizeof(buf), stdin); enter2 = YES;
                });
                CSpinUntilFlagOrStop(&enter2, 0);
            }
        }
        [movieOutput stopRecording];
    }
    signal(SIGINT, SIG_DFL);

    NSDate *finDeadline = [NSDate dateWithTimeIntervalSinceNow:10.0];
    while (!delegate.finished && [[NSDate date] compare:finDeadline] == NSOrderedAscending) {
        [NSThread sleepForTimeInterval:0.05];
    }
    [session stopRunning];
    [previewWindow close];

    if (delegate.recordingError) {
        if (error) *error = delegate.recordingError;
        return NO;
    }

    [[NSFileManager defaultManager] moveItemAtURL:tmpURL toURL:mediaURL error:nil];
    fprintf(stderr, "Saved %s\n", mediaURL.path.UTF8String);

    NSTimeInterval recDuration = movieOutput.recordedDuration.value > 0
        ? CMTimeGetSeconds(movieOutput.recordedDuration) : 0;
    NSMutableDictionary *result = [@{@"path": mediaURL.path,
                                      @"display_index": @(self.displayIndex),
                                      @"format": avType,
                                      @"duration_s": @(round(recDuration * 100.0) / 100.0)} mutableCopy];
    if (self.debug) result[@"processing_ms"] = @((NSInteger)(-[start timeIntervalSinceNow] * 1000.0));
    return [self saveResult:result mediaURL:mediaURL error:error];
}

// ── video --stream ────────────────────────────────────────────────────────────

- (BOOL)runVideoStreamWithError:(NSError **)error {
    // Request camera TCC permission
    dispatch_semaphore_t permSem = dispatch_semaphore_create(0);
    __block BOOL permGranted = NO;
    [AVCaptureDevice requestAccessForMediaType:AVMediaTypeVideo completionHandler:^(BOOL granted) {
        permGranted = granted;
        dispatch_semaphore_signal(permSem);
    }];
    dispatch_semaphore_wait(permSem, DISPATCH_TIME_FOREVER);
    if (!permGranted) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:80
            userInfo:@{NSLocalizedDescriptionKey:
                @"Camera access denied — grant permission in System Settings > Privacy & Security > Camera"}];
        return NO;
    }

    AVCaptureDevice *device = CAVVideoDevice(self.deviceIndex);
    if (!device) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:80
            userInfo:@{NSLocalizedDescriptionKey: @"No camera available"}];
        return NO;
    }
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:error];
    if (!input) return NO;

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPresetMedium;
    [session addInput:input];

    MVMjpegWriter *writer = [[MVMjpegWriter alloc] initWithFileDescriptor:STDOUT_FILENO];
    CaptureStreamDelegate *streamDelegate = [[CaptureStreamDelegate alloc] init];
    streamDelegate.writer    = writer;
    streamDelegate.ciContext = [CIContext context];

    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoOutput.alwaysDiscardsLateVideoFrames = YES;
    dispatch_queue_t captureQ = dispatch_queue_create("mv.capture.videostream", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:streamDelegate queue:captureQ];
    [session addOutput:videoOutput];

    gStopCapture = 0;
    signal(SIGINT, captureSignalHandler);

    [session startRunning];
    fprintf(stderr, "Streaming from '%s'... (Ctrl+C to stop)\n", device.localizedName.UTF8String);

    while (!gStopCapture) {
        [NSThread sleepForTimeInterval:0.05];
    }

    [session stopRunning];
    signal(SIGINT, SIG_DFL);
    return YES;
}

// ── barcode ───────────────────────────────────────────────────────────────────

- (BOOL)runBarcodeWithError:(NSError **)error {
    AVCaptureDevice *device = CAVVideoDevice(self.deviceIndex);
    if (!device) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:85
            userInfo:@{NSLocalizedDescriptionKey: @"No camera available for barcode scanning"}];
        return NO;
    }

    if (@available(macOS 13.0, *)) {} else {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:86
            userInfo:@{NSLocalizedDescriptionKey: @"barcode scanning requires macOS 13.0 or later"}];
        return NO;
    }

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:error];
    if (!input) return NO;
    [session addInput:input];

#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
    AVCaptureMetadataOutput *metaOutput = [[AVCaptureMetadataOutput alloc] init];
    [session addOutput:metaOutput];

    CaptureBarcodeDelegate *delegate = [[CaptureBarcodeDelegate alloc] init];
    [metaOutput setMetadataObjectsDelegate:delegate queue:dispatch_get_main_queue()];

    // Resolve requested types; default to all supported
    NSArray<NSString *> *allSupported = metaOutput.availableMetadataObjectTypes;
    NSArray<NSString *> *activeTypes;
    if (self.types.length) {
        NSMutableArray *resolved = [NSMutableArray array];
        for (NSString *name in [self.types componentsSeparatedByString:@","]) {
            NSString *avType = CAVBarcodeType([name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet]);
            if (avType && [allSupported containsObject:avType]) {
                [resolved addObject:avType];
            } else {
                fprintf(stderr, "streamcapture: unknown or unsupported barcode type '%s'\n", name.UTF8String);
            }
        }
        activeTypes = [resolved copy];
    } else {
        activeTypes = allSupported;
    }
    [metaOutput setMetadataObjectTypes:activeTypes];
    [session startRunning];

    gStopCapture = 0;
    signal(SIGINT, captureSignalHandler);
    fprintf(stderr, "Scanning for barcodes from '%s'... (press ENTER or Ctrl+C to stop)\n", device.localizedName.UTF8String);

    __block volatile BOOL enterPressed = NO;
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
        char buf[256]; fgets(buf, sizeof(buf), stdin); enterPressed = YES;
    });
    CSpinUntilFlagOrStop(&enterPressed, self.duration);

    [session stopRunning];
    signal(SIGINT, SIG_DFL);
#pragma clang diagnostic pop
    return YES;
}

@end
