#import <Foundation/Foundation.h>
#import "ocr/main.h"
#import "debug/main.h"
#import "segment/main.h"
#import "face/main.h"
#import "classify/main.h"
#import "track/main.h"
#import "svg/main.h"

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
        "  svg       Overlay Vision JSON output as SVG shapes on the source image\n"
        "  debug     Print image metadata (dimensions, file size)\n"
        "\n"
        "COMMON OPTIONS:\n"
        "  --img <path>          Path to a single image file\n"
        "  --img-dir <path>      Directory containing images for batch/sequence mode\n"
        "  --output <path>       Output directory for single image mode\n"
        "  --output-dir <path>   Output directory for batch mode\n"
        "  --debug               Draw bounding boxes / joints on the image\n"
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
        "  --svg                 Also produce an SVG overlay for each output JSON\n"
        "  --show-labels         Show text labels in the SVG overlay (default: off)\n"
        "\n"
        "CLASSIFY OPTIONS:\n"
        "  --operation <op>      Operation: classify (default), animals, rectangles, horizon,\n"
        "                          contours, aesthetics, feature-print\n"
        "  --svg                 Also produce an SVG overlay for each output JSON\n"
        "  --show-labels         Show text labels in the SVG overlay (default: off)\n"
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
        "SVG OPTIONS:\n"
        "  --json <path>         Path to Vision JSON file (required)\n"
        "  --img <path>          Override source image (optional; falls back to info.filepath in JSON)\n"
        "  --output <path>       Output directory for the SVG file\n"
        "  --show-labels         Show text labels on shapes (default: off)\n"
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
        BOOL svgOutput        = NO;
        NSString *recLangs    = nil;
        NSString *boxesFormat = @"png";
        NSString *operation   = nil;
        NSString *jsonPath    = nil;

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
            } else if ([arg isEqualToString:@"--svg"]) {
                svgOutput = YES;
            } else if ([arg isEqualToString:@"--lang"]) {
                lang = YES;
            } else if ([arg isEqualToString:@"--merge"]) {
                merge = YES;
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
            processor.svg         = svgOutput;
            processor.svgLabels   = showLabels;
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
            processor.svg         = svgOutput;
            processor.svgLabels   = showLabels;
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

        } else if ([subcommand isEqualToString:@"svg"]) {
            SVGProcessor *processor = [[SVGProcessor alloc] init];
            processor.img        = img;
            processor.jsonPath   = jsonPath;
            processor.output     = output;
            processor.showLabels = showLabels;
            success = [processor runWithError:&error];

        } else {
            fprintf(stderr, "Error: unknown subcommand '%s'. Available: ocr, face, classify, segment, track, svg, debug\n",
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
