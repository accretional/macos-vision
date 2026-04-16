#import "main.h"
#import "common/MVJsonEmit.h"
#import <AVFoundation/AVFoundation.h>
#import <Cocoa/Cocoa.h>
#include <math.h>

static NSString *const CaptureErrorDomain = @"CaptureError";

// ── JSON helpers ──────────────────────────────────────────────────────────────

static void CPrintJSON(id obj) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    if (data) {
        NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        printf("%s\n", str.UTF8String);
    }
}

static BOOL CWriteJSON(id obj, NSURL *url, NSError **error) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:error];
    if (!data) return NO;
    [[NSFileManager defaultManager] createDirectoryAtURL:[url URLByDeletingLastPathComponent]
                             withIntermediateDirectories:YES
                                              attributes:nil
                                                   error:nil];
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

// ── AVCapture photo delegate ──────────────────────────────────────────────────

@interface CapturePhotoDelegate : NSObject <AVCapturePhotoCaptureDelegate>
@property (nonatomic, strong, nullable) NSURL *outputURL;
@property (nonatomic) dispatch_semaphore_t semaphore;
- (instancetype)initWithSemaphore:(dispatch_semaphore_t)sem;
@end

@implementation CapturePhotoDelegate

- (instancetype)initWithSemaphore:(dispatch_semaphore_t)sem {
    if (self = [super init]) { _semaphore = sem; }
    return self;
}

- (void)captureOutput:(AVCapturePhotoOutput *)output
    didFinishProcessingPhoto:(AVCapturePhoto *)photo
                       error:(NSError *)error {
    if (!error) {
        NSData *data = [photo fileDataRepresentation];
        NSString *name = [NSString stringWithFormat:@"photo_%ld.jpg",
                          (long)[[NSDate date] timeIntervalSince1970]];
        NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()]
                      URLByAppendingPathComponent:name];
        [data writeToURL:url atomically:YES];
        self.outputURL = url;
    }
    dispatch_semaphore_signal(self.semaphore);
}

@end

// ── CaptureProcessor ──────────────────────────────────────────────────────────

@implementation CaptureProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation    = @"screenshot";
        _displayIndex = 0;
    }
    return self;
}

- (BOOL)runWithError:(NSError **)error {
    NSArray *validOps = @[@"screenshot", @"camera", @"mic", @"list-devices"];
    if (![validOps containsObject:self.operation]) {
        if (error) {
            *error = [NSError errorWithDomain:CaptureErrorDomain code:1
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:
                                                     @"Unknown operation '%@'. Valid: screenshot, camera, mic, list-devices",
                                                     self.operation]}];
        }
        return NO;
    }

    if ([self.operation isEqualToString:@"screenshot"]) return [self runScreenshotWithError:error];
    if ([self.operation isEqualToString:@"camera"])     return [self runCameraWithError:error];
    if ([self.operation isEqualToString:@"mic"])        return [self runMicWithError:error];
    if ([self.operation isEqualToString:@"list-devices"]) return [self runListDevicesWithError:error];
    return YES;
}

// ── list-devices ──────────────────────────────────────────────────────────────

