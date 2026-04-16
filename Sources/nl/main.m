#import "main.h"
#import "common/MVJsonEmit.h"
#import <NaturalLanguage/NaturalLanguage.h>

static NSString * const NLProcErrorDomain = @"NLProcError";

typedef NS_ENUM(NSInteger, NLProcessorErrorCode) {
    NLProcessorErrorMissingInput    = 1,
    NLProcessorErrorNoFiles         = 2,
    NLProcessorErrorUnknownOp       = 3,
    NLProcessorErrorUnknownScheme   = 4,
    NLProcessorErrorNoEmbedding     = 5,
    NLProcessorErrorWordNotFound    = 6,
    NLProcessorErrorNoSentenceEmbed = 7,
    NLProcessorErrorEmbedOSVersion  = 8,
    NLProcessorErrorMissingWords    = 9,
    NLProcessorErrorNoContextEmbed  = 10,
    NLProcessorErrorAssetUnavail    = 11,
    NLProcessorErrorContextOSVersion = 12,
    NLProcessorErrorMissingModel    = 13,
};

static void NLPrintJSON(id obj) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:nil];
    if (data) printf("%s\n", [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding].UTF8String);
}

static BOOL NLWriteJSON(id obj, NSURL *url, NSError **error) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:obj
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:error];
    if (!data) return NO;
    [[NSFileManager defaultManager] createDirectoryAtURL:url.URLByDeletingLastPathComponent
                             withIntermediateDirectories:YES attributes:nil error:nil];
    return [data writeToURL:url options:NSDataWritingAtomic error:error];
}

static NLLanguage NLLangOrNil(NSString *s) {
    if (!s.length) return nil;
    return (NLLanguage)s;
}

static NLTagScheme NLSchemeFromName(NSString *name) {
    NSString *n = name.lowercaseString;
    if ([n isEqualToString:@"pos"]) return NLTagSchemeLexicalClass;
    if ([n isEqualToString:@"ner"]) return NLTagSchemeNameType;
    if ([n isEqualToString:@"lemma"]) return NLTagSchemeLemma;
    if ([n isEqualToString:@"language"]) return NLTagSchemeLanguage;
    if ([n isEqualToString:@"script"]) return NLTagSchemeScript;
    return nil;
}

static NLTokenUnit NLUnitFromName(NSString *name) {
    NSString *n = name.lowercaseString;
    if ([n isEqualToString:@"sentence"]) return NLTokenUnitSentence;
    if ([n isEqualToString:@"paragraph"]) return NLTokenUnitParagraph;
    return NLTokenUnitWord;
}

@interface NLProcessor ()
- (nullable NSDictionary *)runDetectLanguageOnText:(NSString *)text error:(NSError **)error;
- (nullable NSDictionary *)runTokenizeOnText:(NSString *)text error:(NSError **)error;
- (nullable NSDictionary *)runTagOnText:(NSString *)text error:(NSError **)error;
- (nullable NSDictionary *)runEmbedOnText:(NSString *)text error:(NSError **)error;
- (nullable NSDictionary *)runDistanceWithError:(NSError **)error;
- (nullable NSDictionary *)runContextualEmbedOnText:(NSString *)text error:(NSError **)error;
- (nullable NSDictionary *)runClassifyOnText:(NSString *)text error:(NSError **)error;
@end

@implementation NLProcessor

- (instancetype)init {
    if (self = [super init]) {
        _operation = @"detect-language";
        _topk = 3;
    }
    return self;
}

- (nullable NSString *)loadTextFromURL:(NSURL *)url error:(NSError **)error {
    NSError *e = nil;
    NSString *s = [NSString stringWithContentsOfURL:url encoding:NSUTF8StringEncoding error:&e];
    if (!s && !e) s = [NSString stringWithContentsOfURL:url usedEncoding:NULL error:&e];
    if (!s) {
        if (error) *error = e;
        return nil;
    }
    return s;
}

- (NSArray<NSURL *> *)listTextFiles:(NSString *)dir error:(NSError **)error {
    NSURL *d = [NSURL fileURLWithPath:dir];
    NSArray<NSURL *> *urls = [[NSFileManager defaultManager] contentsOfDirectoryAtURL:d
                                                            includingPropertiesForKeys:nil
                                                                               options:NSDirectoryEnumerationSkipsHiddenFiles
                                                                                 error:error];
    if (!urls) return nil;
    NSMutableArray *out = [NSMutableArray array];
    for (NSURL *u in urls) {
        NSString *ext = u.pathExtension.lowercaseString;
        if ([ext isEqualToString:@"txt"] || [ext isEqualToString:@"md"] || [ext isEqualToString:@""]) {
            BOOL isDir = NO;
            if ([[NSFileManager defaultManager] fileExistsAtPath:u.path isDirectory:&isDir] && !isDir)
                [out addObject:u];
        }
    }
    [out sortUsingComparator:^NSComparisonResult(NSURL *a, NSURL *b) {
        return [a.lastPathComponent compare:b.lastPathComponent];
    }];
    return out;
}

