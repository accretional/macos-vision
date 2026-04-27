#import "main.h"
#import "common/MVJsonEmit.h"
#import "common/MVMjpegStream.h"
#import "common/MVAudioStream.h"
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <Cocoa/Cocoa.h>
#import <Vision/Vision.h>
#import <signal.h>
#include <unistd.h>

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
@property (nonatomic) dispatch_semaphore_t doneSem;
@end

@implementation CaptureMovieDelegate
- (instancetype)init {
    if (self = [super init]) {
        _doneSem = dispatch_semaphore_create(0);
    }
    return self;
}
- (void)captureOutput:(AVCaptureFileOutput *)output
    didFinishRecordingToOutputFileAtURL:(NSURL *)url
                        fromConnections:(NSArray<AVCaptureConnection *> *)connections
                                  error:(NSError *)error {
    self.recordingError = error;
    self.finished = YES;
    dispatch_semaphore_signal(self.doneSem);
}
@end

// ── Stream video delegate ─────────────────────────────────────────────────────

@interface CaptureStreamDelegate : NSObject <AVCaptureVideoDataOutputSampleBufferDelegate>
@property (nonatomic, strong) MVMjpegWriter *writer;
@property (nonatomic, strong) CIContext *ciContext;
/// JPEG compression quality in [0.0, 1.0] (default 0.85).
@property (nonatomic, assign) double jpegQuality;
/// Minimum interval between frames in seconds; 0 = no throttle.
@property (nonatomic, assign) NSTimeInterval frameInterval;
@end

@implementation CaptureStreamDelegate {
    NSDate *_lastFrameTime;
}

- (instancetype)init {
    if ((self = [super init])) {
        _jpegQuality   = 0.85;
        _frameInterval = 0.0;
    }
    return self;
}

