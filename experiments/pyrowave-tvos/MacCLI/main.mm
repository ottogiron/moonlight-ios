#import <Foundation/Foundation.h>
#import "PWProbeCore.h"

static int Run(int argc, const char **argv) {
    BOOL layoutOnly = NO;
    NSString *path = @"Fixtures";
    for (int i = 1; i < argc; ++i) {
        if (strcmp(argv[i], "--validate-only") == 0) layoutOnly = YES;
        else path = [NSString stringWithUTF8String:argv[i]];
    }
    NSError *error = nil;
    NSArray<PWFixture *> *fixtures = PWLoadFixtures([NSURL fileURLWithPath:path isDirectory:YES], &error);
    if (!fixtures) { fprintf(stderr, "fixtures: %s\n", error.localizedDescription.UTF8String); return 1; }
    if (layoutOnly) { puts("Fixture schema, hashes, layout, and sizes: PASS"); return 0; }
    PWProbeCore *core = [[PWProbeCore alloc] initWithError:&error];
    if (!core) { fprintf(stderr, "Metal: %s\n", error.localizedDescription.UTF8String); return 1; }
    if (![core prepareRendererWithPixelFormat:MTLPixelFormatBGRA8Unorm_sRGB error:&error]) {
        fprintf(stderr, "Renderer: %s\n", error.localizedDescription.UTF8String); return 1;
    }
    NSMutableArray *runs = [NSMutableArray new];
    BOOL allPassed = YES;
    // Reuse the same decoder/output textures while alternating sequences. Every
    // call clears the parser and waits for GPU completion before resource reuse.
    for (NSUInteger pass = 0; pass < 2; ++pass) {
        for (NSUInteger i = 0; i < fixtures.count; ++i) {
            PWFixture *fixture = fixtures[pass ? fixtures.count - 1 - i : i];
            error = nil;
            NSDictionary *planes = [core verifyFixture:fixture error:&error];
            BOOL passed = planes != nil && error == nil;
            allPassed &= passed;
            [runs addObject:@{ @"fixture": fixture.name, @"pass": @(pass + 1),
                               @"passed": @(passed), @"planes": planes ?: @{},
                               @"error": error.localizedDescription ?: @"" }];
            fprintf(stderr, "%s pass %lu: %s%s%s\n", fixture.name.UTF8String,
                    (unsigned long)(pass + 1), passed ? "PASS" : "FAIL",
                    error ? " - " : "", error ? error.localizedDescription.UTF8String : "");
        }
    }
    NSDictionary *report = @{ @"schema_version": @1, @"program": @"pyrowave-mac-verify",
                              @"pyrowave_commit": @"89f7e47d4abbf650c91fae766728af866c5e32a0",
                              @"tolerance_lsb": @2, @"passed": @(allPassed), @"runs": runs };
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
    if (!json) { fprintf(stderr, "report: %s\n", error.localizedDescription.UTF8String); return 1; }
    fwrite(json.bytes, 1, json.length, stdout); putchar('\n');
    return allPassed ? 0 : 1;
}

int main(int argc, const char **argv) {
    @autoreleasepool { return Run(argc, argv); }
}
