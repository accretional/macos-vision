#import <Foundation/Foundation.h>
#import "ocr/ocr.h"

static void printUsage(void) {
    printf(
        "USAGE: macos-vision <subcommand> [options]\n"
        "\n"
        "SUBCOMMANDS:\n"
        "  ocr    Perform OCR on single image or batch of images\n"
        "\n"
        "COMMON OPTIONS:\n"
        "  --img <path>          Path to a single image file\n"
        "  --img-dir <path>      Directory containing images for batch mode\n"
        "  --output <path>       Output directory for single image mode\n"
        "  --output-dir <path>   Output directory for batch mode\n"
        "  --debug               Draw bounding boxes on the image\n"
        "\n"
        "OCR OPTIONS:\n"
        "  --lang                Show supported recognition languages\n"
        "  --merge               Merge all text outputs into a single file (batch mode)\n"
        "  --rec-langs <langs>   Comma-separated recognition languages\n"
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

        NSString *subcommand = nil;
        NSString *img        = nil;
        NSString *imgDir     = nil;
        NSString *output     = nil;
        NSString *outputDir  = nil;
        BOOL debug           = NO;
        BOOL lang            = NO;
        BOOL merge           = NO;
        NSString *recLangs   = nil;

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
            } else if ([arg isEqualToString:@"--rec-langs"] && i + 1 < (NSInteger)args.count) {
                recLangs = args[++i];
            } else if ([arg isEqualToString:@"--debug"]) {
                debug = YES;
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

        // ── dispatch ──────────────────────────────────────────────────────────

        NSError *error = nil;
        BOOL success = NO;

        if ([subcommand isEqualToString:@"ocr"]) {
            OCRProcessor *processor = [[OCRProcessor alloc] init];
            processor.img       = img;
            processor.output    = output;
            processor.imgDir    = imgDir;
            processor.outputDir = outputDir;
            processor.debug     = debug;
            processor.lang      = lang;
            processor.merge     = merge;
            processor.recLangs  = recLangs;
            success = [processor runWithError:&error];
        } else {
            fprintf(stderr, "Error: unknown subcommand '%s'. Available: ocr\n", subcommand.UTF8String);
            return 1;
        }

        if (!success) {
            fprintf(stderr, "Error: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
    }
    return 0;
}