- (void)captureOutput:(AVCaptureOutput *)output
    didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer
         fromConnection:(AVCaptureConnection *)connection {
    // FPS throttle: drop frames that arrive sooner than frameInterval
    if (_frameInterval > 0.0 && _lastFrameTime) {
        NSTimeInterval elapsed = -[_lastFrameTime timeIntervalSinceNow];
        if (elapsed < _frameInterval) return;
    }

    CVImageBufferRef pixelBuffer = CMSampleBufferGetImageBuffer(sampleBuffer);
    if (!pixelBuffer) return;
    CIImage *ciImage = [[CIImage alloc] initWithCVImageBuffer:pixelBuffer];
    // Correct built-in camera orientation (frames arrive rotated 180°)
    // ciImage = [ciImage imageByApplyingCGOrientation:kCGImagePropertyOrientationDown];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    NSData *jpeg = [self.ciContext
        JPEGRepresentationOfImage:ciImage
                      colorSpace:cs
                         options:@{(id)kCGImageDestinationLossyCompressionQuality: @(_jpegQuality)}];
    CGColorSpaceRelease(cs);
    if (jpeg) {
        [self.writer writeFrame:jpeg extraHeaders:nil];
        _lastFrameTime = [NSDate date];
    }
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
        _operation       = @"screenshot";
        _format          = @"mp4";
        _displayIndex    = 0;
        _deviceIndex     = 0;
        _duration        = 0;
        _fps             = 30;
        _jpegQuality     = 0.85;
        _audioSampleRate = 16000;
        _audioChannels   = 1;
        _audioBitDepth   = 16;
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
    if ([self.operation isEqualToString:@"screenshot"])
        return self.stream ? [self runScreenshotStreamWithError:error] : [self runScreenshotWithError:error];
    if ([self.operation isEqualToString:@"photo"])
        return self.stream ? [self runPhotoStreamWithError:error] : [self runPhotoWithError:error];
    if ([self.operation isEqualToString:@"audio"])
        return self.stream ? [self runAudioStreamWithError:error] : [self runAudioWithError:error];
    if ([self.operation isEqualToString:@"video"])
        return self.stream ? [self runVideoStreamWithError:error] : [self runVideoWithError:error];
    if ([self.operation isEqualToString:@"screen-record"])
        return self.stream ? [self runScreenRecordStreamWithError:error] : [self runScreenRecordWithError:error];
    if ([self.operation isEqualToString:@"barcode"])
        return self.stream ? [self runBarcodeStreamWithError:error] : [self runBarcodeWithError:error];
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
    } else {
        // Headless: wait for camera to stabilise
        [NSThread sleepForTimeInterval:1.5];
    }
    fprintf(stderr, "Capturing photo from '%s'...\n", device.localizedName.UTF8String);

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

    // Validate the output extension — macOS has no mp3 encoder
    NSString *ext = mediaURL.pathExtension.lowercaseString;
    if ([ext isEqualToString:@"mp3"]) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:1
            userInfo:@{NSLocalizedDescriptionKey:
                @"mp3 encoding is not supported on macOS — use .m4a (AAC) or .wav instead"}];
        return NO;
    }

    [[NSFileManager defaultManager] createDirectoryAtURL:mediaURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];

    BOOL isWav = [ext isEqualToString:@"wav"] || [ext isEqualToString:@"aiff"] || [ext isEqualToString:@"aif"];
    NSDictionary *settings = isWav
        ? @{
            AVFormatIDKey:         @(kAudioFormatLinearPCM),
            AVSampleRateKey:       @44100.0,
            AVNumberOfChannelsKey: @1,
            AVLinearPCMBitDepthKey: @16,
            AVLinearPCMIsFloatKey:  @NO,
          }
        : @{
            AVFormatIDKey:         @(kAudioFormatMPEG4AAC),
            AVSampleRateKey:       @44100.0,
            AVNumberOfChannelsKey: @1,
            AVEncoderBitRateKey:   @128000,
          };
    AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:mediaURL settings:settings error:error];
    if (!recorder) return NO;

    gStopCapture = 0;
    signal(SIGINT, captureSignalHandler);

    [recorder record];
    if (self.duration > 0) {
        fprintf(stderr, "Recording audio for %.0f seconds... (Ctrl+C to stop early)\n", self.duration);
        volatile BOOL never = NO;
        CSpinUntilFlagOrStop(&never, self.duration);
    } else {
        fprintf(stderr, "Recording audio... (Ctrl+C to stop)\n");
        while (!gStopCapture) { [NSThread sleepForTimeInterval:0.05]; }
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
        [movieOutput startRecordingToOutputFileURL:tmpURL recordingDelegate:delegate];
        if (self.duration > 0) {
            fprintf(stderr, "Recording video for %.0f seconds from '%s'... (Ctrl+C to stop early)\n",
                    self.duration, device.localizedName.UTF8String);
        } else {
            fprintf(stderr, "Recording from '%s'... (Ctrl+C to stop)\n", device.localizedName.UTF8String);
        }
        volatile BOOL never = NO;
        CSpinAppKitUntilFlagOrStop(&never, self.duration);
        [movieOutput stopRecording];
    } else {
        [session startRunning];
        [movieOutput startRecordingToOutputFileURL:tmpURL recordingDelegate:delegate];
        if (self.duration > 0) {
            fprintf(stderr, "Recording video for %.0f seconds from '%s'... (Ctrl+C to stop early)\n",
                    self.duration, device.localizedName.UTF8String);
            volatile BOOL never = NO;
            CSpinUntilFlagOrStop(&never, self.duration);
        } else {
            fprintf(stderr, "Recording from '%s'... (Ctrl+C to stop)\n", device.localizedName.UTF8String);
            while (!gStopCapture) { [NSThread sleepForTimeInterval:0.05]; }
        }
        [movieOutput stopRecording];
    }

    // Wait for AVCaptureMovieFileOutput to finalize the file; keep SIGINT
    // handling active so a second Ctrl+C is caught rather than killing the
    // process while the file is being written.
    dispatch_semaphore_wait(delegate.doneSem,
        dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    signal(SIGINT, SIG_DFL);

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
        [movieOutput startRecordingToOutputFileURL:tmpURL recordingDelegate:delegate];
        if (self.duration > 0) {
            fprintf(stderr, "Recording display %ld for %.0f seconds... (Ctrl+C to stop early)\n",
                    (long)self.displayIndex, self.duration);
        } else {
            fprintf(stderr, "Recording display %ld... (Ctrl+C to stop)\n", (long)self.displayIndex);
        }
        volatile BOOL never = NO;
        CSpinAppKitUntilFlagOrStop(&never, self.duration);
        [movieOutput stopRecording];
    } else {
        [session startRunning];
        [movieOutput startRecordingToOutputFileURL:tmpURL recordingDelegate:delegate];
        if (self.duration > 0) {
            fprintf(stderr, "Recording display %ld for %.0f seconds... (Ctrl+C to stop early)\n",
                    (long)self.displayIndex, self.duration);
            volatile BOOL never = NO;
            CSpinUntilFlagOrStop(&never, self.duration);
        } else {
            fprintf(stderr, "Recording display %ld... (Ctrl+C to stop)\n", (long)self.displayIndex);
            while (!gStopCapture) { [NSThread sleepForTimeInterval:0.05]; }
        }
        [movieOutput stopRecording];
    }

    dispatch_semaphore_wait(delegate.doneSem,
        dispatch_time(DISPATCH_TIME_NOW, 10 * NSEC_PER_SEC));
    signal(SIGINT, SIG_DFL);

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
    streamDelegate.writer        = writer;
    streamDelegate.ciContext     = [CIContext context];
    streamDelegate.jpegQuality   = self.jpegQuality > 0.0 ? self.jpegQuality : 0.85;
    streamDelegate.frameInterval = self.fps > 0 ? (1.0 / (double)self.fps) : 0.0;

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

