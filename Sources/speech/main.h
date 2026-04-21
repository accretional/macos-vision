#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SpeechProcessor : NSObject

/// Audio file path (required for transcribe and voice-analytics).
@property (nonatomic, copy, nullable) NSString *inputPath;
/// JSON envelope output path, or stdout when omitted.
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// Operation: transcribe | voice-analytics | list-locales
@property (nonatomic, copy) NSString *operation;
@property (nonatomic, copy) NSString *lang;
@property (nonatomic, assign) BOOL offline;
@property (nonatomic, assign) BOOL debug;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchSpeech(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
