#import <Foundation/Foundation.h>
#import "ocr/main.h"
#import "debug/main.h"
#import "segment/main.h"
#import "face/main.h"
#import "classify/main.h"
#import "track/main.h"
#import "overlay/main.h"
#import "shazam/main.h"
#import "streamcapture/main.h"
#import "nl/main.h"
#import "av/main.h"
#import "speech/main.h"
#import "sna/main.h"
#import "coreimage/main.h"
#import "imagetransfer/main.h"

static void printUsage(void) {
    printf(
        "USAGE: macos-vision <subcommand> [options]\n"
        "\n"
        "Run 'macos-vision <subcommand> --help' for operations and options.\n"
        "\n"
        "SUBCOMMANDS:\n"
        "  ocr            Extract text from images\n"
        "  face           Detect faces, bodies, and poses in images\n"
        "  classify       Classify scenes, objects, and image content\n"
        "  segment        Separate subjects from backgrounds and generate saliency maps\n"
        "  track          Measure motion and registration across video frames\n"
        "  overlay        Visualise analysis results as an interactive SVG\n"
        "  debug          Inspect image file metadata and properties\n"
        "  shazam         Identify songs and audio from recordings\n"
        "  streamcapture  Capture stills, video, and audio from cameras and displays\n"
        "  nl             Analyse and process natural language text\n"
        "  av             Inspect, convert, and process audio and video files\n"
        "  speech         Transcribe speech and analyse voice characteristics\n"
        "  sna            Classify sounds and environmental audio\n"
        "  coreimage      Apply image filters and analyse visual properties\n"
        "  imagetransfer  Import and manage files on connected cameras and scanners\n"
    );
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray<NSString *> *args = [NSProcessInfo processInfo].arguments;

        // Find subcommand: first argument that doesn't start with --
        NSString *subcommand = nil;
        for (NSInteger i = 1; i < (NSInteger)args.count; i++) {
            if ([args[i] isEqualToString:@"--help"] || [args[i] isEqualToString:@"-h"]) {
                printUsage();
                return 0;
            }
            if (![args[i] hasPrefix:@"--"]) {
                subcommand = args[i];
                break;
            }
        }

        if (!subcommand) {
            printUsage();
            return 1;
        }

        // Alias
        if ([subcommand isEqualToString:@"svg"]) subcommand = @"overlay";

        NSError *error = nil;
        BOOL success = NO;

        if      ([subcommand isEqualToString:@"ocr"])          success = MVDispatchOCR(args, &error);
        else if ([subcommand isEqualToString:@"face"])         success = MVDispatchFace(args, &error);
        else if ([subcommand isEqualToString:@"classify"])     success = MVDispatchClassify(args, &error);
        else if ([subcommand isEqualToString:@"segment"])      success = MVDispatchSegment(args, &error);
        else if ([subcommand isEqualToString:@"track"])        success = MVDispatchTrack(args, &error);
        else if ([subcommand isEqualToString:@"overlay"])      success = MVDispatchOverlay(args, &error);
        else if ([subcommand isEqualToString:@"debug"])        success = MVDispatchDebug(args, &error);
        else if ([subcommand isEqualToString:@"shazam"])       success = MVDispatchShazam(args, &error);
        else if ([subcommand isEqualToString:@"streamcapture"])      success = MVDispatchStreamCapture(args, &error);
        else if ([subcommand isEqualToString:@"nl"])           success = MVDispatchNL(args, &error);
        else if ([subcommand isEqualToString:@"av"])           success = MVDispatchAV(args, &error);
        else if ([subcommand isEqualToString:@"speech"])       success = MVDispatchSpeech(args, &error);
        else if ([subcommand isEqualToString:@"sna"])          success = MVDispatchSNA(args, &error);
        else if ([subcommand isEqualToString:@"coreimage"])    success = MVDispatchCoreImage(args, &error);
        else if ([subcommand isEqualToString:@"imagetransfer"]) success = MVDispatchImageTransfer(args, &error);
        else {
            fprintf(stderr, "Error: unknown subcommand '%s'\n", subcommand.UTF8String);
            printUsage();
            return 1;
        }

        if (!success && error) {
            fprintf(stderr, "Error: %s\n", error.localizedDescription.UTF8String);
            return 1;
        }
        return success ? 0 : 1;
    }
}
