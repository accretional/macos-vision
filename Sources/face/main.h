#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface FaceProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *img;
@property (nonatomic, copy, nullable) NSString *output;
@property (nonatomic, copy, nullable) NSString *imgDir;
@property (nonatomic, copy, nullable) NSString *outputDir;
@property (nonatomic, assign) BOOL debug;
@property (nonatomic, copy) NSString *boxesFormat; // png | jpg | tiff | bmp | gif  (default: png)
// face-rectangles (default) | face-landmarks | face-quality |
// human-rectangles | body-pose | hand-pose | animal-pose
@property (nonatomic, copy) NSString *operation;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
