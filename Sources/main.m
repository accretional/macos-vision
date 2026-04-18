#import <Foundation/Foundation.h>
#import "ocr/main.h"
#import "debug/main.h"
#import "segment/main.h"
#import "face/main.h"
#import "classify/main.h"
#import "track/main.h"
#import "overlay/main.h"  // OverlayProcessor
#import "shazam/main.h"
#import "capture/main.h"
#import "nl/main.h"
#import "av/main.h"
#import "speech/main.h"
#import "sna/main.h"
#import "coreimage/main.h"
#import "imagecapture/main.h"

static BOOL MVPathLooksLikeStillImage(NSString *path) {
    if (!path.length) return NO;
    NSString *e = path.pathExtension.lowercaseString;
    static NSSet<NSString *> *exts;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        exts = [NSSet setWithArray:@[@"jpg", @"jpeg", @"png", @"heic", @"heif", @"gif", @"tif", @"tiff", @"bmp", @"webp"]];
    });
    return [exts containsObject:e];
}

static BOOL MVPathIsExistingDirectory(NSString *path) {
    if (!path.length) return NO;
    BOOL isDir = NO;
    return [[NSFileManager defaultManager] fileExistsAtPath:path isDirectory:&isDir] && isDir;
}

static NSString *MVMainStem(NSString *path) {
    NSString *s = path.lastPathComponent.stringByDeletingPathExtension;
    return s.length ? s : @"result";
}

static NSString *MVMainEffectiveOperation(NSString *subcommand, NSString *operation) {
    if (operation.length) return operation;
    if ([subcommand isEqualToString:@"segment"]) return @"foreground-mask";
    if ([subcommand isEqualToString:@"face"]) return @"face-rectangles";
    if ([subcommand isEqualToString:@"classify"]) return @"classify";
    if ([subcommand isEqualToString:@"track"]) return @"homographic";
    if ([subcommand isEqualToString:@"shazam"]) return @"match";
    if ([subcommand isEqualToString:@"capture"]) return @"screenshot";
    if ([subcommand isEqualToString:@"av"]) return @"inspect";
    if ([subcommand isEqualToString:@"nl"]) return @"detect-language";
    if ([subcommand isEqualToString:@"speech"]) return @"transcribe";
    if ([subcommand isEqualToString:@"sna"]) return @"classify";
    if ([subcommand isEqualToString:@"coreimage"]) return @"apply-filter";
    if ([subcommand isEqualToString:@"imagecapture"]) return @"list-devices";
    return @"default";
}

