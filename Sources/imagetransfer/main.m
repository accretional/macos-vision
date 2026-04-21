#import "main.h"
#import "common/MVJsonEmit.h"
#import <ImageCaptureCore/ImageCaptureCore.h>
#import <ImageIO/ImageIO.h>

static NSString *const ICCErrorDomain = @"ICCProcessorError";

typedef NS_ENUM(NSInteger, ICCErrorCode) {
    ICCErrorUnknownOperation  = 1,
    ICCErrorNoDeviceFound     = 2,
    ICCErrorDeviceIndexOOB    = 3,
    ICCErrorSessionFailed     = 4,
    ICCErrorSessionTimeout    = 5,
    ICCErrorCapabilityMissing = 6,
    ICCErrorNoFilesSelected   = 7,
    ICCErrorOutputRequired    = 8,
};

// ── ISO date formatter ────────────────────────────────────────────────────────

static NSDateFormatter *ICCISOFormatter(void) {
    static NSDateFormatter *fmt;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        fmt = [[NSDateFormatter alloc] init];
        fmt.dateFormat = @"yyyy-MM-dd'T'HH:mm:ssZ";
        fmt.locale = [NSLocale localeWithLocaleIdentifier:@"en_US_POSIX"];
    });
    return fmt;
}

// ── DPI snapping ──────────────────────────────────────────────────────────────
//
// Snap requestedDPI to the nearest value in `supported` (an NSIndexSet of valid
// DPI values). Prefers values >= requested; falls back to the largest below.

static NSUInteger ICCSnapDPI(NSUInteger requestedDPI, NSIndexSet *supported) {
    if (supported.count == 0) return requestedDPI;
    NSUInteger above = [supported indexGreaterThanOrEqualToIndex:requestedDPI];
    if (above != NSNotFound) return above;
    NSUInteger below = [supported indexLessThanOrEqualToIndex:requestedDPI];
    return (below != NSNotFound) ? below : [supported firstIndex];
}

// ── JSON sanitizer ────────────────────────────────────────────────────────────
//
// EXIF/metadata dicts can contain NSData blobs, NSDate objects, and other types
// that NSJSONSerialization can't handle. Recursively convert anything that isn't
// a JSON primitive to its -description string.

