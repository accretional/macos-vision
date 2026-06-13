#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Synthesise HID input events (mouse + keyboard) via CoreGraphics CGEvent.
///
/// Operations: mouse-move | click | mouse-down | mouse-up | scroll | key
///
/// Posting synthetic events requires the host process to be trusted for
/// Accessibility (System Settings ▸ Privacy & Security ▸ Accessibility).
@interface InputProcessor : NSObject

/// mouse-move | click | mouse-down | mouse-up | scroll | key
@property (nonatomic, copy) NSString *operation;

/// Absolute cursor target in global display pixels (top-left origin).
/// NaN means "use the current cursor location".
@property (nonatomic, assign) double x;
@property (nonatomic, assign) double y;

/// Scroll deltas in wheel units (scroll). Positive dy scrolls content up.
@property (nonatomic, assign) double dx;
@property (nonatomic, assign) double dy;

/// Mouse button: left (default) | right | center.
@property (nonatomic, copy) NSString *button;

/// Click count for `click` (1 = single, 2 = double). Default 1.
@property (nonatomic, assign) NSInteger count;

/// When set on mouse-move, emit a drag of this button instead of a plain move.
@property (nonatomic, copy, nullable) NSString *dragButton;

/// Key name for `key` (e.g. "left", "a", "return", "f11").
@property (nonatomic, copy, nullable) NSString *key;

/// Comma-separated modifier names for `key`: cmd, ctrl, alt/option, shift, fn.
@property (nonatomic, copy, nullable) NSString *modifiers;

/// JSON envelope output path, or stdout when omitted.
@property (nonatomic, copy, nullable) NSString *jsonOutput;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchInput(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
