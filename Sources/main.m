#import <Foundation/Foundation.h>
#import "ocr/main.h"
#import "debug/main.h"
#import "segment/main.h"
#import "face/main.h"
#import "classify/main.h"
#import "track/main.h"
#import "svg/main.h"  // OverlayProcessor
#import "audio/main.h"
#import "capture/main.h"
#import "nl/main.h"
#import "av/main.h"

static void printUsage(void) {
    printf(
        "USAGE: macos-vision <subcommand> [options]\n"
        "\n"
        "SUBCOMMANDS:\n"
        "  ocr       Perform OCR on single image or batch of images\n"
        "  face      Face, body, and pose analysis\n"
        "  classify  Scene/object classification and image analysis\n"
        "  segment   Image segmentation and saliency analysis\n"
        "  track     Video tracking and image registration\n"
        "  overlay   Overlay Vision JSON output as SVG shapes on the source image\n"
        "  debug     Print image metadata (dimensions, file size)\n"
        "  audio     Audio inference: transcription, classification, Shazam, pitch, noise\n"
        "  capture   Capture from screen, camera, or microphone; list capture devices\n"
        "  nl        NaturalLanguage: language ID, tokenize, tag, embeddings, text classify\n"
        "  av        AVFoundation: inspect, metadata, thumbnails, export, compose, waveform, tts\n"
        "\n"
        "COMMON OPTIONS:\n"
        "  --img <path>          Path to a single image file\n"
        "  --img-dir <path>      Directory containing images for batch/sequence mode\n"
        "  --output <path>       Output directory for single image mode\n"
        "  --output-dir <path>   Output directory for batch mode\n"
        "  --debug               Draw bounding boxes / joints on the image (or emit processing_ms)\n"
        "  --boxes-format <fmt>  Output format for debug images: png (default), jpg, tiff, bmp, gif\n"
        "  --json <path>         Path to a Vision JSON file (used by svg subcommand)\n"
        "\n"
        "OCR OPTIONS:\n"
        "  --lang                Show supported recognition languages\n"
        "  --merge               Merge all text outputs into a single file (batch mode)\n"
        "  --rec-langs <langs>   Comma-separated recognition languages\n"
        "\n"
        "FACE OPTIONS:\n"
        "  --operation <op>      Operation: face-rectangles (default), face-landmarks, face-quality,\n"
        "                          human-rectangles, body-pose, hand-pose, animal-pose\n"
        "\n"
        "CLASSIFY OPTIONS:\n"
        "  --operation <op>      Operation: classify (default), animals, rectangles, horizon,\n"
        "                          contours, aesthetics, feature-print\n"
        "\n"
        "SEGMENT OPTIONS:\n"
        "  --operation <op>      Operation: foreground-mask (default), person-segment,\n"
        "                          person-mask, attention-saliency, objectness-saliency\n"
        "\n"
        "TRACK OPTIONS:\n"
        "  --video <path>        Path to a video file\n"
        "  --operation <op>      Operation: homographic (default), translational,\n"
        "                          optical-flow, trajectories\n"
        "\n"
        "OVERLAY OPTIONS:\n"
        "  --json <path>         Path to Vision JSON file (required)\n"
        "  --img <path>          Override source image (optional; falls back to info.filepath in JSON)\n"
        "  --output <path>       Output directory for the SVG file\n"
        "  --show-labels         boundingBox: name + confidence; landmarks: group name\n"
        "\n"
        "AUDIO OPTIONS:\n"
        "  --audio <path>        Path to a single audio file\n"
        "  --audio-dir <path>    Directory of audio files (batch mode)\n"
        "  --operation <op>      transcribe | classify (default) | shazam | detect |\n"
        "                          noise | pitch | isolate |\n"
        "                          shazam-custom | shazam-build\n"
        "  --catalog <path>      .shazamcatalog file for shazam-custom (built with shazam-build)\n"
        "  --audio-lang <lang>   Language for transcription, e.g. en-US (default)\n"
        "  --offline             Force on-device speech recognition (macOS 13+)\n"
        "  --topk <n>            Top-K classifications to return (default 3)\n"
        "  --merge               Merge batch results into a single JSON\n"
        "  --mic                 Stream from microphone (press Enter to stop)\n"
        "\n"
        "CAPTURE OPTIONS:\n"
        "  --operation <op>      screenshot (default) | camera | mic | list-devices\n"
        "  --display-index <n>   Display to capture for screenshot (default 0 = main)\n"
        "\n"
        "NL OPTIONS (NaturalLanguage):\n"
        "  --text <str>          Inline text (or use --input / --input-dir)\n"
        "  --input <file>        Text file\n"
        "  --input-dir <path>    Directory of .txt / .md files (batch)\n"
        "  --operation <op>      detect-language | tokenize | tag | embed | distance |\n"
        "                          contextual-embed | classify\n"
        "  --language <lang>     BCP-47 hint, e.g. en, fr-FR\n"
        "  --scheme <s>          tag: pos | ner | lemma | language | script\n"
        "  --unit <u>            tokenize/tag unit: word (default) | sentence | paragraph\n"
        "  --word <w>            embed: vector for word; use with --similar for neighbors\n"
        "  --similar <w>         embed: nearest neighbors to word (--topk)\n"
        "  --word-a / --word-b   distance: two words (cosine distance)\n"
        "  --model <path>        classify or tag: compiled .mlmodel path\n"
        "  --topk <n>            detect-language hypotheses / embed neighbors / classify (default 3)\n"
        "  --merge               With --input-dir: also write merged JSON to --output\n"
        "\n"
        "AV OPTIONS (AVFoundation):\n"
        "  --video <path>        Video or audio-visual media file\n"
        "  --img <path>          Still image (thumbnail operation)\n"
        "  --operation <op>      inspect | tracks | metadata | thumbnail | export |\n"
        "                          export-audio | list-presets | compose | waveform | tts\n"
        "  --preset <name>       export/compose: low | medium | high | hevc-1080p | hevc-4k |\n"
        "                          prores-422 | prores-4444 | m4a | passthrough\n"
        "  --time <seconds>      thumbnail: single frame time (default 0)\n"
        "  --times <t1,t2,...>   thumbnail: multiple frames\n"
        "  --time-range <s,d>    export: start seconds and duration\n"
        "  --key <id>            metadata: filter AVMetadataItem by identifier\n"
        "  --videos <p1,p2,...>  compose: comma-separated input files to concatenate\n"
        "  --text <str>          tts: inline text to synthesize\n"
        "  --input <file>        tts: text file to synthesize\n"
        "  --voice <id>          tts: AVSpeechSynthesisVoice identifier (optional)\n"
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
        NSString *img         = nil;
        NSString *imgDir      = nil;
        NSString *output      = nil;
        NSString *outputDir   = nil;
        NSString *video       = nil;
        BOOL debug            = NO;
        BOOL lang             = NO;
        BOOL merge            = NO;
        BOOL showLabels       = NO;
        NSString *recLangs    = nil;
        NSString *boxesFormat = @"png";
        NSString *operation   = nil;
        NSString *jsonPath    = nil;
        NSInteger displayIndex = 0;

        // Audio-specific args
        NSString *audio       = nil;
        NSString *audioDir    = nil;
        NSString *catalog     = nil;
        NSString *audioLang   = @"en-US";
        BOOL offline          = NO;
        NSInteger topk        = 3;
        BOOL mic              = NO;

        NSString *nlText           = nil;
        NSString *nlInput          = nil;
        NSString *nlInputDir       = nil;
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

        for (NSInteger i = 1; i < (NSInteger)args.count; i++) {
            NSString *arg = args[i];

            if ([arg isEqualToString:@"--help"] || [arg isEqualToString:@"-h"]) {
                printUsage();
                return 0;
            } else if ([arg isEqualToString:@"--img"] && i + 1 < (NSInteger)args.count) {
                img = args[++i];
            } else if ([arg isEqualToString:@"--img-dir"] && i + 1 < (NSInteger)args.count) {
                imgDir = args[++i];
            } else if ([arg isEqualToString:@"--output"] && i + 1 < (NSInteger)args.count) {
                output = args[++i];
            } else if ([arg isEqualToString:@"--output-dir"] && i + 1 < (NSInteger)args.count) {
                outputDir = args[++i];
            } else if ([arg isEqualToString:@"--video"] && i + 1 < (NSInteger)args.count) {
                video = args[++i];
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
            } else if ([arg isEqualToString:@"--merge"]) {
                merge = YES;
            } else if ([arg isEqualToString:@"--audio"] && i + 1 < (NSInteger)args.count) {
                audio = args[++i];
            } else if ([arg isEqualToString:@"--audio-dir"] && i + 1 < (NSInteger)args.count) {
                audioDir = args[++i];
            } else if ([arg isEqualToString:@"--audio-lang"] && i + 1 < (NSInteger)args.count) {
                audioLang = args[++i];
            } else if ([arg isEqualToString:@"--catalog"] && i + 1 < (NSInteger)args.count) {
                catalog = args[++i];
            } else if ([arg isEqualToString:@"--offline"]) {
                offline = YES;
            } else if ([arg isEqualToString:@"--topk"] && i + 1 < (NSInteger)args.count) {
                topk = [args[++i] integerValue];
            } else if ([arg isEqualToString:@"--mic"]) {
                mic = YES;
            } else if ([arg isEqualToString:@"--display-index"] && i + 1 < (NSInteger)args.count) {
                displayIndex = [args[++i] integerValue];
            } else if ([arg isEqualToString:@"--text"] && i + 1 < (NSInteger)args.count) {
                nlText = args[++i];
            } else if ([arg isEqualToString:@"--input"] && i + 1 < (NSInteger)args.count) {
                nlInput = args[++i];
            } else if ([arg isEqualToString:@"--input-dir"] && i + 1 < (NSInteger)args.count) {
                nlInputDir = args[++i];
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

        if ([subcommand isEqualToString:@"ocr"]) {
            OCRProcessor *processor = [[OCRProcessor alloc] init];
            processor.img         = img;
            processor.output      = output;
            processor.imgDir      = imgDir;
            processor.outputDir   = outputDir;
            processor.debug       = debug;
            processor.lang        = lang;
            processor.merge       = merge;
            processor.recLangs    = recLangs;
            processor.boxesFormat = boxesFormat;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"debug"]) {
            DebugProcessor *processor = [[DebugProcessor alloc] init];
            processor.img       = img;
            processor.output    = output;
            processor.imgDir    = imgDir;
            processor.outputDir = outputDir;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"segment"]) {
            SegmentProcessor *processor = [[SegmentProcessor alloc] init];
            processor.img       = img;
            processor.output    = output;
            processor.imgDir    = imgDir;
            processor.outputDir = outputDir;
            processor.operation = operation ?: @"foreground-mask";
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"face"]) {
            FaceProcessor *processor = [[FaceProcessor alloc] init];
            processor.img         = img;
            processor.output      = output;
            processor.imgDir      = imgDir;
            processor.outputDir   = outputDir;
            processor.debug       = debug;
            processor.boxesFormat = boxesFormat;
            processor.operation   = operation ?: @"face-rectangles";
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"classify"]) {
            ClassifyProcessor *processor = [[ClassifyProcessor alloc] init];
            processor.img         = img;
            processor.output      = output;
            processor.imgDir      = imgDir;
            processor.outputDir   = outputDir;
            processor.debug       = debug;
            processor.boxesFormat = boxesFormat;
            processor.operation   = operation ?: @"classify";
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"track"]) {
            TrackProcessor *processor = [[TrackProcessor alloc] init];
            processor.video      = video;
            processor.imgDir     = imgDir;
            processor.output     = output;
            processor.outputDir  = outputDir;
            processor.operation  = operation ?: @"homographic";
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"overlay"]) {
            OverlayProcessor *processor = [[OverlayProcessor alloc] init];
            processor.img        = img;
            processor.jsonPath   = jsonPath;
            processor.output     = output;
            processor.showLabels = showLabels;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"audio"]) {
            AudioProcessor *processor = [[AudioProcessor alloc] init];
            processor.audio         = audio;
            processor.audioDir      = audioDir;
            processor.operation     = operation ?: @"classify";
            processor.output        = output;
            processor.outputDir     = outputDir;
            processor.lang          = audioLang;
            processor.offline       = offline;
            processor.topk          = topk;
            processor.merge         = merge;
            processor.debug         = debug;
            processor.mic           = mic;
            processor.catalog       = catalog;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"capture"]) {
            CaptureProcessor *processor = [[CaptureProcessor alloc] init];
            processor.operation    = operation ?: @"screenshot";
            processor.output       = output;
            processor.outputDir    = outputDir;
            processor.displayIndex = displayIndex;
            processor.debug        = debug;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"nl"]) {
            NLProcessor *processor = [[NLProcessor alloc] init];
            processor.text       = nlText;
            processor.input      = nlInput;
            processor.inputDir   = nlInputDir;
            processor.operation  = operation ?: @"detect-language";
            processor.language   = nlLanguage;
            processor.scheme     = nlScheme;
            processor.unit       = nlTokenizerUnit;
            processor.topk       = topk;
            processor.word       = nlWord;
            processor.wordA      = nlWordA;
            processor.wordB      = nlWordB;
            processor.similar    = nlSimilar;
            processor.modelPath  = nlModelPath;
            processor.output     = output;
            processor.outputDir  = outputDir;
            processor.merge      = merge;
            processor.debug      = debug;
            success = [processor runWithError:&error];

        } else if ([subcommand isEqualToString:@"av"]) {
            AVProcessor *processor = [[AVProcessor alloc] init];
            processor.video        = video;
            processor.img          = img;
            processor.operation    = operation ?: @"inspect";
            processor.output       = output;
            processor.outputDir    = outputDir;
            processor.preset       = avPreset;
            processor.timeStr      = avTime;
            processor.timesStr     = avTimes;
            processor.timeRangeStr = avTimeRange;
            processor.metaKey      = avMetaKey;
            processor.videosStr    = avVideos;
            processor.text         = nlText;
            processor.inputFile    = nlInput;
            processor.voice        = avVoice;
            processor.debug        = debug;
            success = [processor runWithError:&error];

        } else {
            fprintf(stderr, "Error: unknown subcommand '%s'. Available: ocr, face, classify, segment, track, overlay, debug, audio, capture, nl, av\n",
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