static id ICCSanitizeForJSON(id value) {
    if (!value) return [NSNull null];
    if ([value isKindOfClass:[NSString class]] ||
        [value isKindOfClass:[NSNumber class]] ||
        [value isKindOfClass:[NSNull class]]) return value;
    if ([value isKindOfClass:[NSArray class]]) {
        NSMutableArray *out = [NSMutableArray arrayWithCapacity:[(NSArray *)value count]];
        for (id item in (NSArray *)value) [out addObject:ICCSanitizeForJSON(item)];
        return [out copy];
    }
    if ([value isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *out = [NSMutableDictionary dictionary];
        [(NSDictionary *)value enumerateKeysAndObjectsUsingBlock:^(id key, id obj, BOOL *stop) {
            NSString *strKey = [key isKindOfClass:[NSString class]] ? key : [key description];
            out[strKey] = ICCSanitizeForJSON(obj);
        }];
        return [out copy];
    }
    return [value description];
}

// ── Browser delegate ──────────────────────────────────────────────────────────
//
// ICDeviceBrowser calls its delegate on the main thread, so the run loop must
// be spinning when we call [browser start]. We poll a BOOL flag set by the
// delegate and spin [[NSRunLoop currentRunLoop] runMode:...] in a tight loop.

@interface ICCBrowserHelper : NSObject <ICDeviceBrowserDelegate>
@property (nonatomic) BOOL localEnumDone;
@property (nonatomic, strong) NSMutableArray<ICDevice *> *devices;
@end

@implementation ICCBrowserHelper
- (instancetype)init {
    if (self = [super init]) { _devices = [NSMutableArray array]; }
    return self;
}
- (void)deviceBrowser:(ICDeviceBrowser *)browser didAddDevice:(ICDevice *)device moreComing:(BOOL)moreComing {
    [_devices addObject:device];
    if (!moreComing) _localEnumDone = YES;
}
- (void)deviceBrowser:(ICDeviceBrowser *)browser didRemoveDevice:(ICDevice *)device moreGoing:(BOOL)moreGoing {}
- (void)deviceBrowserDidEnumerateLocalDevices:(ICDeviceBrowser *)browser {
    _localEnumDone = YES;
}
@end

// ── Camera device delegate ────────────────────────────────────────────────────
//
// Conforms to ICCameraDeviceDelegate (which extends ICDeviceDelegate).
// All required protocol methods are implemented; most are no-ops.
// `capturedFile` is set when a new item arrives after catalog (tethered capture).

@interface ICCSessionHelper : NSObject <ICCameraDeviceDelegate>
@property (nonatomic) BOOL sessionOpened;
@property (nonatomic) BOOL catalogReady;
@property (nonatomic, strong, nullable) NSError *sessionError;
@property (nonatomic, strong, nullable) ICCameraFile *capturedFile;
@end

@implementation ICCSessionHelper

// ICDeviceDelegate required
- (void)device:(ICDevice *)device didOpenSessionWithError:(NSError * _Nullable)error {
    _sessionError  = error;
    _sessionOpened = YES;
}
- (void)device:(ICDevice *)device didCloseSessionWithError:(NSError * _Nullable)error {}
- (void)didRemoveDevice:(ICDevice *)device {}

// ICCameraDeviceDelegate required
- (void)cameraDevice:(ICCameraDevice *)camera didAddItems:(NSArray<ICCameraItem *> *)items {
    // Capture: items that arrive after catalog completion are newly captured files.
    if (_capturedFile) return;
    for (ICCameraItem *item in items) {
        if ([item isKindOfClass:[ICCameraFile class]]) {
            ICCameraFile *f = (ICCameraFile *)item;
            if (f.addedAfterContentCatalogCompleted) {
                _capturedFile = f;
                return;
            }
        }
    }
}
- (void)cameraDevice:(ICCameraDevice *)camera didRemoveItems:(NSArray<ICCameraItem *> *)items {}
- (void)cameraDevice:(ICCameraDevice *)camera
    didReceiveThumbnail:(CGImageRef _Nullable)thumbnail
    forItem:(ICCameraItem *)item
    error:(NSError * _Nullable)error {}
- (void)cameraDevice:(ICCameraDevice *)camera
    didReceiveMetadata:(NSDictionary * _Nullable)metadata
    forItem:(ICCameraItem *)item
    error:(NSError * _Nullable)error {}
- (void)cameraDevice:(ICCameraDevice *)camera didRenameItems:(NSArray<ICCameraItem *> *)items {}
- (void)cameraDeviceDidChangeCapability:(ICCameraDevice *)camera {}
- (void)cameraDevice:(ICCameraDevice *)camera didReceivePTPEvent:(NSData *)eventData {}
- (void)cameraDeviceDidRemoveAccessRestriction:(ICDevice *)device {}
- (void)cameraDeviceDidEnableAccessRestriction:(ICDevice *)device {}

- (void)deviceDidBecomeReadyWithCompleteContentCatalog:(ICCameraDevice *)device {
    _catalogReady = YES;
}

@end

// ── Scanner device delegate ───────────────────────────────────────────────────

@interface ICCScannerHelper : NSObject <ICScannerDeviceDelegate>
@property (nonatomic) BOOL sessionOpened;
@property (nonatomic) BOOL functionalUnitSelected;
@property (nonatomic) BOOL overviewDone;
@property (nonatomic) BOOL scanDone;
@property (nonatomic, strong, nullable) NSError *sessionError;
@property (nonatomic, strong, nullable) NSError *overviewError;
@property (nonatomic, strong, nullable) NSError *scanError;
@property (nonatomic, strong) NSMutableArray<NSURL *> *scannedURLs;
@end

@implementation ICCScannerHelper

- (instancetype)init {
    if (self = [super init]) { _scannedURLs = [NSMutableArray array]; }
    return self;
}

// ICDeviceDelegate required
- (void)device:(ICDevice *)device didOpenSessionWithError:(NSError * _Nullable)error {
    _sessionError  = error;
    _sessionOpened = YES;
}
- (void)device:(ICDevice *)device didCloseSessionWithError:(NSError * _Nullable)error {}
- (void)didRemoveDevice:(ICDevice *)device {}

// ICScannerDeviceDelegate optional
- (void)scannerDevice:(ICScannerDevice *)scanner
    didSelectFunctionalUnit:(ICScannerFunctionalUnit *)functionalUnit
    error:(NSError * _Nullable)error {
    _functionalUnitSelected = YES;
}
- (void)scannerDevice:(ICScannerDevice *)scanner didScanToURL:(NSURL *)url {
    [_scannedURLs addObject:url];
}
- (void)scannerDevice:(ICScannerDevice *)scanner
    didCompleteOverviewScanWithError:(NSError * _Nullable)error {
    _overviewError = error;
    _overviewDone  = YES;
}
- (void)scannerDevice:(ICScannerDevice *)scanner
    didCompleteScanWithError:(NSError * _Nullable)error {
    _scanError = error;
    _scanDone  = YES;
}

@end

// ── Run-loop spinner ──────────────────────────────────────────────────────────
//
// Spins the main run loop in 50 ms slices until `condition()` returns YES or
// timeout (seconds) elapses. Returns YES if condition became true in time.

static BOOL ICCSpinUntilCondition(BOOL (^condition)(void), NSTimeInterval timeout) {
    NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:timeout];
    while ([[NSDate date] compare:deadline] == NSOrderedAscending) {
        [[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode
                                 beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        if (condition()) return YES;
    }
    return condition();
}

// ── ICCProcessor ──────────────────────────────────────────────────────────────

@implementation ICCProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation     = @"list-devices";
        _deviceIndex   = 0;
        _browseTimeout = 2.0;
        _outputFormat  = @"tiff";
    }
    return self;
}

- (BOOL)runWithError:(NSError **)error {
    NSArray<NSString *> *validOps = @[
        @"list-devices",
        @"list-files", @"camera/files",        // list-files kept for backwards compat
        @"camera/thumbnail",
        @"camera/metadata",
        @"camera/import",
        @"camera/delete",
        @"camera/capture",
        @"camera/sync-clock",
        @"scanner/preview",
        @"scanner/scan",
    ];
    if (![validOps containsObject:self.operation]) {
        if (error) {
            *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorUnknownOperation
                                     userInfo:@{NSLocalizedDescriptionKey:
                                                    [NSString stringWithFormat:
                                                     @"Unknown operation '%@'. Valid: %@",
                                                     self.operation,
                                                     [validOps componentsJoinedByString:@", "]]}];
        }
        return NO;
    }

    if ([self.operation isEqualToString:@"list-devices"])
        return [self runListDevicesWithError:error];
    if ([self.operation isEqualToString:@"list-files"] ||
        [self.operation isEqualToString:@"camera/files"])
        return [self runCameraFilesWithError:error];
    if ([self.operation isEqualToString:@"camera/thumbnail"])
        return [self runCameraThumbnailWithError:error];
    if ([self.operation isEqualToString:@"camera/metadata"])
        return [self runCameraMetadataWithError:error];
    if ([self.operation isEqualToString:@"camera/import"])
        return [self runCameraImportWithError:error];
    if ([self.operation isEqualToString:@"camera/delete"])
        return [self runCameraDeleteWithError:error];
    if ([self.operation isEqualToString:@"camera/capture"])
        return [self runCameraCaptureWithError:error];
    if ([self.operation isEqualToString:@"camera/sync-clock"])
        return [self runCameraSyncClockWithError:error];
    if ([self.operation isEqualToString:@"scanner/preview"])
        return [self runScannerPreviewWithError:error];
    if ([self.operation isEqualToString:@"scanner/scan"])
        return [self runScannerScanWithError:error];
    return YES;
}

