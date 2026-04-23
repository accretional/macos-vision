#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface NLProcessor : NSObject

@property (nonatomic, copy, nullable) NSString *text;
@property (nonatomic, copy, nullable) NSString *input;
@property (nonatomic, copy) NSString *operation;
@property (nonatomic, copy, nullable) NSString *language;
@property (nonatomic, copy, nullable) NSString *scheme;
@property (nonatomic, copy, nullable) NSString *unit;
@property (nonatomic, assign) NSInteger topk;
@property (nonatomic, copy, nullable) NSString *word;
@property (nonatomic, copy, nullable) NSString *wordA;
@property (nonatomic, copy, nullable) NSString *wordB;
@property (nonatomic, copy, nullable) NSString *similar;
@property (nonatomic, copy, nullable) NSString *modelPath;
@property (nonatomic, copy, nullable) NSString *jsonOutput;
@property (nonatomic, assign) BOOL debug;
@property (nonatomic, assign) BOOL stream;
@property (nonatomic, assign) BOOL streamOut;
@property (nonatomic, copy, nullable) NSString *ndjsonOutput;

- (BOOL)runWithError:(NSError **)error;

@end

BOOL MVDispatchNL(NSArray<NSString *> *args, NSError **error);

NS_ASSUME_NONNULL_END
