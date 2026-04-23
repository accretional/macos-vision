#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ICCProcessor : NSObject

/// Operation: list-devices (default) | camera/files | camera/thumbnail | camera/metadata |
///            camera/import | camera/delete | camera/capture | camera/sync-clock |
///            scanner/preview | scanner/scan
/// Aliases: list-files → camera/files
@property (nonatomic, copy) NSString *operation;
/// JSON envelope output path, or stdout when omitted.
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// Binary/media output path (thumbnail file, scan/import directory). Nil = stdout/default.
@property (nonatomic, copy, nullable) NSString *outputPath;
/// Which device to use when multiple are found (0-based, default 0).
@property (nonatomic, assign) NSInteger deviceIndex;
/// File index within the camera's mediaFiles list (0-based, default 0).
@property (nonatomic, assign) NSInteger fileIndex;
/// When YES, operate on all files rather than a single --file-index.
@property (nonatomic, assign) BOOL allFiles;
/// Delete from device after successful import (camera/import only).
@property (nonatomic, assign) BOOL deleteAfter;
/// Also download sidecar files (camera/import only).
@property (nonatomic, assign) BOOL downloadSidecars;
/// Max thumbnail dimension in pixels (0 = device default).
@property (nonatomic, assign) NSInteger thumbSize;
/// Seconds to run ICDeviceBrowser before collecting results (default 2.0).
@property (nonatomic, assign) NSTimeInterval browseTimeout;
/// Seconds to wait for the camera's content catalog to complete (default 15.0).
@property (nonatomic, assign) NSTimeInterval catalogTimeout;
/// Scan resolution in DPI (0 = use scanner's preferred resolution).
@property (nonatomic, assign) NSUInteger scanDPI;
/// Output format for scanner/scan: "tiff" (default), "jpeg", "png".
@property (nonatomic, copy, nullable) NSString *outputFormat;
@property (nonatomic, assign) BOOL debug;
/// When YES and stdout is piped, write device images as MJPEG frames to stdout instead of files.
/// Supported for camera/thumbnail, scanner/preview, scanner/scan.
@property (nonatomic, assign) BOOL streamOut;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchImageTransfer(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
