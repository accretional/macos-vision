#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// Bumped when the envelope shape changes.
FOUNDATION_EXPORT NSString * const MVCLIEnvelopeVersion;

/// One generated file or directory reference for `result.artifacts` (see envelope v2).
NSDictionary *MVArtifactEntry(NSString *path, NSString *role);

/// Merges `artifacts` into `result` under key `artifacts` (append-only; normalizes legacy string entries).
NSDictionary *MVResultByMergingArtifacts(NSDictionary *result, NSArray<NSDictionary *> *artifacts);

/// Returns `path` relative to the current working directory. If `path` does not start with the CWD
/// prefix it is returned unchanged (handles non-file labels like "mic" or "<inline>" transparently).
NSString *MVRelativePath(NSString *path);

/// Standard CLI JSON envelope: version, subcommand, operation, optional input path, free-form result.
NSDictionary *MVMakeEnvelope(NSString *subcommand,
                             NSString *operation,
                             NSString *_Nullable inputPath,
                             NSDictionary *result);

/// Writes pretty JSON to `jsonOutputPath`, or prints to stdout if path is nil/empty.
/// Human-oriented confirmation goes to stderr when writing a file.
BOOL MVEmitEnvelope(NSDictionary *envelope, NSString *_Nullable jsonOutputPath, NSError **error);

NS_ASSUME_NONNULL_END