// ── Shared: browse for devices ────────────────────────────────────────────────

- (NSArray<ICDevice *> *)browseDevicesWithTypeMask:(ICDeviceTypeMask)mask {
    ICCBrowserHelper *helper  = [[ICCBrowserHelper alloc] init];
    ICDeviceBrowser  *browser = [[ICDeviceBrowser alloc] init];
    browser.delegate = helper;
    browser.browsedDeviceTypeMask = mask;
    [browser start];
    ICCSpinUntilCondition(^{ return helper.localEnumDone; }, self.browseTimeout);
    [browser stop];
    return [helper.devices copy];
}

// ── Shared: device summary dict ───────────────────────────────────────────────

- (NSDictionary *)deviceInfoForDevice:(ICDevice *)device index:(NSInteger)idx {
    NSMutableDictionary *info = [NSMutableDictionary dictionary];
    info[@"index"] = @(idx);
    if (device.name)               info[@"name"]          = device.name;
    if (device.UUIDString)         info[@"uuid"]          = device.UUIDString;
    if (device.transportType)      info[@"transport_type"]= device.transportType;
    if (device.productKind)        info[@"product_kind"]  = device.productKind;
    if (device.locationDescription)info[@"location"]      = device.locationDescription;
    if (device.serialNumberString) info[@"serial_number"] = device.serialNumberString;
    info[@"usb_vendor_id"]  = @(device.usbVendorID);
    info[@"usb_product_id"] = @(device.usbProductID);
    info[@"capabilities"]   = device.capabilities ?: @[];

    if ([device isKindOfClass:[ICCameraDevice class]]) {
        ICCameraDevice *cam = (ICCameraDevice *)device;
        info[@"type"]      = @"camera";
        if (cam.mountPoint) info[@"mount_point"] = cam.mountPoint;
        info[@"ejectable"] = @(cam.isEjectable);
        info[@"locked"]    = @(cam.isLocked);
        if (cam.batteryLevelAvailable) info[@"battery_level"] = @(cam.batteryLevel);
    } else {
        info[@"type"] = @"scanner";
    }
    return [info copy];
}

// ── Shared: open camera session ───────────────────────────────────────────────
//
// Browses for cameras, validates deviceIndex, opens session, optionally waits
// for the content catalog. Returns YES if the camera is ready for use.
// The caller is responsible for calling [camera requestCloseSession].

- (BOOL)prepareCameraSession:(ICCameraDevice * _Nullable __autoreleasing *)cameraOut
                     session:(ICCSessionHelper * _Nullable __autoreleasing *)sessionOut
                 needCatalog:(BOOL)needCatalog
                       error:(NSError **)error {
    NSArray<ICDevice *> *found = [self browseDevicesWithTypeMask:ICDeviceTypeMaskCamera];
    NSMutableArray<ICCameraDevice *> *cameras = [NSMutableArray array];
    for (ICDevice *d in found) {
        if ([d isKindOfClass:[ICCameraDevice class]]) [cameras addObject:(ICCameraDevice *)d];
    }

    if (cameras.count == 0) {
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorNoDeviceFound
            userInfo:@{NSLocalizedDescriptionKey:
                @"No camera device found. Connect a camera (USB, FireWire, or network) and retry."}];
        return NO;
    }
    if (self.deviceIndex >= (NSInteger)cameras.count) {
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorDeviceIndexOOB
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:
                 @"--device-index %ld is out of range (%lu camera(s) found). "
                 "Use list-devices to see connected devices.",
                 (long)self.deviceIndex, (unsigned long)cameras.count]}];
        return NO;
    }

    ICCameraDevice *camera = cameras[self.deviceIndex];
    ICCSessionHelper *session = [[ICCSessionHelper alloc] init];
    camera.delegate = session;
    [camera requestOpenSession];

    if (!ICCSpinUntilCondition(^{ return session.sessionOpened; }, 5.0)) {
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorSessionTimeout
            userInfo:@{NSLocalizedDescriptionKey: @"Timed out waiting for the camera session to open."}];
        return NO;
    }
    if (session.sessionError) {
        if (error) *error = session.sessionError;
        return NO;
    }

    if (needCatalog) {
        ICCSpinUntilCondition(^{ return session.catalogReady; }, 15.0);
    }

    if (cameraOut)  *cameraOut  = camera;
    if (sessionOut) *sessionOut = session;
    return YES;
}

// ── Shared: open scanner session ──────────────────────────────────────────────