/// Sets `outStr` from --text or --input file. Returns NO if neither provided.
- (BOOL)resolvePrimaryText:(NSError **)error intoString:(NSString **)outStr {
    if (self.text.length) {
        *outStr = self.text;
        return YES;
    }
    if (self.input.length) {
        NSURL *u = [NSURL fileURLWithPath:self.input];
        *outStr = [self loadTextFromURL:u error:error];
        return *outStr != nil;
    }
    if (error) {
        *error = [NSError errorWithDomain:NLProcErrorDomain code:2
                     userInfo:@{NSLocalizedDescriptionKey: @"Provide --text or --input <file>"}];
    }
    return NO;
}

// ── detect-language (NLLanguageRecognizer) ───────────────────────────────────

- (nullable NSDictionary *)runDetectLanguageOnText:(NSString *)text error:(NSError **)error {
    (void)error;
    NLLanguageRecognizer *rec = [[NLLanguageRecognizer alloc] init];
    if (self.language.length) {
        rec.languageHints = @{ (NLLanguage)self.language: @1.0 };
    }
    [rec processString:text];
    NSMutableDictionary *hyp = [NSMutableDictionary dictionary];
    NSDictionary *h = [rec languageHypothesesWithMaximum:(NSUInteger)MAX(1, self.topk)];
    for (NLLanguage k in h) hyp[k] = @([h[k] doubleValue]);
    return @{
        @"dominantLanguage": rec.dominantLanguage ?: [NSNull null],
        @"hypotheses": hyp,
    };
}

// ── tokenize (NLTokenizer) ─────────────────────────────────────────────────────

- (nullable NSDictionary *)runTokenizeOnText:(NSString *)text error:(NSError **)error {
    (void)error;
    NLTokenUnit u = NLUnitFromName(self.unit ?: @"word");
    NLTokenizer *tok = [[NLTokenizer alloc] initWithUnit:u];
    tok.string = text;
    if (self.language.length) [tok setLanguage:(NLLanguage)self.language];
    NSMutableArray *tokens = [NSMutableArray array];
    [tok enumerateTokensInRange:NSMakeRange(0, text.length)
                   usingBlock:^(NSRange tokenRange, NLTokenizerAttributes flags, BOOL *stop) {
        [tokens addObject:@{
            @"text": [text substringWithRange:tokenRange],
            @"location": @(tokenRange.location),
            @"length": @(tokenRange.length),
            @"flags": @(flags),
        }];
    }];
    return @{
        @"unit": self.unit ?: @"word",
        @"tokens": tokens,
    };
}

// ── tag (NLTagger) ─────────────────────────────────────────────────────────────

- (nullable NSDictionary *)runTagOnText:(NSString *)text error:(NSError **)error {
    NSString *schemeName = self.scheme ?: @"pos";
    NLTagScheme scheme = NLSchemeFromName(schemeName);
    if (!scheme) {
        if (error) *error = [NSError errorWithDomain:NLProcErrorDomain code:4
                             userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithFormat:@"Unknown scheme '%@' (use pos|ner|lemma|language|script)", schemeName]}];
        return nil;
    }
    NLTagger *tagger = [[NLTagger alloc] initWithTagSchemes:@[scheme]];
    tagger.string = text;
    if (self.language.length) [tagger setLanguage:(NLLanguage)self.language range:NSMakeRange(0, text.length)];
    if (self.modelPath.length) {
        NSURL *murl = [NSURL fileURLWithPath:self.modelPath];
        NLModel *m = [NLModel modelWithContentsOfURL:murl error:error];
        if (!m) return nil;
        [tagger setModels:@[m] forTagScheme:scheme];
    }
    NLTokenUnit u = NLUnitFromName(self.unit ?: @"word");
    NSMutableArray *tags = [NSMutableArray array];
    NLTaggerOptions opts = NLTaggerOmitWhitespace | NLTaggerOmitPunctuation;
    [tagger enumerateTagsInRange:NSMakeRange(0, text.length) unit:u scheme:scheme options:opts
                      usingBlock:^(NLTag _Nullable tag, NSRange tokenRange, BOOL *stop) {
        [tags addObject:@{
            @"tag": tag ?: [NSNull null],
            @"text": [text substringWithRange:tokenRange],
            @"location": @(tokenRange.location),
            @"length": @(tokenRange.length),
        }];
    }];
    return @{ @"scheme": schemeName, @"tags": tags };
}

