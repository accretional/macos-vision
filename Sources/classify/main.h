#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ClassifyProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *img;
@property (nonatomic, copy, nullable) NSString *output;
@property (nonatomic, copy, nullable) NSString *imgDir;
@property (nonatomic, copy, nullable) NSString *outputDir;
@property (nonatomic, assign) BOOL debug;
@property (nonatomic, assign) BOOL svg;         // also produce an SVG overlay alongside each JSON
@property (nonatomic, assign) BOOL svgLabels;   // show labels in SVG (default YES)
@property (nonatomic, copy) NSString *boxesFormat; // png | jpg | tiff | bmp | gif  (default: png)
// classify (default) | animals | rectangles | horizon | contours | aesthetics | feature-print
@property (nonatomic, copy) NSString *operation;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