- (BOOL)runListDevicesWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    NSMutableArray *videoTypes = [NSMutableArray arrayWithObject:AVCaptureDeviceTypeBuiltInWideAngleCamera];
    [videoTypes addObject:AVCaptureDeviceTypeExternalUnknown];
    if (@available(macOS 14.0, *)) {
        [videoTypes addObject:AVCaptureDeviceTypeExternal];
    }

    NSMutableArray *cameras = [NSMutableArray array];
    AVCaptureDeviceDiscoverySession *vds =
        [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:videoTypes
                                                               mediaType:AVMediaTypeVideo
                                                                position:AVCaptureDevicePositionUnspecified];
    for (AVCaptureDevice *d in vds.devices) {
        [cameras addObject:@{
            @"uniqueID": d.uniqueID,
            @"localizedName": d.localizedName,
            @"position": @(d.position),
            @"deviceType": d.deviceType,
            @"mediaType": @"video",
            @"hasVideo": @([d hasMediaType:AVMediaTypeVideo]),
        }];
    }

    NSMutableArray *mics = [NSMutableArray array];
    if (@available(macOS 14.0, *)) {
        AVCaptureDeviceDiscoverySession *ads =
            [AVCaptureDeviceDiscoverySession discoverySessionWithDeviceTypes:@[AVCaptureDeviceTypeMicrophone]
                                                                   mediaType:AVMediaTypeAudio
                                                                    position:AVCaptureDevicePositionUnspecified];
        for (AVCaptureDevice *d in ads.devices) {
            [mics addObject:@{
                @"uniqueID": d.uniqueID,
                @"localizedName": d.localizedName,
                @"deviceType": d.deviceType,
                @"mediaType": @"audio",
            }];
        }
    } else {
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wdeprecated-declarations"
        for (AVCaptureDevice *d in [AVCaptureDevice devicesWithMediaType:AVMediaTypeAudio]) {
            [mics addObject:@{
                @"uniqueID": d.uniqueID,
                @"localizedName": d.localizedName,
                @"deviceType": d.deviceType ?: @"",
                @"mediaType": @"audio",
            }];
        }
#pragma clang diagnostic pop
    }

    NSMutableDictionary *root = [@{ @"operation": @"list-devices", @"cameras": cameras, @"microphones": mics } mutableCopy];
    if (self.debug) root[@"processing_ms"] = @((NSInteger)(-[start timeIntervalSinceNow] * 1000.0));

    NSMutableDictionary *inner = [root mutableCopy];
    NSDictionary *env = MVMakeEnvelope(@"capture", @"list-devices", nil, inner);
    return MVEmitEnvelope(env, self.jsonOutput, error);
}

// ── output dir helper ─────────────────────────────────────────────────────────

- (NSURL *)resolveDestDir {
    if (self.artifactsDir.length) return [NSURL fileURLWithPath:self.artifactsDir];
    if (self.mediaOutput.length) return [[NSURL fileURLWithPath:self.mediaOutput] URLByDeletingLastPathComponent];
    return [NSURL fileURLWithPath:[[NSFileManager defaultManager] currentDirectoryPath]];
}

- (NSURL *)resolveMediaURLWithName:(NSString *)autoName {
    if (self.mediaOutput.length) return [NSURL fileURLWithPath:self.mediaOutput];
    return [[self resolveDestDir] URLByAppendingPathComponent:autoName];
}

- (BOOL)saveResult:(NSDictionary *)result mediaURL:(NSURL *)mediaURL error:(NSError **)error {
    NSArray *arts = mediaURL.path.length ? @[MVArtifactEntry(mediaURL.path, @"media")] : @[];
    NSDictionary *merged = MVResultByMergingArtifacts(result, arts);
    NSDictionary *env = MVMakeEnvelope(@"capture", self.operation, mediaURL.path, merged);
    return MVEmitEnvelope(env, self.jsonOutput, error);
}

// ── screenshot ────────────────────────────────────────────────────────────────