static NSString *MVMainJsonInDirectory(NSString *dir, NSString *subcommand, NSString *operation, NSString *stemPath) {
    NSString *op = [operation stringByReplacingOccurrencesOfString:@"-" withString:@"_"];
    op = [op stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    if ([subcommand isEqualToString:@"track"]) {
        // Stable names for gallery / field journal: track_<op>.json (optical-flow under optical-flow/)
        NSString *base = [NSString stringWithFormat:@"track_%@", op];
        if ([op isEqualToString:@"optical_flow"]) {
            NSString *sub = [dir stringByAppendingPathComponent:@"optical-flow"];
            return [sub stringByAppendingPathComponent:[base stringByAppendingPathExtension:@"json"]];
        }
        return [dir stringByAppendingPathComponent:[base stringByAppendingPathExtension:@"json"]];
    }
    if ([subcommand isEqualToString:@"overlay"]) {
        NSString *stem = MVMainStem(stemPath);
        if (!stem.length) stem = @"overlay";
        return [dir stringByAppendingPathComponent:[[stem stringByAppendingString:@"_overlay"] stringByAppendingPathExtension:@"json"]];
    }
    if ([subcommand isEqualToString:@"ocr"] || [subcommand isEqualToString:@"debug"] ||
        [subcommand isEqualToString:@"shazam"] || [subcommand isEqualToString:@"nl"] ||
        [subcommand isEqualToString:@"speech"] || [subcommand isEqualToString:@"sna"]) {
        return [dir stringByAppendingPathComponent:[MVMainStem(stemPath) stringByAppendingPathExtension:@"json"]];
    }
    NSString *stem = MVMainStem(stemPath);
    return [dir stringByAppendingPathComponent:[[NSString stringWithFormat:@"%@_%@", stem, op]
                                                   stringByAppendingPathExtension:@"json"]];
}

static NSString *MVMainResolvedJSONOutput(NSString *subcommand,
                                          NSString *operation,
                                          NSString *jsonOutOpt,
                                          NSString *outOpt,
                                          NSString *stemPath) {
    if (jsonOutOpt.length && !MVPathIsExistingDirectory(jsonOutOpt)) {
        return jsonOutOpt;
    }
    if (jsonOutOpt.length && MVPathIsExistingDirectory(jsonOutOpt)) {
        return MVMainJsonInDirectory(jsonOutOpt, subcommand, operation, stemPath);
    }
    if (!outOpt.length) return nil;
    if (MVPathIsExistingDirectory(outOpt)) {
        return MVMainJsonInDirectory(outOpt, subcommand, operation, stemPath);
    }
    if ([outOpt.pathExtension.lowercaseString isEqualToString:@"json"]) {
        return outOpt;
    }
    return nil;
}

static NSString *MVMainResolvedArtifactsDir(NSString *subcommand,
                                            NSString *operation,
                                            NSString *artifactsDirOpt,
                                            NSString *outOpt) {
    if (artifactsDirOpt.length) return artifactsDirOpt;
    if (!MVPathIsExistingDirectory(outOpt)) return nil;
    if ([subcommand isEqualToString:@"segment"]) return outOpt;
    if ([subcommand isEqualToString:@"track"]) {
        NSString *op = MVMainEffectiveOperation(subcommand, operation).lowercaseString;
        if ([op isEqualToString:@"optical-flow"]) return outOpt;
        return nil;
    }
    if ([subcommand isEqualToString:@"face"] || [subcommand isEqualToString:@"classify"] ||
        [subcommand isEqualToString:@"ocr"]) {
        return outOpt;
    }
    if ([subcommand isEqualToString:@"capture"]) {
        NSString *cap = MVMainEffectiveOperation(subcommand, operation).lowercaseString;
        if (![cap isEqualToString:@"list-devices"]) return outOpt;
    }
    if ([subcommand isEqualToString:@"coreimage"]) {
        NSString *op = MVMainEffectiveOperation(subcommand, operation).lowercaseString;
        if ([op isEqualToString:@"apply-filter"] || [op isEqualToString:@"suggest-filters"]) return outOpt;
        return nil;
    }
    return nil;
}

static void printUsage(void) {
    printf(
        "USAGE: macos-vision <subcommand> [options]\n"
        "\n"
        "SUBCOMMANDS:\n"
        "  ocr       Text recognition (Vision)\n"
        "  face      Face, body, and pose (Vision)\n"
        "  classify  Scene/object analysis (Vision)\n"
        "  segment   Masks and saliency (Vision)\n"
        "  track     Video or frame-sequence registration / motion (Vision)\n"
        "  overlay   Vision JSON → SVG overlay\n"
        "  debug     Image metadata\n"
        "  shazam    Song/audio identification (ShazamKit)\n"
        "  capture   Screen, camera, microphone, list devices\n"
        "  nl        NaturalLanguage\n"
        "  av        AVFoundation (inspect, export, waveform, tts, …)\n"
        "  speech    Speech framework (transcribe, voice-analytics, list-locales)\n"
        "  sna       SoundAnalysis (classify, classify-custom, list-labels)\n"
        "  coreimage    CoreImage (apply-filter, suggest-filters, list-filters)\n"
        "  imagecapture ImageCaptureCore (list-devices, camera/*, scanner/*)\n"
        "\n"
        "COMMON OPTIONS:\n"
        "  --input <path>        Primary input: image, video, audio, text file, directory (track / shazam-build)\n"
        "  --output <path>       Meaning depends on subcommand (JSON file, media file, or .svg path)\n"
        "  --json-output <path>  Write the JSON envelope to this file (default: stdout)\n"
        "  --artifacts-dir <dir> PNG / debug overlays / isolate audio / optical-flow frames / capture media dir\n"
        "  --debug               Draw boxes/joints or emit processing_ms where supported\n"
        "  --boxes-format <fmt>  png (default), jpg, tiff, bmp, gif\n"
        "  --json <path>         Vision JSON path (overlay subcommand)\n"
        "\n"
        "OCR: --lang, --rec-langs\n"
        "FACE / CLASSIFY / SEGMENT / TRACK: --operation …\n"
        "TRACK optical-flow: uses --artifacts-dir for flow PNGs; falls back to CWD.\n"
        "OVERLAY: --json (required); --input overrides image; --output = .svg path (optional).\n"
        "SHAZAM: --input; --operation …; --catalog (match-custom / build)\n"
        "CAPTURE: --operation …, --display-index\n"
        "NL: --text, --input (text file), --operation …, --language, --scheme, --unit, --model, …\n"
        "AV: --input; --operation …; --preset; --times; --videos (compose); tts: --text/--input\n"
        "SPEECH: --input (audio file); --operation …; --audio-lang; --offline; --debug\n"
        "SNA: --input (audio file); --operation …; --topk; --classify-window; --classify-overlap; --model (classify-custom / list-labels)\n"
        "COREIMAGE:    --input (image); --operation …; --filter-name <CIFilterName>; --filter-params <json>; --format png|jpg|heif|tiff; --apply (suggest-filters); --category-only (list-filters)\n"
        "IMAGECAPTURE: --operation …; --device-index <N>; --file-index <N>; --all; --delete-after;\n"
        "              --sidecars; --thumb-size <px>; --dpi <N>; --format tiff|jpeg|png; --output <path>\n"
        "  Ops: list-devices | camera/files | camera/thumbnail | camera/metadata |\n"
        "       camera/import | camera/delete | camera/capture | camera/sync-clock |\n"
        "       scanner/preview | scanner/scan\n"
    );
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *args = [NSProcessInfo processInfo].arguments;

        if (args.count < 2) {
            printUsage();
            return 1;
        }

        // ── parse args ────────────────────────────────────────────────────────

        NSString *subcommand  = nil;
        NSString *inputPath   = nil;
        NSString *output      = nil;
        NSString *jsonOutputPath = nil;
        NSString *artifactsDir = nil;
        BOOL debug            = NO;
        BOOL lang             = NO;
        BOOL showLabels       = NO;
        NSString *recLangs    = nil;
        NSString *boxesFormat = @"png";
        NSString *operation   = nil;
        NSString *jsonPath    = nil;
        NSInteger displayIndex = 0;
        NSInteger deviceIndex  = 0;

        NSString *catalog     = nil;
        NSString *audioLang   = @"en-US";
        BOOL offline          = NO;
        NSInteger topk        = 3;
        BOOL mic              = NO;
        BOOL classifyWindowSet   = NO;
        NSTimeInterval classifyWindow = 0;
        BOOL classifyOverlapSet  = NO;
        double classifyOverlap   = 0;
        NSInteger pitchHopFrames = 0;

        NSString *nlText           = nil;
        NSString *nlLanguage       = nil;
        NSString *nlScheme         = nil;
        NSString *nlTokenizerUnit  = nil;
        NSString *nlWord           = nil;
        NSString *nlWordA          = nil;
        NSString *nlWordB          = nil;
        NSString *nlSimilar        = nil;
        NSString *nlModelPath      = nil;

        NSString *avPreset      = nil;
        NSString *avTime        = nil;
        NSString *avTimes       = nil;
        NSString *avTimeRange   = nil;
        NSString *avMetaKey     = nil;
        NSString *avVideos      = nil;
        NSString *avVoice       = nil;

        NSString *ciFilterName   = nil;
        NSString *ciFilterParams = nil;
        NSString *ciFormat       = @"png";
        BOOL ciCategoryOnly      = NO;
        BOOL ciApply             = NO;

        NSInteger iccFileIndex  = 0;
        BOOL iccAll             = NO;
        BOOL iccDeleteAfter     = NO;
        BOOL iccSidecars        = NO;
        NSInteger iccThumbSize  = 0;
        NSInteger iccDpi        = 0;

        for (NSInteger i = 1; i < (NSInteger)args.count; i++) {
            NSString *arg = args[i];

            if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                printUsage();
                return 0;
            } else if ([arg isEqualToString:@"--input"] && i + 1 < (NSInteger)args.count) {
                inputPath = args[++i];
            } else if ([arg isEqualToString:@"--json-output"] && i + 1 < (NSInteger)args.count) {
                jsonOutputPath = args[++i];
            } else if ([arg isEqualToString:@"--artifacts-dir"] && i + 1 < (NSInteger)args.count) {
                artifactsDir = args[++i];
            } else if ([arg isEqualToString:@"--output"] && i + 1 < (NSInteger)args.count) {
                output = args[++i];
            } else if ([arg isEqualToString:@"--rec-langs"] && i + 1 < (NSInteger)args.count) {
                recLangs = args[++i];
            } else if ([arg isEqualToString:@"--boxes-format"] && i + 1 < (NSInteger)args.count) {
                boxesFormat = args[++i];
            } else if ([arg isEqualToString:@"--operation"] && i + 1 < (NSInteger)args.count) {
                operation = args[++i];
            } else if ([arg isEqualToString:@"--json"] && i + 1 < (NSInteger)args.count) {
                jsonPath = args[++i];
            } else if ([arg isEqualToString:@"--debug"]) {
                debug = YES;
            } else if ([arg isEqualToString:@"--show-labels"]) {
                showLabels = YES;
            } else if ([arg isEqualToString:@"--lang"]) {
                lang = YES;
            } else if ([arg isEqualToString:@"--audio-lang"] && i + 1 < (NSInteger)args.count) {
                audioLang = args[++i];
            } else if ([arg isEqualToString:@"--catalog"] && i + 1 < (NSInteger)args.count) {
                catalog = args[++i];
            } else if ([arg isEqualToString:@"--offline"]) {
                offline = YES;
            } else if ([arg isEqualToString:@"--topk"] && i + 1 < (NSInteger)args.count) {
                topk = [args[++i] integerValue];
            } else if ([arg isEqualToString:@"--classify-window"] && i + 1 < (NSInteger)args.count) {
                classifyWindow = [args[++i] doubleValue];
                classifyWindowSet = YES;
            } else if ([arg isEqualToString:@"--classify-overlap"] && i + 1 < (NSInteger)args.count) {
                classifyOverlap = [args[++i] doubleValue];
                classifyOverlapSet = YES;
            } else if ([arg isEqualToString:@"--pitch-hop"] && i + 1 < (NSInteger)args.count) {
                pitchHopFrames = [args[++i] integerValue];
            } else if ([arg isEqualToString:@"--mic"]) {
                mic = YES;
            } else if ([arg isEqualToString:@"--display-index"] && i + 1 < (NSInteger)args.count) {
                displayIndex = [args[++i] integerValue];
            } else if ([arg isEqualToString:@"--device-index"] && i + 1 < (NSInteger)args.count) {
                deviceIndex = [args[++i] integerValue];
            } else if ([arg isEqualToString:@"--text"] && i + 1 < (NSInteger)args.count) {
                nlText = args[++i];
            } else if ([arg isEqualToString:@"--language"] && i + 1 < (NSInteger)args.count) {
                nlLanguage = args[++i];
            } else if ([arg isEqualToString:@"--scheme"] && i + 1 < (NSInteger)args.count) {
                nlScheme = args[++i];
            } else if ([arg isEqualToString:@"--unit"] && i + 1 < (NSInteger)args.count) {
                nlTokenizerUnit = args[++i];
            } else if ([arg isEqualToString:@"--word"] && i + 1 < (NSInteger)args.count) {
                nlWord = args[++i];
            } else if ([arg isEqualToString:@"--word-a"] && i + 1 < (NSInteger)args.count) {
                nlWordA = args[++i];
            } else if ([arg isEqualToString:@"--word-b"] && i + 1 < (NSInteger)args.count) {
                nlWordB = args[++i];
            } else if ([arg isEqualToString:@"--similar"] && i + 1 < (NSInteger)args.count) {
                nlSimilar = args[++i];
            } else if ([arg isEqualToString:@"--model"] && i + 1 < (NSInteger)args.count) {
                nlModelPath = args[++i];
            } else if ([arg isEqualToString:@"--preset"] && i + 1 < (NSInteger)args.count) {
                avPreset = args[++i];
            } else if ([arg isEqualToString:@"--time"] && i + 1 < (NSInteger)args.count) {
                avTime = args[++i];
            } else if ([arg isEqualToString:@"--times"] && i + 1 < (NSInteger)args.count) {
                avTimes = args[++i];
            } else if ([arg isEqualToString:@"--time-range"] && i + 1 < (NSInteger)args.count) {
                avTimeRange = args[++i];
            } else if ([arg isEqualToString:@"--key"] && i + 1 < (NSInteger)args.count) {
                avMetaKey = args[++i];
            } else if ([arg isEqualToString:@"--videos"] && i + 1 < (NSInteger)args.count) {
                avVideos = args[++i];
            } else if ([arg isEqualToString:@"--voice"] && i + 1 < (NSInteger)args.count) {
                avVoice = args[++i];
            } else if ([arg isEqualToString:@"--filter-name"] && i + 1 < (NSInteger)args.count) {
                ciFilterName = args[++i];
            } else if ([arg isEqualToString:@"--filter-params"] && i + 1 < (NSInteger)args.count) {
                ciFilterParams = args[++i];
            } else if ([arg isEqualToString:@"--format"] && i + 1 < (NSInteger)args.count) {
                ciFormat = args[++i];
            } else if ([arg isEqualToString:@"--apply"]) {
                ciApply = YES;
            } else if ([arg isEqualToString:@"--category-only"]) {
                ciCategoryOnly = YES;
            } else if ([arg isEqualToString:@"--file-index"] && i + 1 < (NSInteger)args.count) {
                iccFileIndex = [args[++i] integerValue];
            } else if ([arg isEqualToString:@"--all"]) {
                iccAll = YES;
            } else if ([arg isEqualToString:@"--delete-after"]) {
                iccDeleteAfter = YES;
            } else if ([arg isEqualToString:@"--sidecars"]) {
                iccSidecars = YES;
            } else if ([arg isEqualToString:@"--thumb-size"] && i + 1 < (NSInteger)args.count) {
                iccThumbSize = [args[++i] integerValue];
            } else if ([arg isEqualToString:@"--dpi"] && i + 1 < (NSInteger)args.count) {
                iccDpi = [args[++i] integerValue];
            } else if (![arg hasPrefix:@"--"] && subcommand == nil) {
                subcommand = arg;
            } else {
                fprintf(stderr, "Error: unknown option '%s'\n", arg.UTF8String);
                printUsage();
                return 1;
            }
        }

        if (!subcommand) {
            fprintf(stderr, "Error: missing subcommand\n");
            printUsage();
            return 1;
        }

        if ([subcommand isEqualToString:@"svg"]) {
            subcommand = @"overlay";
        }

        // ── validate ──────────────────────────────────────────────────────────

        NSArray<NSString *> *validFormats = @[@"png", @"jpg", @"jpeg", @"tiff", @"tif", @"bmp", @"gif"];
        if (![validFormats containsObject:[boxesFormat lowercaseString]]) {
            fprintf(stderr, "Error: unsupported --boxes-format '%s'. Supported: png, jpg, tiff, bmp, gif\n",
                    boxesFormat.UTF8String);
            return 1;
        }

        // ── dispatch ──────────────────────────────────────────────────────────

        NSError *error = nil;
        BOOL success = NO;

        NSString *visionIn = inputPath;
        NSString *effOp = MVMainEffectiveOperation(subcommand, operation);
        NSString *jsonStem = visionIn;
        if ([subcommand isEqualToString:@"track"]) {
            jsonStem = inputPath ?: @"";
        } else if ([subcommand isEqualToString:@"shazam"]) {
            jsonStem = inputPath ?: @"";
        } else if ([subcommand isEqualToString:@"nl"]) {
            jsonStem = inputPath ?: @"";
        } else if ([subcommand isEqualToString:@"speech"]) {
            jsonStem = inputPath ?: @"";
        } else if ([subcommand isEqualToString:@"sna"]) {
            jsonStem = inputPath ?: @"";
        } else if ([subcommand isEqualToString:@"coreimage"]) {
            jsonStem = inputPath ?: @"";
        } else if ([subcommand isEqualToString:@"imagecapture"]) {
            jsonStem = @"";
        } else if ([subcommand isEqualToString:@"overlay"]) {
            jsonStem = jsonPath.length ? jsonPath : @"";
        }
        NSString *jsonOutResolved = MVMainResolvedJSONOutput(subcommand, effOp, jsonOutputPath, output, jsonStem);
        NSString *artResolved = MVMainResolvedArtifactsDir(subcommand, operation, artifactsDir, output);

        if ([subcommand isEqualToString:@"ocr"]) {
            OCRProcessor *processor = [[OCRProcessor alloc] init];
            processor.inputPath   = visionIn;
            processor.jsonOutput  = jsonOutResolved;
            processor.artifactsDir = artResolved;
            processor.debug       = debug;
            processor.lang        = lang;
            processor.recLangs    = recLangs;
            processor.boxesFormat = boxesFormat;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"debug"]) {
            DebugProcessor *processor = [[DebugProcessor alloc] init];
            processor.inputPath    = visionIn;
            processor.jsonOutput   = jsonOutResolved;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"segment"]) {
            SegmentProcessor *processor = [[SegmentProcessor alloc] init];
            processor.inputPath    = visionIn;
            processor.jsonOutput   = jsonOutResolved;
            processor.artifactsDir = artResolved;
            processor.operation    = operation ?: @"foreground-mask";
            // --output as an exact media file path (not a directory, not .json)
            if (output.length && !MVPathIsExistingDirectory(output)
                && ![[output.pathExtension lowercaseString] isEqualToString:@"json"]) {
                processor.outputPath = output;
            }
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"face"]) {
            FaceProcessor *processor = [[FaceProcessor alloc] init];
            processor.inputPath    = visionIn;
            processor.jsonOutput   = jsonOutResolved;
            processor.artifactsDir = artResolved;
            processor.debug        = debug;
            processor.boxesFormat  = boxesFormat;
            processor.operation    = operation ?: @"face-rectangles";
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"classify"]) {
            ClassifyProcessor *processor = [[ClassifyProcessor alloc] init];
            processor.inputPath    = visionIn;
            processor.jsonOutput   = jsonOutResolved;
            processor.artifactsDir = artResolved;
            processor.debug        = debug;
            processor.boxesFormat  = boxesFormat;
            processor.operation    = operation ?: @"classify";
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"track"]) {
            TrackProcessor *processor = [[TrackProcessor alloc] init];
            processor.inputPath    = inputPath;
            processor.jsonOutput   = jsonOutResolved;
            processor.artifactsDir = artifactsDir.length ? artifactsDir : artResolved;
            processor.operation    = operation ?: @"homographic";
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"overlay"]) {
            OverlayProcessor *processor = [[OverlayProcessor alloc] init];
            processor.jsonPath     = jsonPath;
            processor.inputPath    = visionIn;
            processor.svgOutput    = output;
            processor.jsonOutput   = jsonOutputPath.length ? jsonOutputPath : jsonOutResolved;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"shazam"]) {
            ShazamProcessor *processor = [[ShazamProcessor alloc] init];
            processor.inputPath    = inputPath;
            processor.jsonOutput   = jsonOutResolved;
            processor.artifactsDir = artifactsDir.length ? artifactsDir : artResolved;
            processor.operation    = operation ?: @"match";
            processor.catalog      = catalog;
            processor.debug        = debug;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"capture"]) {
            CaptureProcessor *processor = [[CaptureProcessor alloc] init];
            NSString *capOp = operation ?: @"screenshot";
            processor.operation    = capOp;
            processor.mediaOutput  = output;
            processor.artifactsDir = artifactsDir.length ? artifactsDir : artResolved;
            if (jsonOutputPath.length) {
                processor.jsonOutput = jsonOutputPath;
            } else if ([capOp isEqualToString:@"list-devices"] && output.length) {
                processor.jsonOutput = output;
            } else {
                processor.jsonOutput = nil;
            }
            processor.displayIndex = displayIndex;
            processor.debug        = debug;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"nl"]) {
            NLProcessor *processor = [[NLProcessor alloc] init];
            processor.text         = nlText;
            processor.input          = inputPath;
            processor.operation      = operation ?: @"detect-language";
            processor.language       = nlLanguage;
            processor.scheme         = nlScheme;
            processor.unit           = nlTokenizerUnit;
            processor.topk           = topk;
            processor.word           = nlWord;
            processor.wordA          = nlWordA;
            processor.wordB          = nlWordB;
            processor.similar        = nlSimilar;
            processor.modelPath      = nlModelPath;
            processor.jsonOutput     = jsonOutResolved;
            processor.debug          = debug;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"av"]) {
            AVProcessor *processor = [[AVProcessor alloc] init];
            NSString *avOp = operation ?: @"inspect";
            processor.operation = avOp;
            if ([avOp isEqualToString:@"tts"]) {
                processor.inputFile = inputPath;
            } else if (inputPath.length) {
                if (MVPathLooksLikeStillImage(inputPath)) {
                    processor.img = inputPath;
                } else {
                    processor.video = inputPath;
                }
            }
            processor.output       = output.length ? output : jsonOutputPath;
            processor.artifactsDir = artifactsDir;
            processor.preset       = avPreset;
            processor.timeStr      = avTime;
            processor.timesStr     = avTimes;
            processor.timeRangeStr = avTimeRange;
            processor.metaKey      = avMetaKey;
            processor.videosStr    = avVideos;
            processor.text          = nlText;
            processor.inputFile     = inputPath;
            processor.voice         = avVoice;
            processor.pitchHopFrames = pitchHopFrames;
            processor.debug         = debug;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"speech"]) {
            SpeechProcessor *processor = [[SpeechProcessor alloc] init];
            processor.inputPath  = inputPath;
            processor.jsonOutput = jsonOutResolved;
            processor.operation  = operation ?: @"transcribe";
            processor.lang       = audioLang;
            processor.offline    = offline;
            processor.debug      = debug;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"sna"]) {
            SNAProcessor *processor = [[SNAProcessor alloc] init];
            processor.inputPath        = inputPath;
            processor.jsonOutput       = jsonOutResolved;
            processor.operation        = operation ?: @"classify";
            processor.modelPath        = nlModelPath;
            processor.topk             = topk;
            processor.windowDuration   = classifyWindow;
            processor.windowDurationSet = classifyWindowSet;
            processor.overlapFactor    = classifyOverlap;
            processor.overlapFactorSet = classifyOverlapSet;
            processor.debug            = debug;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"coreimage"]) {
            CIProcessor *processor = [[CIProcessor alloc] init];
            processor.inputPath        = visionIn;
            processor.jsonOutput       = jsonOutResolved;
            processor.artifactsDir     = artResolved;
            processor.operation        = operation ?: @"apply-filter";
            processor.filterName       = ciFilterName;
            processor.filterParamsJSON = ciFilterParams;
            processor.outputFormat     = ciFormat;
            processor.applyFilters     = ciApply;
            processor.categoryOnly     = ciCategoryOnly;
            processor.debug            = debug;
            // Exact image output file when --output is not a directory and not a .json file
            if (output.length && !MVPathIsExistingDirectory(output)
                && ![[output.pathExtension lowercaseString] isEqualToString:@"json"]) {
                processor.outputPath = output;
            }
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"imagecapture"]) {
            ICCProcessor *processor = [[ICCProcessor alloc] init];
            processor.operation        = operation ?: @"list-devices";
            processor.jsonOutput       = jsonOutResolved;
            processor.deviceIndex      = deviceIndex;
            processor.debug            = debug;
            processor.fileIndex        = iccFileIndex;
            processor.allFiles         = iccAll;
            processor.deleteAfter      = iccDeleteAfter;
            processor.downloadSidecars = iccSidecars;
            processor.thumbSize        = iccThumbSize;
            processor.scanDPI          = (NSUInteger)iccDpi;
            processor.outputFormat     = ciFormat;
            // Pass raw --output to processor; each operation decides how to use it
            if (output.length) processor.outputPath = output;
            success = [processor runWithError:&error];

        } else {
            fprintf(stderr, "Error: unknown subcommand '%s'. Available: ocr, face, classify, segment, track, overlay (svg), debug, shazam, capture, nl, av, speech, sna, coreimage, imagecapture\n",
                    subcommand.UTF8String);
            return 1;
        }

        if (!success) {
            fprintf(stderr, "Error: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
    }
    return 0;
}
