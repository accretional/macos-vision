# Onboarding Log - ImageCaptureCor

## Implementation Log — `imagecapture` Subcommand

**Date:** 2026-04-17 (initial); updated 2026-04-17 (all 10 operations)  
**Files created:**
- `Sources/imagecapture/main.h` — ICCProcessor interface (updated: 8 new properties)
- `Sources/imagecapture/main.m` — ICCProcessor implementation (all 10 operations)
- `Sources/imagecapture/test.sh` — smoke tests (23/23 pass)
- `cmd/example/subcommand_imagecapture.sh` — usage examples (all operations)

**Files modified:**
- `Package.swift` — added `ImageCaptureCore` linker framework
- `Sources/main.m` — added `#import`, dispatch block, `--device-index` arg, default op, usage string

### Operations Implemented

| Operation | Default? | What it does |
|---|---|---|
| `list-devices` | YES | `ICDeviceBrowser` → cameras + scanners with UUID, transport, product kind, battery, USB IDs |
| `list-files` | — | Opens session on camera device[N], waits for `deviceDidBecomeReadyWithCompleteContentCatalog:`, enumerates `mediaFiles` with per-file metadata |

### Key Technical Findings

1. **ICDeviceBrowser is fully async / main-thread delegate.** All `ICDeviceBrowserDelegate` and `ICCameraDeviceDelegate` callbacks fire on the main thread. Since our `main()` function has no NSApplication run loop, we spin it manually: `[[NSRunLoop currentRunLoop] runMode:NSDefaultRunLoopMode beforeDate:[NSDate dateWithTimeIntervalSinceNow:0.05]]`. A `dispatch_semaphore_wait` alone is **not sufficient** — it blocks the main thread and the delegate callbacks never fire.

2. **ICCameraDeviceDelegate has 10 required methods** (inheriting from ICDeviceDelegate). All must be implemented even if they're no-ops, otherwise the protocol conformance check at link time emits warnings and some delegate messages may be silently dropped.

3. **`deviceBrowserDidEnumerateLocalDevices:` only fires for local USB/FireWire devices.** If no local devices are present the delegate method is never called, so the browse timer must run to full timeout to also catch network/Bonjour devices. We set `localEnumDone = YES` in this optional method as an early-exit hint, but always fall back to the timeout.

4. **`ICCameraDevice.mediaFiles` is nil until the content catalog completes.** Accessing `mediaFiles` before `deviceDidBecomeReadyWithCompleteContentCatalog:` returns nil or an incomplete array. We spin the run loop up to 10 s for catalog completion; the flag is flipped in the delegate and polled via a block-based condition.

5. **`browsedDeviceTypeMask` is macOS 10.4+** — no availability guard needed for our deployment target of 10.15.

6. **ObjC instance variable visibility.** Synthesized ivars (`_flagName`) generated from `@property` declarations are `@private` in Objective-C. A C helper function trying to access them with `->` fails to compile. Solution: use an ObjC block that reads the public property, passed to a `ICCSpinUntilCondition(BOOL (^condition)(void), NSTimeInterval)` spinner.

7. **`NSDate -isEarlierThan:` does not exist.** The correct idiom is `[[NSDate date] compare:deadline] == NSOrderedAscending` or `[deadline timeIntervalSinceNow] > 0`.

8. **`import` / `tether` / `scan` not yet implemented.** These require either a physically connected device to test against or a mock; deferred to a follow-up. Their async patterns (download progress delegate + NSProgress, `requestTakePicture` + `cameraDevice:didAddItems:`) are more complex than `list-files` and need dedicated handling.

### Gaps Found in `docs/new-subcommand-instructions.md`

1. **No mention of async / run-loop requirement.** The instructions say "implement a thin wrapper" but do not flag that some Apple frameworks (ImageCaptureCore, HomeKit, CoreBluetooth) require a spinning run loop for their delegate callbacks. A note like *"if the framework's APIs are delegate/callback-based, you must spin the main run loop rather than use dispatch_semaphore_wait"* would prevent this footgun.

2. **Step 1 says "fetch the document webpage" but gives no instructions for offline/SDK inspection.** The Apple developer documentation for ImageCaptureCore is sparse and sometimes out of date vs. the SDK headers. Inspecting `$SDK/ImageCaptureCore.framework/Headers/` directly (especially `ICCameraDevice.h`, `ICCameraFile.h`, `ICCameraItem.h`) gave the most accurate and complete property lists. The instructions should mention SDK header inspection as the primary source of truth.

3. **Step 3 says "add files/data for testing" but gives no guidance for device-dependent APIs.** ImageCaptureCore (and similarly CoreBluetooth, HomeKit) cannot be tested without physical hardware. The instructions should acknowledge this case and suggest: (a) testing the no-device path explicitly, (b) documenting the expected output format in the subcommand doc, and (c) deferring device-dependent operations to a skip or conditional in test.sh.

4. **"Look at two other subcommands for implementation style"** — this is good advice, but the async ones (`speech`, `sna`) use `dispatch_semaphore_wait` which works because the recognizer callbacks don't run on the main thread. Recommending checking *which thread* a framework's callbacks land on before picking a synchronization primitive would prevent the main-thread-deadlock class of bugs.

### Key Tools Used

- `Read` — SDK headers (`ICDevice.h`, `ICCameraDevice.h`, `ICCameraFile.h`, `ICDeviceBrowser.h`, `ICCameraItem.h`)
- `Read` — existing subcommand implementations (`coreimage/main.m`, `speech/main.m`, `capture/main.m`) for patterns
- `Read` — `Package.swift`, `Sources/main.m` for integration points
- `Bash` — `swift build` iteratively to catch compile errors
- `Bash` — `bash Sources/imagecapture/test.sh` to validate outputs
- `Bash` — `bash cmd/example/subcommand_imagecapture.sh` to validate example script