// ── embed (NLEmbedding) ──────────────────────────────────────────────────────

- (nullable NSDictionary *)runEmbedOnText:(NSString *)text error:(NSError **)error {
    NLLanguage lang = NLLangOrNil(self.language) ?: @"en";
    if (self.similar.length) {
        NLEmbedding *emb = [NLEmbedding wordEmbeddingForLanguage:lang];
        if (!emb) {
            if (error) *error = [NSError errorWithDomain:NLProcErrorDomain code:NLProcessorErrorNoEmbedding
                                 userInfo:@{NSLocalizedDescriptionKey: @"No word embedding for language"}];
            return nil;
        }
        NSUInteger k = self.topk > 0 ? (NSUInteger)self.topk : 10;
        NSMutableArray *neighbors = [NSMutableArray array];
        [emb enumerateNeighborsForString:self.similar maximumCount:k distanceType:NLDistanceTypeCosine
                              usingBlock:^(NSString *neighbor, NLDistance distance, BOOL *stop) {
            [neighbors addObject:@{ @"word": neighbor, @"distance": @(distance) }];
        }];
        return @{ @"similarTo": self.similar, @"neighbors": neighbors };
    }
    if (self.word.length) {
        NLEmbedding *emb = [NLEmbedding wordEmbeddingForLanguage:lang];
        if (!emb) {
            if (error) *error = [NSError errorWithDomain:NLProcErrorDomain code:NLProcessorErrorNoEmbedding
                                 userInfo:@{NSLocalizedDescriptionKey: @"No word embedding for language"}];
            return nil;
        }
        // Tokenize so multi-word input (e.g. --word "cat dog") returns a vector per token
        NLTokenizer *tok = [[NLTokenizer alloc] initWithUnit:NLTokenUnitWord];
        tok.string = self.word;
        if (self.language.length) [tok setLanguage:(NLLanguage)self.language];
        NSMutableArray *tokens = [NSMutableArray array];
        [tok enumerateTokensInRange:NSMakeRange(0, self.word.length)
                         usingBlock:^(NSRange r, NLTokenizerAttributes flags, BOOL *stop) {
            [tokens addObject:[self.word substringWithRange:r]];
        }];
        if (tokens.count == 0) tokens = [@[self.word] mutableCopy];

        if (tokens.count == 1) {
            NSArray<NSNumber *> *vec = [emb vectorForString:tokens[0]];
            if (!vec) {
                if (error) *error = [NSError errorWithDomain:NLProcErrorDomain
                                                        code:NLProcessorErrorWordNotFound
                                                    userInfo:@{NSLocalizedDescriptionKey:
                                                                   [NSString stringWithFormat:@"'%@' not in vocabulary", tokens[0]]}];
                return nil;
            }
            return @{ @"word": tokens[0], @"vector": vec, @"dimension": @(emb.dimension) };
        }

        NSMutableArray *results = [NSMutableArray array];
        for (NSString *token in tokens) {
            NSArray<NSNumber *> *vec = [emb vectorForString:token];
            [results addObject:@{
                @"word":       token,
                @"vector":     vec ?: @[],
                @"inVocab":    @(vec != nil),
            }];
        }
        return @{ @"words": results, @"dimension": @(emb.dimension) };
    }
    if (@available(macOS 11.0, *)) {
        NLEmbedding *semb = [NLEmbedding sentenceEmbeddingForLanguage:lang];
        if (!semb) {
            if (error) *error = [NSError errorWithDomain:NLProcErrorDomain code:7
                                 userInfo:@{NSLocalizedDescriptionKey: @"No sentence embedding for language"}];
            return nil;
        }
        NSArray<NSNumber *> *vec = [semb vectorForString:text];
        return @{
            @"vector": vec ?: @[],
            @"dimension": @(semb.dimension),
            @"mode": @"sentence",
        };
    }
    if (error) *error = [NSError errorWithDomain:NLProcErrorDomain code:8
                         userInfo:@{NSLocalizedDescriptionKey: @"Sentence embeddings require macOS 11+"}];
    return nil;
}

// ── distance (NLEmbedding) ───────────────────────────────────────────────────

