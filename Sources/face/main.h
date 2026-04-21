#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FaceProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *inputPath;
@property (nonatomic, copy, nullable) NSString *jsonOutput;
@property (nonatomic, copy, nullable) NSString *artifactsDir;
@property (nonatomic, assign) BOOL debug;
@property (nonatomic, copy) NSString *boxesFormat;
// face-rectangles (default) | face-landmarks | face-quality |
// human-rectangles | body-pose | hand-pose | animal-pose
@property (nonatomic, copy) NSString *operation;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchFace(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