- (BOOL)prepareScannerSession:(ICScannerDevice * _Nullable __autoreleasing *)scannerOut
                       helper:(ICCScannerHelper * _Nullable __autoreleasing *)helperOut
                        error:(NSError **)error {
    NSArray<ICDevice *> *found = [self browseDevicesWithTypeMask:ICDeviceTypeMaskScanner];
    NSMutableArray<ICScannerDevice *> *scanners = [NSMutableArray array];
    for (ICDevice *d in found) {
        if ([d isKindOfClass:[ICScannerDevice class]]) [scanners addObject:(ICScannerDevice *)d];
    }

    if (scanners.count == 0) {
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorNoDeviceFound
            userInfo:@{NSLocalizedDescriptionKey: @"No scanner found. Connect a scanner and retry."}];
        return NO;
    }
    if (self.deviceIndex >= (NSInteger)scanners.count) {
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorDeviceIndexOOB
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:
                 @"--device-index %ld is out of range (%lu scanner(s) found).",
                 (long)self.deviceIndex, (unsigned long)scanners.count]}];
        return NO;
    }

    ICScannerDevice *scanner = scanners[self.deviceIndex];
    ICCScannerHelper *helper = [[ICCScannerHelper alloc] init];
    scanner.delegate = helper;
    [scanner requestOpenSession];

    if (!ICCSpinUntilCondition(^{ return helper.sessionOpened; }, 5.0)) {
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorSessionTimeout
            userInfo:@{NSLocalizedDescriptionKey: @"Timed out waiting for the scanner session to open."}];
        return NO;
    }
    if (helper.sessionError) {
        if (error) *error = helper.sessionError;
        return NO;
    }

    // Wait for functional unit to be auto-selected (scanner fires this on session open)
    ICCSpinUntilCondition(^{ return helper.functionalUnitSelected; }, 5.0);

    if (scannerOut) *scannerOut = scanner;
    if (helperOut)  *helperOut  = helper;
    return YES;
}

// ── list-devices ──────────────────────────────────────────────────────────────