- (nullable NSDictionary *)runDistanceWithError:(NSError **)error {
    if (!self.wordA.length || !self.wordB.length) {
        if (error) *error = [NSError errorWithDomain:NLProcErrorDomain code:9
                             userInfo:@{NSLocalizedDescriptionKey: @"distance requires --word-a and --word-b"}];
        return nil;
    }
    NLLanguage lang = NLLangOrNil(self.language) ?: @"en";
    NLEmbedding *emb = [NLEmbedding wordEmbeddingForLanguage:lang];
    if (!emb) {
        if (error) *error = [NSError errorWithDomain:NLProcErrorDomain code:NLProcessorErrorNoEmbedding
                             userInfo:@{NSLocalizedDescriptionKey: @"No word embedding for language"}];
        return nil;
    }
    NLDistance d = [emb distanceBetweenString:self.wordA andString:self.wordB distanceType:NLDistanceTypeCosine];
    return @{ @"wordA": self.wordA, @"wordB": self.wordB, @"cosineDistance": @(d) };
}

// ── contextual-embed (NLContextualEmbedding) ───────────────────────────────────

- (nullable NSDictionary *)runContextualEmbedOnText:(NSString *)text error:(NSError **)error {
    if (@available(macOS 14.0, *)) {
        NLLanguage lang = NLLangOrNil(self.language) ?: @"en";
        NLContextualEmbedding *ce = [NLContextualEmbedding contextualEmbeddingWithLanguage:lang];
        if (!ce) {
            if (error) *error = [NSError errorWithDomain:NLProcErrorDomain code:10
                                 userInfo:@{NSLocalizedDescriptionKey: @"No contextual embedding for language"}];
            return nil;
        }
        if (!ce.hasAvailableAssets) {
            dispatch_semaphore_t sem = dispatch_semaphore_create(0);
            __block NSError *assetErr = nil;
            [ce requestEmbeddingAssetsWithCompletionHandler:^(NLContextualEmbeddingAssetsResult result, NSError * _Nullable err) {
                if (result != NLContextualEmbeddingAssetsResultAvailable) assetErr = err;
                dispatch_semaphore_signal(sem);
            }];
            dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 120 * NSEC_PER_SEC));
            if (!ce.hasAvailableAssets) {
                if (error) *error = assetErr ?: [NSError errorWithDomain:NLProcErrorDomain code:11
                                            userInfo:@{NSLocalizedDescriptionKey: @"Contextual embedding assets unavailable"}];
                return nil;
            }
        }
        NSError *le = nil;
        if (![ce loadWithError:&le]) {
            if (error) *error = le;
            return nil;
        }
        NLContextualEmbeddingResult *res = [ce embeddingResultForString:text language:lang error:error];
        [ce unload];
        if (!res) return nil;
        NSMutableArray *tokens = [NSMutableArray array];
        [res enumerateTokenVectorsInRange:NSMakeRange(0, text.length)
                                usingBlock:^(NSArray<NSNumber *> *tokenVector, NSRange tokenRange, BOOL *stop) {
            [tokens addObject:@{
                @"text": [text substringWithRange:tokenRange],
                @"location": @(tokenRange.location),
                @"length": @(tokenRange.length),
                @"vector": tokenVector,
            }];
        }];
        return @{
            @"modelIdentifier": ce.modelIdentifier,
            @"dimension": @(ce.dimension),
            @"sequenceLength": @(res.sequenceLength),
            @"identifiedLanguage": res.language,
            @"tokens": tokens,
        };
    }
    if (error) *error = [NSError errorWithDomain:NLProcErrorDomain code:12
                         userInfo:@{NSLocalizedDescriptionKey: @"contextual-embed requires macOS 14+"}];
    return nil;
}

// ── classify (NLModel) ─────────────────────────────────────────────────────────

