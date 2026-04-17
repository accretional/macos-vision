#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *video;
@property (nonatomic, copy, nullable) NSString *img;
@property (nonatomic, copy) NSString *operation;
@property (nonatomic, copy, nullable) NSString *output;
@property (nonatomic, copy, nullable) NSString *artifactsDir;
@property (nonatomic, copy, nullable) NSString *preset;
@property (nonatomic, copy, nullable) NSString *timeStr;
@property (nonatomic, copy, nullable) NSString *timesStr;
@property (nonatomic, copy, nullable) NSString *timeRangeStr;
@property (nonatomic, copy, nullable) NSString *metaKey;
@property (nonatomic, copy, nullable) NSString *videosStr;   // comma-sep paths for compose
@property (nonatomic, copy, nullable) NSString *text;        // inline text for tts
@property (nonatomic, copy, nullable) NSString *voice;       // voice identifier for tts
@property (nonatomic, copy, nullable) NSString *inputFile;   // --input file for tts
@property (nonatomic, assign) NSInteger pitchHopFrames;      // --pitch-hop for pitch operation
@property (nonatomic, assign) BOOL debug;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
