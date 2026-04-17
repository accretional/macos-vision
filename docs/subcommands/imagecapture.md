# ImageCaptureCore — API surface

SDK headers: `/Library/Developer/CommandLineTools/SDKs/MacOSX.sdk/System/Library/Frameworks/ImageCaptureCore.framework/Headers/`  
Framework: `ImageCaptureCore` (linked in `Package.swift`)  
Availability: macOS 10.15+

> **Architecture note:** Every delegate callback in ImageCaptureCore fires on the **main thread**. In a CLI process with no NSApplication, the main run loop must be spun manually with `[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:...]`. `dispatch_semaphore_wait` alone deadlocks. Block-based APIs (`requestDownloadWithOptions:`, `requestThumbnailDataWithOptions:`, `requestMetadataDictionaryWithOptions:`, `requestDeleteFiles:deleteFailed:completion:`) fire their completions on a non-main thread, so a semaphore is safe inside those blocks.

---

## Operations implemented

| Operation | Functionality | Flags | API used |
|-----------|--------------|-------|----------|
| `list-devices` | Discover all cameras and scanners on all transports | *(none)* | `ICDeviceBrowser` + `ICDeviceBrowserDelegate` |
| `camera/files` | List every file on a camera with full pre-download metadata | `--device-index` | `ICCameraDevice.mediaFiles` + `deviceDidBecomeReadyWithCompleteContentCatalog:` |
| `camera/thumbnail` | Fetch JPEG thumbnail for one file without downloading it | `--device-index`, `--file-index`, `--output`, `--thumb-size` | `ICCameraFile.requestThumbnailDataWithOptions:completion:` |
| `camera/metadata` | Fetch full EXIF/IPTC/GPS dictionary for one file without downloading | `--device-index`, `--file-index` | `ICCameraFile.requestMetadataDictionaryWithOptions:completion:` |
| `camera/import` | Download one or all files to a local directory | `--device-index`, `--file-index` / `--all`, `--output`, `--delete-after`, `--sidecars` | `ICCameraFile.requestDownloadWithOptions:completion:` |
| `camera/delete` | Delete one or all files from the device | `--device-index`, `--file-index` / `--all` | `ICCameraDevice.requestDeleteFiles:deleteFailed:completion:` |
| `camera/capture` | Fire the shutter remotely; report new file metadata when it appears | `--device-index` | `ICCameraDevice.requestTakePicture` + `cameraDevice:didAddItems:` |
| `camera/sync-clock` | Set the camera's clock to the Mac's clock; report drift before and after | `--device-index` | `ICCameraDevice.requestSyncClock` + `timeOffset` |
| `scanner/preview` | Low-res preview scan; saves result as PNG | `--device-index`, `--output`, `--dpi` | `ICScannerDevice.requestOverviewScan` + `selectedFunctionalUnit.overviewImage` |
| `scanner/scan` | Full-resolution scan; scanner writes file to output directory | `--device-index`, `--output`, `--dpi`, `--format` | `ICScannerDevice.requestScan` + `scannerDevice:didScanToURL:` |

Alias: `list-files` → `camera/files` (kept for backwards compatibility).

---

## Key classes

| Class | Purpose | Header |
|-------|---------|--------|
| `ICDeviceBrowser` | Discovers cameras and scanners on USB, FireWire, Bluetooth, and TCP/IP (Bonjour); set `browsedDeviceTypeMask` then call `start` | `ICDeviceBrowser.h` |
| `ICDevice` | Abstract base for all devices; session lifecycle (`requestOpenSession` / `requestCloseSession`), identity (`name`, `UUIDString`), and `capabilities` array | `ICDevice.h` |
| `ICCameraDevice` | Camera: `mediaFiles` (nil until catalog completes), `timeOffset`, battery, and capability flags for delete/tether/clock-sync | `ICCameraDevice.h` |
| `ICCameraItem` | Abstract base for folders and files on a camera | `ICCameraItem.h` |
| `ICCameraFile` | Per-file metadata before download: `name`, `UTI`, `fileSize`, `width`, `height`, timestamps, GPS, burst/group UUIDs, `addedAfterContentCatalogCompleted` | `ICCameraFile.h` |
| `ICCameraFolder` | Folder node mirroring the camera's on-device storage hierarchy; `.contents` gives children | `ICCameraFolder.h` |
| `ICScannerDevice` | Scanner: configure `transferMode`, `downloadsDirectory`, `documentName`, `documentUTI` then call `requestOverviewScan` or `requestScan` | `ICScannerDevice.h` |
| `ICScannerFunctionalUnit` | Flatbed/ADF/transparency unit; configure `resolution` (snap to `supportedResolutions`), `pixelDataType`, `bitDepth`; `overviewImage` holds the CGImageRef after a preview scan | `ICScannerFunctionalUnits.h` |
| `ICScannerBandData` | Memory-based band-by-band scan data for streaming transfers | `ICScannerBandData.h` |
