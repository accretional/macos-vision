#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface OCRProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *img;
@property (nonatomic, copy, nullable) NSString *output;
@property (nonatomic, copy, nullable) NSString *imgDir;
@property (nonatomic, copy, nullable) NSString *outputDir;
@property (nonatomic, assign) BOOL debug;
@property (nonatomic, assign) BOOL lang;
@property (nonatomic, assign) BOOL merge;
@property (nonatomic, copy, nullable) NSString *recLangs;
@property (nonatomic, copy) NSString *boxesFormat; // png | jpg | tiff | bmp | gif  (default: png)

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
