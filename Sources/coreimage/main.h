#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface CIProcessor : NSObject

/// Image file path (required for apply when the filter uses inputImage).
@property (nonatomic, copy, nullable) NSString *inputPath;
/// JSON envelope output path, or stdout when omitted.
@property (nonatomic, copy, nullable) NSString *jsonOutput;
/// Directory for rendered PNG output (apply). Ignored for list-* operations.
@property (nonatomic, copy, nullable) NSString *artifactsDir;
/// Exact output file path for the rendered PNG (apply). Takes precedence over artifactsDir.
@property (nonatomic, copy, nullable) NSString *outputPath;
/// Operation: apply-filter | list-filters
@property (nonatomic, copy) NSString *operation;
/// CIFilter class name, e.g. "CISepiaTone" (required for apply-filter).
@property (nonatomic, copy, nullable) NSString *filterName;
/// JSON object string of scalar NSNumber filter params, e.g. {"inputIntensity":0.8} (optional for apply-filter).
@property (nonatomic, copy, nullable) NSString *filterParamsJSON;
/// Output image format for apply-filter and suggest-filters --apply: png (default), jpg, heif, tiff.
@property (nonatomic, copy) NSString *outputFormat;
/// When YES and operation is suggest-filters, also render and write the adjusted image.
@property (nonatomic, assign) BOOL applyFilters;
/// When YES and operation is list-filters, return category metadata instead of filter names.
@property (nonatomic, assign) BOOL categoryOnly;
@property (nonatomic, assign) BOOL debug;

- (BOOL)runWithError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