// ── screenshot --stream ───────────────────────────────────────────────────────

- (BOOL)runScreenshotStreamWithError:(NSError **)error {
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

    CIContext *ctx = [CIContext context];
    CIImage *ciImage = [[CIImage alloc] initWithCGImage:cgi];
    CGImageRelease(cgi);
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    double quality = self.jpegQuality > 0.0 ? self.jpegQuality : 0.85;
    NSData *jpeg = [ctx JPEGRepresentationOfImage:ciImage
                                       colorSpace:cs
                                          options:@{(id)kCGImageDestinationLossyCompressionQuality: @(quality)}];
    CGColorSpaceRelease(cs);
    if (!jpeg) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:70
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode screenshot as JPEG"}];
        return NO;
    }

    MVMjpegWriter *writer = [[MVMjpegWriter alloc] initWithFileDescriptor:STDOUT_FILENO];
    [writer writeFrame:jpeg extraHeaders:nil];
    return YES;
}

// ── photo --stream ────────────────────────────────────────────────────────────

- (BOOL)runPhotoStreamWithError:(NSError **)error {
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
    session.sessionPreset = AVCaptureSessionPresetPhoto;
    [session addInput:input];

    dispatch_semaphore_t capSem = dispatch_semaphore_create(0);
    CaptureFrameDelegate *delegate = [[CaptureFrameDelegate alloc] initWithSemaphore:capSem];
    delegate.shouldCapture = NO;

    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoOutput.alwaysDiscardsLateVideoFrames = YES;
    dispatch_queue_t captureQ = dispatch_queue_create("mv.capture.photostream", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:delegate queue:captureQ];
    [session addOutput:videoOutput];

    [session startRunning];
    // Warm up camera: wait for it to stabilise before capturing
    [NSThread sleepForTimeInterval:1.5];
    delegate.shouldCapture = YES;
    dispatch_semaphore_wait(capSem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    [session stopRunning];

    if (!delegate.capturedImage) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:81
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to capture photo frame"}];
        return NO;
    }

    CIContext *ctx = [CIContext context];
    CGColorSpaceRef cs = CGColorSpaceCreateDeviceRGB();
    double quality = self.jpegQuality > 0.0 ? self.jpegQuality : 0.85;
    NSData *jpeg = [ctx JPEGRepresentationOfImage:delegate.capturedImage
                                       colorSpace:cs
                                          options:@{(id)kCGImageDestinationLossyCompressionQuality: @(quality)}];
    CGColorSpaceRelease(cs);
    if (!jpeg) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:82
            userInfo:@{NSLocalizedDescriptionKey: @"Failed to encode photo as JPEG"}];
        return NO;
    }

    MVMjpegWriter *writer = [[MVMjpegWriter alloc] initWithFileDescriptor:STDOUT_FILENO];
    [writer writeFrame:jpeg extraHeaders:nil];
    return YES;
}

