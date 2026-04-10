#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Operations: screenshot | camera | mic | list-devices
@interface CaptureProcessor : NSObject

@property (nonatomic, copy) NSString *operation;           // screenshot | camera | mic | list-devices
@property (nonatomic, copy, nullable) NSString *output;    // output path for captured media file
@property (nonatomic, copy, nullable) NSString *outputDir; // output directory for media + JSON
@property (nonatomic, assign) NSInteger displayIndex;      // for screenshot (default 0)
@property (nonatomic, assign) BOOL debug;                  // emit processing_ms

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
