#import "nl/main.h"

static BOOL isDir(NSString *p) {
    if (!p.length) return NO;
    BOOL d = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:p isDirectory:&d] && d;
}
static NSString *stem(NSString *p) {
    NSString *s = p.lastPathComponent.stringByDeletingPathExtension;
    return s.length ? s : @"result";
}

static void printHelp(void) {
    printf(
        "USAGE: macos-vision nl --operation <op> [options]\n"
        "\n"
        "Analyse text — detect language, tag parts of speech, embed words, and classify content.\n"
        "\n"
        "OPERATIONS:\n"
        "  detect-language    (default) Identify the language of text\n"
        "  tokenize           Split text into tokens (words, sentences, paragraphs)\n"
        "  tag                Part-of-speech, named entity, lemma, or custom scheme tagging\n"
        "  embed              Compute a word or sentence embedding vector\n"
        "  distance           Semantic distance between two words\n"
        "  contextual-embed   Contextual word embedding (requires macOS 14+)\n"
        "  classify           Text classification with a CoreML model\n"
        "\n"
        "OPTIONS:\n"
        "  --text <string>         Inline text to analyse\n"
        "  --input <path>          Text file to analyse\n"
        "  --operation <op>        Operation to run (default: detect-language)\n"
        "  --output <path>         Directory or .json file for JSON output\n"
        "  --json-output <path>    Write JSON envelope to this file (default: stdout)\n"
        "  --language <lang>       BCP-47 language tag (e.g. en, fr-FR)\n"
        "  --scheme <scheme>       Tagging scheme for tag operation\n"
        "  --unit <unit>           Tokenizer unit: word (default), sentence, paragraph\n"
        "  --word <word>           Word for embed / nn-words operations\n"
        "  --word-a <word>         First word for distance operation\n"
        "  --word-b <word>         Second word for distance operation\n"
        "  --similar <word>        Find words nearest to this word (embed operation)\n"
        "  --model <path>          CoreML model path for classify\n"
        "  --topk <n>              Top-K results (default: 3)\n"
        "  --debug                 Emit processing_ms in output\n"
    );
}

BOOL MVDispatchNL(NSArray<NSString *> *args, NSError **error) {
    NSString *text         = nil;
    NSString *inputPath    = nil;
    NSString *operation    = @"detect-language";
    NSString *output       = nil;
    NSString *jsonOutput   = nil;
    NSString *language     = nil;
    NSString *scheme       = nil;
    NSString *unit         = nil;
    NSString *word         = nil;
    NSString *wordA        = nil;
    NSString *wordB        = nil;
    NSString *similar      = nil;
    NSString *modelPath    = nil;
    NSInteger topk         = 3;
    BOOL debug = NO;

    for (NSInteger i = 2; i < (NSInteger)args.count; i++) {
        NSString *a = args[i];
        if ([a isEqualToString:@"--help"] || [a isEqualToString:@"-h"]) {
            printHelp(); return YES;
        } else if ([a isEqualToString:@"--text"] && i+1 < (NSInteger)args.count)           { text      = args[++i]; }
        else if ([a isEqualToString:@"--input"] && i+1 < (NSInteger)args.count)            { inputPath = args[++i]; }
        else if ([a isEqualToString:@"--operation"] && i+1 < (NSInteger)args.count)        { operation = args[++i]; }
        else if ([a isEqualToString:@"--output"] && i+1 < (NSInteger)args.count)           { output    = args[++i]; }
        else if ([a isEqualToString:@"--json-output"] && i+1 < (NSInteger)args.count)      { jsonOutput= args[++i]; }
        else if ([a isEqualToString:@"--language"] && i+1 < (NSInteger)args.count)         { language  = args[++i]; }
        else if ([a isEqualToString:@"--scheme"] && i+1 < (NSInteger)args.count)           { scheme    = args[++i]; }
        else if ([a isEqualToString:@"--unit"] && i+1 < (NSInteger)args.count)             { unit      = args[++i]; }
        else if ([a isEqualToString:@"--word"] && i+1 < (NSInteger)args.count)             { word      = args[++i]; }
        else if ([a isEqualToString:@"--word-a"] && i+1 < (NSInteger)args.count)           { wordA     = args[++i]; }
        else if ([a isEqualToString:@"--word-b"] && i+1 < (NSInteger)args.count)           { wordB     = args[++i]; }
        else if ([a isEqualToString:@"--similar"] && i+1 < (NSInteger)args.count)          { similar   = args[++i]; }
        else if ([a isEqualToString:@"--model"] && i+1 < (NSInteger)args.count)            { modelPath = args[++i]; }
        else if ([a isEqualToString:@"--topk"] && i+1 < (NSInteger)args.count)             { topk      = [args[++i] integerValue]; }
        else if ([a isEqualToString:@"--debug"]) { debug = YES; }
        else {
            fprintf(stderr, "nl: unknown option '%s'\n", a.UTF8String);
            printHelp();
            if (error) *error = [NSError errorWithDomain:@"MVDispatch" code:1
                userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat:@"nl: unknown option '%@'", a]}];
            return NO;
        }
    }

    // JSON: <stem>.json naming (stem from input file, or "nl" if inline text)
    NSString *jsonStem = inputPath.length ? stem(inputPath) : @"nl";
    NSString *resolvedJSON = nil;
    if (jsonOutput.length && !isDir(jsonOutput))        resolvedJSON = jsonOutput;
    else if (jsonOutput.length && isDir(jsonOutput))    resolvedJSON = [[jsonOutput stringByAppendingPathComponent:jsonStem] stringByAppendingPathExtension:@"json"];
    else if (output.length && isDir(output))            resolvedJSON = [[output stringByAppendingPathComponent:jsonStem] stringByAppendingPathExtension:@"json"];
    else if ([output.pathExtension.lowercaseString isEqualToString:@"json"]) resolvedJSON = output;

    NLProcessor *p = [[NLProcessor alloc] init];
    p.text       = text;
    p.input      = inputPath;
    p.operation  = operation;
    p.language   = language;
    p.scheme     = scheme;
    p.unit       = unit;
    p.topk       = topk;
    p.word       = word;
    p.wordA      = wordA;
    p.wordB      = wordB;
    p.similar    = similar;
    p.modelPath  = modelPath;
    p.jsonOutput = resolvedJSON;
    p.debug      = debug;
    return [p runWithError:error];
}