- (nullable NSDictionary *)runClassifyOnText:(NSString *)text error:(NSError **)error {
    if (!self.modelPath.length) {
        if (error) *error = [NSError errorWithDomain:NLProcErrorDomain code:13
                             userInfo:@{NSLocalizedDescriptionKey: @"classify requires --model"}];
        return nil;
    }
    NSURL *murl = [NSURL fileURLWithPath:self.modelPath];
    NLModel *m = [NLModel modelWithContentsOfURL:murl error:error];
    if (!m) return nil;
    if (m.configuration.type == NLModelTypeClassifier) {
        NSUInteger k = self.topk > 0 ? (NSUInteger)self.topk : 1;
        NSMutableDictionary *out = [@{
            @"type": @"classifier",
            @"predictedLabel": [m predictedLabelForString:text] ?: [NSNull null],
        } mutableCopy];
        if (@available(macOS 11.0, *)) {
            NSDictionary *hyp = [m predictedLabelHypothesesForString:text maximumCount:k];
            NSMutableDictionary *hout = [NSMutableDictionary dictionary];
            for (NSString *lab in hyp) hout[lab] = hyp[lab];
            out[@"hypotheses"] = hout;
        }
        return out;
    }
    NLTokenizer *tok = [[NLTokenizer alloc] initWithUnit:NLTokenUnitWord];
    tok.string = text;
    NSMutableArray *words = [NSMutableArray array];
    [tok enumerateTokensInRange:NSMakeRange(0, text.length)
                     usingBlock:^(NSRange tokenRange, NLTokenizerAttributes flags, BOOL *stop) {
        [words addObject:[text substringWithRange:tokenRange]];
    }];
    NSArray *labels = [m predictedLabelsForTokens:words];
    NSMutableArray *pairs = [NSMutableArray array];
    for (NSUInteger i = 0; i < words.count && i < labels.count; i++) {
        [pairs addObject:@{ @"token": words[i], @"label": labels[i] ?: [NSNull null] }];
    }
    return @{ @"type": @"sequence", @"tokenLabels": pairs };
}

// ── dispatch ───────────────────────────────────────────────────────────────────

- (nullable NSDictionary *)runOperationOnText:(NSString *)text source:(nullable NSString *)sourcePath error:(NSError **)error {
    NSDate *t0 = self.debug ? [NSDate date] : nil;

    NSArray *valid = @[@"detect-language", @"tokenize", @"tag", @"embed", @"distance",
                       @"contextual-embed", @"classify"];
    if (![valid containsObject:self.operation]) {
        if (error) *error = [NSError errorWithDomain:NLProcErrorDomain code:3
                             userInfo:@{NSLocalizedDescriptionKey:
                                            [NSString stringWithFormat:@"Unknown operation '%@'", self.operation]}];
        return nil;
    }

    NSMutableDictionary *base = [NSMutableDictionary dictionary];
    base[@"operation"] = self.operation;
    if (sourcePath) base[@"path"] = MVRelativePath(sourcePath);

    NSDictionary *payload = nil;
    if ([self.operation isEqualToString:@"detect-language"]) {
        payload = [self runDetectLanguageOnText:text error:error];
    } else if ([self.operation isEqualToString:@"tokenize"]) {
        payload = [self runTokenizeOnText:text error:error];
    } else if ([self.operation isEqualToString:@"tag"]) {
        payload = [self runTagOnText:text error:error];
    } else if ([self.operation isEqualToString:@"embed"]) {
        payload = [self runEmbedOnText:text error:error];
    } else if ([self.operation isEqualToString:@"distance"]) {
        payload = [self runDistanceWithError:error];
    } else if ([self.operation isEqualToString:@"contextual-embed"]) {
        payload = [self runContextualEmbedOnText:text error:error];
    } else if ([self.operation isEqualToString:@"classify"]) {
        payload = [self runClassifyOnText:text error:error];
    }

    if (!payload) return nil;
    [base addEntriesFromDictionary:payload];

    if (t0) base[@"processing_ms"] = @((NSInteger)([[NSDate date] timeIntervalSinceDate:t0] * 1000.0));
    return base;
}

- (BOOL)runWithError:(NSError **)error {
    NSString *inputLabel = self.input ?: self.text ?: @"";

    if ([self.operation isEqualToString:@"distance"]) {
        NSDictionary *r = [self runDistanceWithError:error];
        if (!r) return NO;
        NSDictionary *env = MVMakeEnvelope(@"nl", self.operation, inputLabel, r);
        return MVEmitEnvelope(env, self.jsonOutput, error);
    }
    if ([self.operation isEqualToString:@"embed"] && (self.word.length || self.similar.length)) {
        NSDictionary *r = [self runEmbedOnText:@"" error:error];
        if (!r) return NO;
        NSDictionary *env = MVMakeEnvelope(@"nl", self.operation, inputLabel, r);
        return MVEmitEnvelope(env, self.jsonOutput, error);
    }

    NSString *singleText = nil;
    if (![self resolvePrimaryText:error intoString:&singleText]) return NO;

    NSDictionary *r = [self runOperationOnText:singleText source:self.input error:error];
    if (!r) return NO;
    NSDictionary *env = MVMakeEnvelope(@"nl", self.operation, inputLabel.length ? inputLabel : @"<inline>", r);
    return MVEmitEnvelope(env, self.jsonOutput, error);
}

@end
