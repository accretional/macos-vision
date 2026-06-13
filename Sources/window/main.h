#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Inspect and reposition windows via the Accessibility API (AXUIElement) and
/// query display geometry via NSScreen.
///
/// Operations: list-displays | info | move | move-to-display
///
/// move / move-to-display act on the focused window of the frontmost
/// application and require Accessibility permission (System Settings ▸
/// Privacy & Security ▸ Accessibility).
@interface WindowProcessor : NSObject

/// list-displays | info | move | move-to-display
@property (nonatomic, copy) NSString *operation;

/// Target for move-to-display: a 0-based display index, or one of
/// next | prev | left | right.
@property (nonatomic, copy, nullable) NSString *displayTarget;

/// Absolute window frame for `move`, in global display pixels (top-left origin).
/// NaN leaves that component unchanged.
@property (nonatomic, assign) double x;
@property (nonatomic, assign) double y;
@property (nonatomic, assign) double w;
@property (nonatomic, assign) double h;

/// JSON envelope output path, or stdout when omitted.
@property (nonatomic, copy, nullable) NSString *jsonOutput;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchWindow(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
