#import "MVJsonEmit.h"

NSString * const MVCLIEnvelopeVersion = @"2";

NSString *MVRelativePath(NSString *path) {
    if (!path.length) return path;
    NSString *cwd = [[NSFileManager defaultManager] currentDirectoryPath];
    NSString *prefix = [cwd stringByAppendingString:@"/"];
    if ([path hasPrefix:prefix]) {
        return [path substringFromIndex:prefix.length];
    }
    return path;
}

NSDictionary *MVArtifactEntry(NSString *path, NSString *role) {
    if (!path.length) return @{};
    return @{ @"path": MVRelativePath(path), @"role": role.length ? role : @"file" };
}

NSDictionary *MVResultByMergingArtifacts(NSDictionary *result, NSArray<NSDictionary *> *artifacts) {
    NSDictionary *base = result ?: @{};
    if (!artifacts.count) return base;
    NSMutableDictionary *m = [base mutableCopy];
    NSMutableArray *combined = [NSMutableArray array];
    id existing = m[@"artifacts"];
    if ([existing isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)existing) {
            if ([item isKindOfClass:[NSString class]]) {
                NSDictionary *e = MVArtifactEntry((NSString *)item, @"file");
                if (e.count) [combined addObject:e];
            } else if ([item isKindOfClass:[NSDictionary class]]) {
                [combined addObject:item];
            }
        }
    }
    for (NSDictionary *a in artifacts) {
        if (a.count) [combined addObject:a];
    }
    m[@"artifacts"] = combined;
    return m;
}

NSDictionary *MVMakeEnvelope(NSString *subcommand,
                             NSString *operation,
                             NSString *inputPath,
                             NSDictionary *result) {
    NSMutableDictionary *env = [@{
        @"cliVersion": MVCLIEnvelopeVersion,
        @"subcommand": subcommand ?: @"",
        @"operation": operation ?: @"",
        @"result": result ?: @{},
    } mutableCopy];
    if (inputPath.length) env[@"input"] = MVRelativePath(inputPath);
    return env;
}

BOOL MVEmitEnvelope(NSDictionary *envelope, NSString *jsonOutputPath, NSError **error) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:envelope
                                                   options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys | NSJSONWritingWithoutEscapingSlashes
                                                     error:error];
    if (!data) return NO;
    NSString *str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    if (jsonOutputPath.length) {
        NSString *dir = jsonOutputPath.stringByDeletingLastPathComponent;
        if (dir.length) {
            [[NSFileManager defaultManager] createDirectoryAtPath:dir
                                       withIntermediateDirectories:YES
                                                        attributes:nil
                                                             error:nil];
        }
        if (![str writeToFile:jsonOutputPath atomically:YES encoding:NSUTF8StringEncoding error:error]) return NO;
    } else {
        printf("%s\n", str.UTF8String);
    }
    return YES;
}