// ── audio --stream ────────────────────────────────────────────────────────────

- (BOOL)runAudioStreamWithError:(NSError **)error {
    // Build MVAU format from processor properties
    MVAudioFormat fmt;
    fmt.sampleRate = self.audioSampleRate > 0 ? self.audioSampleRate : 16000;
    fmt.channels   = self.audioChannels   > 0 ? self.audioChannels   : 1;
    fmt.bitDepth   = self.audioBitDepth   > 0 ? self.audioBitDepth   : 16;

    MVAudioWriter *audioWriter = [[MVAudioWriter alloc] initWithFileDescriptor:STDOUT_FILENO format:fmt];

    // Set up AVAudioEngine to capture from the default microphone
    AVAudioEngine *engine = [[AVAudioEngine alloc] init];
    AVAudioInputNode *inputNode = engine.inputNode;
    AVAudioFormat *inputFormat = [inputNode inputFormatForBus:0];

    // Request the hardware's native format; resample to target format via AVAudioConverter
    AVAudioFormat *targetFmt = [[AVAudioFormat alloc]
        initWithCommonFormat:AVAudioPCMFormatInt16
                  sampleRate:(double)fmt.sampleRate
                    channels:(AVAudioChannelCount)fmt.channels
                 interleaved:YES];

    AVAudioConverter *converter = [[AVAudioConverter alloc] initFromFormat:inputFormat toFormat:targetFmt];

    [audioWriter writeHeader];

    NSError *engineErr = nil;
    [inputNode installTapOnBus:0 bufferSize:4096 format:inputFormat block:^(AVAudioPCMBuffer *buf, AVAudioTime *when) {
        // Convert to target format
        AVAudioFrameCount capacity = (AVAudioFrameCount)((double)buf.frameLength * fmt.sampleRate / inputFormat.sampleRate + 1);
        AVAudioPCMBuffer *outBuf = [[AVAudioPCMBuffer alloc] initWithPCMFormat:targetFmt frameCapacity:capacity];
        if (!outBuf) return;

        __block BOOL inputConsumed = NO;
        AVAudioConverterOutputStatus status = [converter convertToBuffer:outBuf error:nil
            withInputFromBlock:^AVAudioBuffer *(AVAudioPacketCount inNumPackets, AVAudioConverterInputStatus *outStatus) {
                if (inputConsumed) {
                    *outStatus = AVAudioConverterInputStatus_NoDataNow;
                    return nil;
                }
                inputConsumed = YES;
                *outStatus = AVAudioConverterInputStatus_HaveData;
                return buf;
            }];

        if ((status == AVAudioConverterOutputStatus_HaveData || status == AVAudioConverterOutputStatus_InputRanDry)
             && outBuf.frameLength > 0) {
            NSUInteger bytes = outBuf.frameLength * fmt.channels * (fmt.bitDepth / 8);
            NSData *pcmData = [NSData dataWithBytes:outBuf.int16ChannelData[0] length:bytes];
            [audioWriter writeSamples:pcmData];
        }
    }];

    if (![engine startAndReturnError:&engineErr]) {
        if (error) *error = engineErr;
        return NO;
    }

    gStopCapture = 0;
    signal(SIGINT, captureSignalHandler);
    fprintf(stderr, "Streaming audio (MVAU) to stdout... (Ctrl+C to stop)\n");

    if (self.duration > 0) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:self.duration];
        while (!gStopCapture && [[NSDate date] compare:deadline] == NSOrderedAscending) {
            [NSThread sleepForTimeInterval:0.05];
        }
    } else {
        while (!gStopCapture) {
            [NSThread sleepForTimeInterval:0.05];
        }
    }

    [engine stop];
    [inputNode removeTapOnBus:0];
    signal(SIGINT, SIG_DFL);
    return YES;
}