- (BOOL)runScreenshotWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    NSString *autoName = [NSString stringWithFormat:@"shot_%ld.png",
                          (long)[[NSDate date] timeIntervalSince1970]];
    NSURL *mediaURL = [self resolveMediaURLWithName:autoName];
    [[NSFileManager defaultManager] createDirectoryAtURL:mediaURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];

    // Capture directly to destination
    CGDirectDisplayID displayID = CGMainDisplayID();
    if (self.displayIndex > 0) {
        uint32_t count = 0;
        CGGetActiveDisplayList(0, NULL, &count);
        if ((NSInteger)count <= self.displayIndex) {
            if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:71
                                 userInfo:@{NSLocalizedDescriptionKey:
                                                [NSString stringWithFormat:
                                                 @"Display index %ld not found (%u active display(s))",
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

    NSMutableDictionary *result = [@{
        @"operation": @"screenshot",
        @"path":      mediaURL.path,
        @"width":     @(rep.pixelsWide),
        @"height":    @(rep.pixelsHigh),
    } mutableCopy];
    if (self.debug) result[@"processing_ms"] = @((NSInteger)(-[start timeIntervalSinceNow] * 1000.0));

    return [self saveResult:result mediaURL:mediaURL error:error];
}

// ── camera ────────────────────────────────────────────────────────────────────

- (BOOL)runCameraWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    fprintf(stderr, "Press ENTER to capture photo...\n");
    char lb[256]; fgets(lb, sizeof(lb), stdin);

    AVCaptureSession *session = [[AVCaptureSession alloc] init];
    session.sessionPreset = AVCaptureSessionPresetPhoto;

    AVCaptureDevice *device = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeVideo];
    if (!device) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:80
                             userInfo:@{NSLocalizedDescriptionKey: @"No camera available"}];
        return NO;
    }
    AVCaptureDeviceInput *input = [AVCaptureDeviceInput deviceInputWithDevice:device error:error];
    if (!input) return NO;
    [session addInput:input];

    AVCapturePhotoOutput *photoOutput = [[AVCapturePhotoOutput alloc] init];
    [session addOutput:photoOutput];
    [session startRunning];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    CapturePhotoDelegate *delegate = [[CapturePhotoDelegate alloc] initWithSemaphore:sem];
    [photoOutput capturePhotoWithSettings:[AVCapturePhotoSettings photoSettings]
                                 delegate:delegate];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 5 * NSEC_PER_SEC));
    [session stopRunning];

    if (!delegate.outputURL) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:81
                             userInfo:@{NSLocalizedDescriptionKey: @"Failed to capture photo"}];
        return NO;
    }

    // Move from temp to destination
    NSString *autoName = [NSString stringWithFormat:@"photo_%ld.jpg",
                          (long)[[NSDate date] timeIntervalSince1970]];
    NSURL *mediaURL = [self resolveMediaURLWithName:autoName];
    [[NSFileManager defaultManager] createDirectoryAtURL:mediaURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];
    [[NSFileManager defaultManager] moveItemAtURL:delegate.outputURL toURL:mediaURL error:nil];

    fprintf(stderr, "Saved %s\n", mediaURL.path.UTF8String);

    NSMutableDictionary *result = [@{
        @"operation": @"camera",
        @"path":      mediaURL.path,
    } mutableCopy];
    if (self.debug) result[@"processing_ms"] = @((NSInteger)(-[start timeIntervalSinceNow] * 1000.0));

    return [self saveResult:result mediaURL:mediaURL error:error];
}

// ── mic ───────────────────────────────────────────────────────────────────────

- (BOOL)runMicWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    // Verify a microphone is available before attempting to record
    AVCaptureDevice *micDevice = [AVCaptureDevice defaultDeviceWithMediaType:AVMediaTypeAudio];
    if (!micDevice) {
        if (error) *error = [NSError errorWithDomain:CaptureErrorDomain code:82
                             userInfo:@{NSLocalizedDescriptionKey: @"No microphone available"}];
        return NO;
    }

    NSString *autoName = [NSString stringWithFormat:@"mic_%ld.m4a",
                          (long)[[NSDate date] timeIntervalSince1970]];
    NSURL *mediaURL = [self resolveMediaURLWithName:autoName];
    [[NSFileManager defaultManager] createDirectoryAtURL:mediaURL.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];

    NSDictionary *settings = @{
        AVFormatIDKey:         @(kAudioFormatMPEG4AAC),
        AVSampleRateKey:       @44100.0,
        AVNumberOfChannelsKey: @1,
        AVEncoderBitRateKey:   @128000,
    };
    AVAudioRecorder *recorder = [[AVAudioRecorder alloc] initWithURL:mediaURL
                                                            settings:settings
                                                               error:error];
    if (!recorder) return NO;

    fprintf(stderr, "Press ENTER to START recording...\n");
    char sb[256]; fgets(sb, sizeof(sb), stdin);
    [recorder record];

    fprintf(stderr, "Recording... Press ENTER to STOP\n");
    char eb[256]; fgets(eb, sizeof(eb), stdin);

    NSTimeInterval duration = recorder.currentTime;
    [recorder stop];

    fprintf(stderr, "Saved %s\n", mediaURL.path.UTF8String);

    NSMutableDictionary *result = [@{
        @"operation": @"mic",
        @"path":      mediaURL.path,
        @"duration":  @(round(duration * 100.0) / 100.0),
    } mutableCopy];
    if (self.debug) result[@"processing_ms"] = @((NSInteger)(-[start timeIntervalSinceNow] * 1000.0));

    return [self saveResult:result mediaURL:mediaURL error:error];
}

@end