- (BOOL)runListDevicesWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    ICDeviceTypeMask mask = ICDeviceTypeMaskCamera | ICDeviceTypeMaskScanner;
    NSArray<ICDevice *> *found = [self browseDevicesWithTypeMask:mask];

    NSMutableArray<NSDictionary *> *cameras  = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *scanners = [NSMutableArray array];

    for (NSInteger i = 0; i < (NSInteger)found.count; i++) {
        ICDevice *device = found[i];
        NSDictionary *info = [self deviceInfoForDevice:device index:i];
        if ([device isKindOfClass:[ICCameraDevice class]]) {
            [cameras addObject:info];
        } else {
            [scanners addObject:info];
        }
    }

    NSMutableDictionary *result = [@{
        @"camera_count":  @(cameras.count),
        @"scanner_count": @(scanners.count),
        @"cameras":       cameras,
        @"scanners":      scanners,
    } mutableCopy];

    if (self.debug && start) {
        result[@"processing_ms"] =
            @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    NSDictionary *envelope = MVMakeEnvelope(@"imagetransfer", self.operation, nil, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── camera/files ──────────────────────────────────────────────────────────────

- (BOOL)runCameraFilesWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    ICCameraDevice *camera = nil;
    ICCSessionHelper *session = nil;
    if (![self prepareCameraSession:&camera session:&session needCatalog:YES error:error]) return NO;

    NSMutableArray<NSDictionary *> *files = [NSMutableArray array];
    NSDateFormatter *fmt = ICCISOFormatter();

    for (ICCameraItem *item in camera.mediaFiles) {
        if (![item isKindOfClass:[ICCameraFile class]]) continue;
        ICCameraFile *f = (ICCameraFile *)item;

        NSMutableDictionary *entry = [NSMutableDictionary dictionary];
        if (f.name)             entry[@"name"]               = f.name;
        if (f.originalFilename) entry[@"original_filename"]  = f.originalFilename;
        if (f.UTI)              entry[@"uti"]                = f.UTI;
        entry[@"file_size"]     = @(f.fileSize);
        entry[@"width"]         = @(f.width);
        entry[@"height"]        = @(f.height);
        if (f.duration > 0)     entry[@"duration_s"]         = @(f.duration);
        if (f.gpsString)        entry[@"gps"]                = f.gpsString;
        if (f.fileCreationDate)     entry[@"created"]        = [fmt stringFromDate:f.fileCreationDate];
        if (f.fileModificationDate) entry[@"modified"]       = [fmt stringFromDate:f.fileModificationDate];
        if (f.exifCreationDate)     entry[@"exif_created"]   = [fmt stringFromDate:f.exifCreationDate];
        if (f.burstUUID)        entry[@"burst_uuid"]         = f.burstUUID;
        if (f.groupUUID)        entry[@"group_uuid"]         = f.groupUUID;
        entry[@"raw"]           = @(f.isRaw);
        if (f.highFramerate)    entry[@"high_framerate"]     = @YES;
        if (f.timeLapse)        entry[@"time_lapse"]         = @YES;
        if (f.pairedRawImage)   entry[@"has_raw_pair"]       = @YES;
        if (f.sidecarFiles.count > 0) entry[@"sidecar_count"] = @(f.sidecarFiles.count);
        if (f.fileSystemPath)   entry[@"fs_path"]            = f.fileSystemPath;
        [files addObject:[entry copy]];
    }

    [camera requestCloseSession];

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (camera.name)       result[@"device_name"]      = camera.name;
    if (camera.UUIDString) result[@"device_uuid"]      = camera.UUIDString;
    result[@"catalog_complete"] = @(session.catalogReady);
    result[@"file_count"]       = @(files.count);
    result[@"files"]            = files;

    if (self.debug && start) {
        result[@"processing_ms"] =
            @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    NSDictionary *envelope = MVMakeEnvelope(@"imagetransfer", self.operation, nil, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── camera/thumbnail ──────────────────────────────────────────────────────────

- (BOOL)runCameraThumbnailWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    ICCameraDevice *camera = nil;
    ICCSessionHelper *session = nil;
    if (![self prepareCameraSession:&camera session:&session needCatalog:YES error:error]) return NO;

    // Find file at fileIndex within mediaFiles
    ICCameraFile *file = nil;
    NSInteger idx = 0;
    for (ICCameraItem *item in camera.mediaFiles) {
        if (![item isKindOfClass:[ICCameraFile class]]) continue;
        if (idx == self.fileIndex) { file = (ICCameraFile *)item; break; }
        idx++;
    }

    if (!file) {
        [camera requestCloseSession];
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorDeviceIndexOOB
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:
                 @"--file-index %ld is out of range or no files on camera.",
                 (long)self.fileIndex]}];
        return NO;
    }

    // Request thumbnail; completion fires on a non-main thread — semaphore is safe here
    NSMutableDictionary *thumbOpts = [NSMutableDictionary dictionary];
    if (self.thumbSize > 0) {
        thumbOpts[(NSString *)kCGImageSourceThumbnailMaxPixelSize] = @(self.thumbSize);
    }

    __block NSData *thumbData   = nil;
    __block NSError *thumbError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    [file requestThumbnailDataWithOptions:thumbOpts
                               completion:^(NSData * _Nullable data, NSError * _Nullable err) {
        thumbData  = data;
        thumbError = err;
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    [camera requestCloseSession];

    if (thumbError) {
        if (error) *error = thumbError;
        return NO;
    }
    if (!thumbData) {
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorSessionFailed
            userInfo:@{NSLocalizedDescriptionKey: @"Thumbnail data was nil (camera may not have generated one for this file)."}];
        return NO;
    }

    // Write JPEG to outputPath when provided
    NSString *writtenPath = nil;
    if (self.outputPath.length) {
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:self.outputPath isDirectory:&isDir];
        writtenPath = isDir
            ? [self.outputPath stringByAppendingPathComponent:
               [(file.name ?: @"thumbnail") stringByAppendingPathExtension:@"jpg"]]
            : self.outputPath;

        NSError *writeErr = nil;
        if (![thumbData writeToFile:writtenPath options:NSDataWritingAtomic error:&writeErr]) {
            if (error) *error = writeErr;
            return NO;
        }
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (camera.name) result[@"device_name"]     = camera.name;
    if (file.name)   result[@"filename"]        = file.name;
    result[@"file_index"]                       = @(self.fileIndex);
    result[@"thumbnail_size_bytes"]             = @(thumbData.length);
    if (writtenPath) result[@"thumbnail_path"]  = writtenPath;
    if (self.debug && start) {
        result[@"processing_ms"] =
            @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    NSDictionary *envelope = MVMakeEnvelope(@"imagetransfer", self.operation, nil, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── camera/metadata ───────────────────────────────────────────────────────────

- (BOOL)runCameraMetadataWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    ICCameraDevice *camera = nil;
    ICCSessionHelper *session = nil;
    if (![self prepareCameraSession:&camera session:&session needCatalog:YES error:error]) return NO;

    ICCameraFile *file = nil;
    NSInteger idx = 0;
    for (ICCameraItem *item in camera.mediaFiles) {
        if (![item isKindOfClass:[ICCameraFile class]]) continue;
        if (idx == self.fileIndex) { file = (ICCameraFile *)item; break; }
        idx++;
    }

    if (!file) {
        [camera requestCloseSession];
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorDeviceIndexOOB
            userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:
                 @"--file-index %ld is out of range or no files on camera.",
                 (long)self.fileIndex]}];
        return NO;
    }

    __block NSDictionary *metaDict  = nil;
    __block NSError *metaError      = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    [file requestMetadataDictionaryWithOptions:@{}
                                    completion:^(NSDictionary * _Nullable meta, NSError * _Nullable err) {
        metaDict  = meta;
        metaError = err;
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 30 * NSEC_PER_SEC));
    [camera requestCloseSession];

    if (metaError) {
        if (error) *error = metaError;
        return NO;
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (camera.name) result[@"device_name"] = camera.name;
    if (file.name)   result[@"filename"]    = file.name;
    result[@"file_index"]                   = @(self.fileIndex);
    result[@"metadata"]                     = metaDict ? ICCSanitizeForJSON(metaDict) : [NSNull null];
    if (self.debug && start) {
        result[@"processing_ms"] =
            @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    NSDictionary *envelope = MVMakeEnvelope(@"imagetransfer", self.operation, nil, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── camera/import ─────────────────────────────────────────────────────────────

- (BOOL)runCameraImportWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    if (!self.outputPath.length) {
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorOutputRequired
            userInfo:@{NSLocalizedDescriptionKey:
                @"--output <directory> is required for camera/import."}];
        return NO;
    }

    ICCameraDevice *camera = nil;
    ICCSessionHelper *session = nil;
    if (![self prepareCameraSession:&camera session:&session needCatalog:YES error:error]) return NO;

    // Ensure output directory exists
    NSString *downloadDir = self.outputPath;
    BOOL isDir = NO;
    [[NSFileManager defaultManager] fileExistsAtPath:downloadDir isDirectory:&isDir];
    if (!isDir) {
        NSError *mkErr = nil;
        if (![[NSFileManager defaultManager] createDirectoryAtPath:downloadDir
                                      withIntermediateDirectories:YES attributes:nil error:&mkErr]) {
            [camera requestCloseSession];
            if (error) *error = mkErr;
            return NO;
        }
    }

    // Build download list
    NSMutableArray<ICCameraFile *> *toDownload = [NSMutableArray array];
    NSInteger idx = 0;
    for (ICCameraItem *item in camera.mediaFiles) {
        if (![item isKindOfClass:[ICCameraFile class]]) continue;
        ICCameraFile *f = (ICCameraFile *)item;
        if (self.allFiles || idx == self.fileIndex) [toDownload addObject:f];
        if (!self.allFiles && idx == self.fileIndex) break;
        idx++;
    }

    if (toDownload.count == 0) {
        [camera requestCloseSession];
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorNoFilesSelected
            userInfo:@{NSLocalizedDescriptionKey:
                @"No files selected. Use --file-index N to target a specific file, or --all for all files."}];
        return NO;
    }

    NSURL *downloadURL = [NSURL fileURLWithPath:downloadDir isDirectory:YES];
    NSMutableArray<NSDictionary *> *imported = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *failed   = [NSMutableArray array];

    // Download sequentially — parallel calls can overwhelm the camera driver
    for (ICCameraFile *f in toDownload) {
        NSMutableDictionary *opts = [NSMutableDictionary dictionary];
        opts[ICDownloadsDirectoryURL] = downloadURL;
        opts[ICOverwrite] = @YES;
        if (self.deleteAfter)      opts[ICDeleteAfterSuccessfulDownload] = @YES;
        if (self.downloadSidecars) opts[ICDownloadSidecarFiles]          = @YES;

        __block NSString *savedFilename  = nil;
        __block NSError *downloadError   = nil;
        dispatch_semaphore_t sem = dispatch_semaphore_create(0);

        // SDK completion signature: (NSString * _Nullable filename, NSError * _Nullable error)
        [f requestDownloadWithOptions:opts
                           completion:^(NSString * _Nullable filename, NSError * _Nullable err) {
            savedFilename  = filename;
            downloadError  = err;
            dispatch_semaphore_signal(sem);
        }];

        dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));

        if (downloadError) {
            [failed addObject:@{
                @"filename": f.name ?: @"?",
                @"error":    downloadError.localizedDescription
            }];
        } else {
            NSString *savedName = savedFilename ?: f.name;
            NSString *savedPath = savedName.length
                ? [downloadDir stringByAppendingPathComponent:savedName]
                : downloadDir;
            NSMutableDictionary *entry = [NSMutableDictionary dictionary];
            if (f.name)      entry[@"filename"]  = f.name;
            if (savedPath)   entry[@"path"]      = savedPath;
            entry[@"file_size"] = @(f.fileSize);
            [imported addObject:[entry copy]];
        }
    }

    [camera requestCloseSession];

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (camera.name) result[@"device_name"]  = camera.name;
    result[@"imported_count"] = @(imported.count);
    result[@"failed_count"]   = @(failed.count);
    result[@"imported"]       = imported;
    if (failed.count > 0) result[@"failed"]  = failed;
    if (self.debug && start) {
        result[@"processing_ms"] =
            @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    NSDictionary *envelope = MVMakeEnvelope(@"imagetransfer", self.operation, nil, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── camera/delete ─────────────────────────────────────────────────────────────

- (BOOL)runCameraDeleteWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    ICCameraDevice *camera = nil;
    ICCSessionHelper *session = nil;
    if (![self prepareCameraSession:&camera session:&session needCatalog:YES error:error]) return NO;

    // Check capability
    BOOL canDeleteOne = [camera.capabilities containsObject:ICCameraDeviceCanDeleteOneFile];
    BOOL canDeleteAll = [camera.capabilities containsObject:ICCameraDeviceCanDeleteAllFiles];
    if (!canDeleteOne && !canDeleteAll) {
        [camera requestCloseSession];
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorCapabilityMissing
            userInfo:@{NSLocalizedDescriptionKey:
                @"Camera does not report file-deletion capability. "
                "This camera may be read-only or require a different connection mode."}];
        return NO;
    }

    // Build delete list
    NSMutableArray<ICCameraFile *> *toDelete = [NSMutableArray array];
    NSInteger idx = 0;
    for (ICCameraItem *item in camera.mediaFiles) {
        if (![item isKindOfClass:[ICCameraFile class]]) continue;
        ICCameraFile *f = (ICCameraFile *)item;
        if (self.allFiles || idx == self.fileIndex) [toDelete addObject:f];
        if (!self.allFiles && idx == self.fileIndex) break;
        idx++;
    }

    if (toDelete.count == 0) {
        [camera requestCloseSession];
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorNoFilesSelected
            userInfo:@{NSLocalizedDescriptionKey:
                @"No files selected. Use --file-index N or --all."}];
        return NO;
    }

    __block NSMutableArray<NSDictionary *> *failedItems = [NSMutableArray array];
    __block NSError *deleteCompletionError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);

    [camera requestDeleteFiles:toDelete
                  deleteFailed:^(NSDictionary<NSString *, ICCameraItem *> *info) {
        [info enumerateKeysAndObjectsUsingBlock:^(NSString *reason, ICCameraItem *item, BOOL *stop) {
            [failedItems addObject:@{@"filename": item.name ?: @"?", @"reason": reason}];
        }];
    }
               completion:^(NSDictionary<NSString *, id> *info, NSError * _Nullable err) {
        deleteCompletionError = err;
        dispatch_semaphore_signal(sem);
    }];

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 60 * NSEC_PER_SEC));
    [camera requestCloseSession];

    NSUInteger deletedCount = toDelete.count - failedItems.count;

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (camera.name) result[@"device_name"] = camera.name;
    result[@"requested_count"] = @(toDelete.count);
    result[@"deleted_count"]   = @(deletedCount);
    if (failedItems.count > 0) result[@"failed"] = [failedItems copy];
    if (deleteCompletionError) result[@"error"] = deleteCompletionError.localizedDescription;
    if (self.debug && start) {
        result[@"processing_ms"] =
            @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    NSDictionary *envelope = MVMakeEnvelope(@"imagetransfer", self.operation, nil, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── camera/capture ────────────────────────────────────────────────────────────
//
// Fire the shutter remotely; wait for the new file to appear on the device.
// Does NOT download the file — use camera/import for that.

- (BOOL)runCameraCaptureWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    // Catalog not needed — we only open session, check capability, fire shutter,
    // and wait for cameraDevice:didAddItems: with addedAfterContentCatalogCompleted == YES
    ICCameraDevice *camera = nil;
    ICCSessionHelper *session = nil;
    if (![self prepareCameraSession:&camera session:&session needCatalog:NO error:error]) return NO;

    if (![camera.capabilities containsObject:ICCameraDeviceCanTakePicture]) {
        [camera requestCloseSession];
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorCapabilityMissing
            userInfo:@{NSLocalizedDescriptionKey:
                @"Camera does not support remote tethered capture "
                "(ICCameraDeviceCanTakePicture capability absent). "
                "Ensure the camera is connected via USB data cable and is in a shooting mode."}];
        return NO;
    }

    [camera requestTakePicture];

    // Wait up to 30 s — DSLRs can take several seconds to autofocus, expose, and transfer
    BOOL arrived = ICCSpinUntilCondition(^BOOL{ return session.capturedFile != nil; }, 30.0);
    ICCameraFile *captured = session.capturedFile;
    [camera requestCloseSession];

    if (!arrived || !captured) {
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorSessionTimeout
            userInfo:@{NSLocalizedDescriptionKey:
                @"Timed out waiting for captured file to appear on the camera. "
                "Make sure the camera is ready to shoot and not busy."}];
        return NO;
    }

    NSDateFormatter *fmt = ICCISOFormatter();
    NSMutableDictionary *fileInfo = [NSMutableDictionary dictionary];
    if (captured.name)             fileInfo[@"name"]          = captured.name;
    if (captured.UTI)              fileInfo[@"uti"]           = captured.UTI;
    fileInfo[@"file_size"]         = @(captured.fileSize);
    fileInfo[@"width"]             = @(captured.width);
    fileInfo[@"height"]            = @(captured.height);
    if (captured.fileCreationDate) fileInfo[@"created"]       = [fmt stringFromDate:captured.fileCreationDate];
    if (captured.inTemporaryStore) fileInfo[@"in_temp_store"] = @YES;

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (camera.name) result[@"device_name"]  = camera.name;
    result[@"captured_file"] = [fileInfo copy];
    if (self.debug && start) {
        result[@"processing_ms"] =
            @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    NSDictionary *envelope = MVMakeEnvelope(@"imagetransfer", self.operation, nil, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── camera/sync-clock ─────────────────────────────────────────────────────────

- (BOOL)runCameraSyncClockWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    ICCameraDevice *camera = nil;
    ICCSessionHelper *session = nil;
    if (![self prepareCameraSession:&camera session:&session needCatalog:NO error:error]) return NO;

    if (![camera.capabilities containsObject:ICCameraDeviceCanSyncClock]) {
        [camera requestCloseSession];
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorCapabilityMissing
            userInfo:@{NSLocalizedDescriptionKey:
                @"Camera does not support clock synchronisation "
                "(ICCameraDeviceCanSyncClock capability absent)."}];
        return NO;
    }

    NSTimeInterval driftBefore = camera.timeOffset;
    [camera requestSyncClock];

    // No callback for sync — spin 500 ms to let the camera apply the new time
    ICCSpinUntilCondition(^{ return NO; }, 0.5);

    NSTimeInterval driftAfter = camera.timeOffset;
    [camera requestCloseSession];

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (camera.name) result[@"device_name"]  = camera.name;
    result[@"drift_before_s"] = @(driftBefore);
    result[@"drift_after_s"]  = @(driftAfter);
    if (self.debug && start) {
        result[@"processing_ms"] =
            @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    NSDictionary *envelope = MVMakeEnvelope(@"imagetransfer", self.operation, nil, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── scanner/preview ───────────────────────────────────────────────────────────

- (BOOL)runScannerPreviewWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    ICScannerDevice *scanner  = nil;
    ICCScannerHelper *helper  = nil;
    if (![self prepareScannerSession:&scanner helper:&helper error:error]) return NO;

    ICScannerFunctionalUnit *fu = scanner.selectedFunctionalUnit;

    if (!fu.canPerformOverviewScan) {
        [scanner requestCloseSession];
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorCapabilityMissing
            userInfo:@{NSLocalizedDescriptionKey:
                @"Selected functional unit cannot perform an overview scan "
                "(document feeders do not support overview scans). Use scanner/scan instead."}];
        return NO;
    }

    if (self.scanDPI > 0) {
        fu.overviewResolution = (unsigned int)ICCSnapDPI(self.scanDPI, fu.supportedResolutions);
    }

    [scanner requestOverviewScan];

    if (!ICCSpinUntilCondition(^{ return helper.overviewDone; }, 60.0)) {
        [scanner requestCloseSession];
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorSessionTimeout
            userInfo:@{NSLocalizedDescriptionKey: @"Timed out waiting for overview scan to complete."}];
        return NO;
    }

    if (helper.overviewError) {
        [scanner requestCloseSession];
        if (error) *error = helper.overviewError;
        return NO;
    }

    // Save overviewImage (CGImageRef) as PNG using ImageIO
    NSString *writtenPath = nil;
    CGImageRef overviewImage = fu.overviewImage;
    if (overviewImage && self.outputPath.length) {
        writtenPath = self.outputPath;
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:writtenPath isDirectory:&isDir];
        if (isDir) {
            writtenPath = [writtenPath stringByAppendingPathComponent:@"preview.png"];
        }
        NSURL *outURL = [NSURL fileURLWithPath:writtenPath];
        CGImageDestinationRef dest = CGImageDestinationCreateWithURL(
            (__bridge CFURLRef)outURL, kUTTypePNG, 1, NULL);
        if (dest) {
            CGImageDestinationAddImage(dest, overviewImage, NULL);
            BOOL ok = CGImageDestinationFinalize(dest);
            CFRelease(dest);
            if (!ok) writtenPath = nil;
        } else {
            writtenPath = nil;
        }
    }

    [scanner requestCloseSession];

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (scanner.name) result[@"device_name"]      = scanner.name;
    if (fu) {
        result[@"overview_resolution_dpi"] = @(fu.overviewResolution);
    }
    if (writtenPath) result[@"preview_path"]       = writtenPath;
    if (self.debug && start) {
        result[@"processing_ms"] =
            @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    NSDictionary *envelope = MVMakeEnvelope(@"imagetransfer", self.operation, nil, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

// ── scanner/scan ──────────────────────────────────────────────────────────────

- (BOOL)runScannerScanWithError:(NSError **)error {
    NSDate *start = self.debug ? [NSDate date] : nil;

    ICScannerDevice *scanner  = nil;
    ICCScannerHelper *helper  = nil;
    if (![self prepareScannerSession:&scanner helper:&helper error:error]) return NO;

    // Determine output directory
    NSString *outputDir = self.outputPath;
    if (!outputDir.length) {
        outputDir = NSTemporaryDirectory();
    } else {
        BOOL isDir = NO;
        [[NSFileManager defaultManager] fileExistsAtPath:outputDir isDirectory:&isDir];
        if (!isDir) {
            NSError *mkErr = nil;
            if (![[NSFileManager defaultManager] createDirectoryAtPath:outputDir
                                          withIntermediateDirectories:YES attributes:nil error:&mkErr]) {
                [scanner requestCloseSession];
                if (error) *error = mkErr;
                return NO;
            }
        }
    }

    // Map --format to document UTI
    NSString *fmt = (self.outputFormat ?: @"tiff").lowercaseString;
    NSString *docUTI;
    if ([fmt isEqualToString:@"jpeg"] || [fmt isEqualToString:@"jpg"]) {
        docUTI = @"public.jpeg";
    } else if ([fmt isEqualToString:@"png"]) {
        docUTI = @"public.png";
    } else {
        docUTI = @"public.tiff";
    }

    // Configure functional unit
    ICScannerFunctionalUnit *fu = scanner.selectedFunctionalUnit;
    if (self.scanDPI > 0) {
        fu.resolution = (unsigned int)ICCSnapDPI(self.scanDPI, fu.supportedResolutions);
    } else {
        NSUInteger preferred = [fu.preferredResolutions firstIndex];
        if (preferred != NSNotFound) fu.resolution = (unsigned int)preferred;
    }
    fu.pixelDataType = ICScannerPixelDataTypeRGB;
    fu.bitDepth      = ICScannerBitDepth8Bits;

    // Generate a unique document name from current timestamp
    NSString *rawName = [NSString stringWithFormat:@"scan_%@",
                         [ICCISOFormatter() stringFromDate:[NSDate date]]];
    NSString *docName = [rawName stringByReplacingOccurrencesOfString:@":" withString:@"-"];

    scanner.transferMode       = ICScannerTransferModeFileBased;
    scanner.downloadsDirectory = [NSURL fileURLWithPath:outputDir isDirectory:YES];
    scanner.documentName       = docName;
    scanner.documentUTI        = docUTI;

    [scanner requestScan];

    if (!ICCSpinUntilCondition(^{ return helper.scanDone; }, 120.0)) {
        [scanner requestCloseSession];
        if (error) *error = [NSError errorWithDomain:ICCErrorDomain code:ICCErrorSessionTimeout
            userInfo:@{NSLocalizedDescriptionKey: @"Timed out waiting for scan to complete."}];
        return NO;
    }

    if (helper.scanError) {
        [scanner requestCloseSession];
        if (error) *error = helper.scanError;
        return NO;
    }

    [scanner requestCloseSession];

    NSMutableArray<NSString *> *pages = [NSMutableArray array];
    for (NSURL *url in helper.scannedURLs) {
        [pages addObject:url.path];
    }

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    if (scanner.name) result[@"device_name"]  = scanner.name;
    result[@"resolution_dpi"]                 = @(fu.resolution);
    result[@"format"]                         = docUTI;
    result[@"output_directory"]               = outputDir;
    result[@"page_count"]                     = @(pages.count);
    result[@"pages"]                          = pages;
    if (self.debug && start) {
        result[@"processing_ms"] =
            @((NSInteger)([[NSDate date] timeIntervalSinceDate:start] * 1000.0));
    }

    NSDictionary *envelope = MVMakeEnvelope(@"imagetransfer", self.operation, nil, result);
    return MVEmitEnvelope(envelope, self.jsonOutput, error);
}

@end