// ── screen-record --stream ────────────────────────────────────────────────────

- (BOOL)runScreenRecordStreamWithError:(NSError **)error {
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

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    AVCaptureScreenInput *screenInput = [[AVCaptureScreenInput alloc] initWithDisplayID:displayID];
    if (self.fps > 0) screenInput.minFrameDuration = CMTimeMake(1, (int32_t)self.fps);
    if (![session canAddInput:screenInput]) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:84
            userInfo:@{NSLocalizedDescriptionKey: @"Cannot add screen input — check Screen Recording permission in System Settings"}];
        return NO;
    }
    [session addInput:screenInput];

    MVMjpegWriter *writer = [[MVMjpegWriter alloc] initWithFileDescriptor:STDOUT_FILENO];
    CaptureStreamDelegate *streamDelegate = [[CaptureStreamDelegate alloc] init];
    streamDelegate.writer        = writer;
    streamDelegate.ciContext     = [CIContext context];
    streamDelegate.jpegQuality   = self.jpegQuality > 0.0 ? self.jpegQuality : 0.85;
    // fps throttle already handled by screenInput.minFrameDuration; no extra throttle needed
    streamDelegate.frameInterval = 0.0;

    AVCaptureVideoDataOutput *videoOutput = [[AVCaptureVideoDataOutput alloc] init];
    videoOutput.alwaysDiscardsLateVideoFrames = YES;
    dispatch_queue_t captureQ = dispatch_queue_create("mv.capture.screenstream", DISPATCH_QUEUE_SERIAL);
    [videoOutput setSampleBufferDelegate:streamDelegate queue:captureQ];
    if (![session canAddOutput:videoOutput]) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:84
            userInfo:@{NSLocalizedDescriptionKey: @"Cannot add video output to screen record session"}];
        return NO;
    }
    [session addOutput:videoOutput];

    gStopCapture = 0;
    signal(SIGINT, captureSignalHandler);

    [session startRunning];
    fprintf(stderr, "Streaming screen %ld as MJPEG to stdout... (Ctrl+C to stop)\n", (long)self.displayIndex);

    if (self.duration > 0) {
        NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:self.duration];
        while (!gStopCapture && [[NSDate date] compare:deadline] == NSOrderedAscending) {
            [NSThread sleepForTimeInterval:0.05];
        }
    } else {
        while (!gStopCapture) {
            [NSThread sleepForTimeInterval:0.05];
        }
    }

    [session stopRunning];
    signal(SIGINT, SIG_DFL);
    return YES;
}

// ── barcode stream filter (MJPEG in → MJPEG out + X-MV-streamcapture-barcode) ─

