#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface AVProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *video;
@property (nonatomic, copy, nullable) NSString *img;
@property (nonatomic, copy) NSString *operation;
@property (nonatomic, copy, nullable) NSString *mediaOutput;  // output media file path (encode, frames, tts, etc.)
@property (nonatomic, copy, nullable) NSString *jsonOutput;   // JSON envelope output path
@property (nonatomic, copy, nullable) NSString *artifactsDir;
@property (nonatomic, copy, nullable) NSString *preset;
@property (nonatomic, copy, nullable) NSString *timeStr;
@property (nonatomic, copy, nullable) NSString *timesStr;
@property (nonatomic, copy, nullable) NSString *timeRangeStr;
@property (nonatomic, copy, nullable) NSString *metaKey;
@property (nonatomic, copy, nullable) NSString *videosStr;    // comma-sep paths for concat
@property (nonatomic, copy, nullable) NSString *inputsStr;    // comma-sep paths for mix
@property (nonatomic, copy, nullable) NSString *text;         // inline text for tts / burn
@property (nonatomic, copy, nullable) NSString *voice;        // voice identifier for tts
@property (nonatomic, copy, nullable) NSString *inputFile;    // --input file for tts / fetch URL
@property (nonatomic, copy, nullable) NSString *overlayPath;  // image path for burn
@property (nonatomic, assign) NSInteger pitchHopFrames;       // --pitch-hop for pitch operation
@property (nonatomic, assign) BOOL audioOnly;                 // --audio-only for encode
@property (nonatomic, assign) double factor;                  // --factor for retime
@property (nonatomic, assign) BOOL debug;
/// When YES, write frames as MJPEG stream to stdout (frames F→S).
@property (nonatomic, assign) BOOL streamOut;
/// When YES, read MJPEG stream from stdin and encode to output file (encode S→F).
@property (nonatomic, assign) BOOL stream;
/// FPS for encode S→F (default 30).
@property (nonatomic, assign) NSInteger fps;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchAV(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