- (BOOL)runBarcodeStreamWithError:(NSError **)error {
    // Build Vision barcode symbol type filter from --types
    NSArray<NSString *> *symbologyFilter = nil;
    if (self.types.length) {
        NSMutableArray *syms = [NSMutableArray array];
        // Map VN symbol type names from user-friendly names via the AV map,
        // then convert to VNBarcodeSymbology equivalents.
        NSDictionary<NSString *, NSString *> *vnMap = @{
            @"qr":         VNBarcodeSymbologyQR,
            @"ean13":      VNBarcodeSymbologyEAN13,
            @"ean8":       VNBarcodeSymbologyEAN8,
            @"upce":       VNBarcodeSymbologyUPCE,
            @"code128":    VNBarcodeSymbologyCode128,
            @"code39":     VNBarcodeSymbologyCode39,
            @"code93":     VNBarcodeSymbologyCode93,
            @"pdf417":     VNBarcodeSymbologyPDF417,
            @"aztec":      VNBarcodeSymbologyAztec,
            @"datamatrix": VNBarcodeSymbologyDataMatrix,
            @"itf14":      VNBarcodeSymbologyITF14,
            @"i2of5":      VNBarcodeSymbologyI2of5,
        };
        for (NSString *name in [self.types componentsSeparatedByString:@","]) {
            NSString *t = [name stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet].lowercaseString;
            NSString *sym = vnMap[t];
            if (sym) [syms addObject:sym];
            else fprintf(stderr, "streamcapture: unknown barcode type '%s'\n", t.UTF8String);
        }
        symbologyFilter = [syms copy];
    }

    MVMjpegReader *reader = [[MVMjpegReader alloc] initWithFileDescriptor:STDIN_FILENO];
    MVMjpegWriter *writer = [[MVMjpegWriter alloc] initWithFileDescriptor:STDOUT_FILENO];

    [reader readFramesWithHandler:^(NSData *jpeg, NSDictionary<NSString *, NSString *> *inHeaders) {
        NSMutableDictionary<NSString *, NSString *> *outHeaders = [NSMutableDictionary dictionaryWithDictionary:inHeaders];
        [outHeaders removeObjectForKey:@"Content-Type"];
        [outHeaders removeObjectForKey:@"Content-Length"];

        // Decode JPEG → CGImage for Vision
        CGImageSourceRef src = CGImageSourceCreateWithData((__bridge CFDataRef)jpeg, nil);
        CGImageRef cg = src ? CGImageSourceCreateImageAtIndex(src, 0, nil) : NULL;
        if (src) CFRelease(src);

        if (cg) {
            VNDetectBarcodesRequest *req = [[VNDetectBarcodesRequest alloc] init];
            if (symbologyFilter.count) req.symbologies = symbologyFilter;
            VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:cg options:@{}];
            CGImageRelease(cg);
            NSError *vnErr = nil;
            if ([handler performRequests:@[req] error:&vnErr] && req.results.count) {
                NSMutableArray *barcodes = [NSMutableArray array];
                for (VNBarcodeObservation *obs in req.results) {
                    NSMutableDictionary *entry = [NSMutableDictionary dictionary];
                    entry[@"type"]    = obs.symbology ?: @"unknown";
                    if (obs.payloadStringValue) entry[@"payload"] = obs.payloadStringValue;
                    CGRect b = obs.boundingBox;
                    entry[@"bounds"] = @{
                        @"x": @(b.origin.x), @"y": @(1.0 - b.origin.y - b.size.height),
                        @"width": @(b.size.width), @"height": @(b.size.height),
                    };
                    [barcodes addObject:entry];
                }
                NSDictionary *result = @{ @"operation": @"barcode", @"barcodes": barcodes };
                NSData *jsonData = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
                if (jsonData)
                    outHeaders[@"X-MV-streamcapture-barcode"] =
                        [[NSString alloc] initWithData:jsonData encoding:NSUTF8StringEncoding];
            }
        } else {
            // No CGImage — still pass frame through without header
        }

        [writer writeFrame:jpeg extraHeaders:outHeaders];
    }];

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
    if (self.duration > 0) {
        fprintf(stderr, "Scanning for barcodes from '%s' for %.0f seconds... (Ctrl+C to stop early)\n",
                device.localizedName.UTF8String, self.duration);
        volatile BOOL never = NO;
        CSpinUntilFlagOrStop(&never, self.duration);
    } else {
        fprintf(stderr, "Scanning for barcodes from '%s'... (Ctrl+C to stop)\n", device.localizedName.UTF8String);
        while (!gStopCapture) { [NSThread sleepForTimeInterval:0.05]; }
    }

    [session stopRunning];
    signal(SIGINT, SIG_DFL);
#pragma clang diagnostic pop
    return YES;
}

@end
