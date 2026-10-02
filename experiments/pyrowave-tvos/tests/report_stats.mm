#import <Foundation/Foundation.h>
#import "PWReportStats.h"
#include <cassert>
#include <cmath>
#include <cstdio>

int main() {
    @autoreleasepool {
        NSDictionary *missing = PWStats(@[@(NAN), @(INFINITY), @(-1.0)], 4, 1);
        assert([missing[@"samples"] unsignedIntegerValue] == 0);
        assert([missing[@"unavailable_samples"] unsignedIntegerValue] == 3);
        assert([missing[@"pending_samples"] unsignedIntegerValue] == 1);
        assert(missing[@"mean"] == NSNull.null && missing[@"max"] == NSNull.null);

        NSDictionary *available = PWStats(@[@(NAN), @2.0, @4.0, @(INFINITY)], 4, 0);
        assert([available[@"samples"] unsignedIntegerValue] == 2);
        assert([available[@"unavailable_samples"] unsignedIntegerValue] == 2);
        assert([available[@"mean"] doubleValue] == 3.0);
        assert([available[@"max"] doubleValue] == 4.0);

        NSError *error = nil;
        NSData *json = [NSJSONSerialization dataWithJSONObject:@{ @"gpu": missing, @"present": available }
                                                          options:0 error:&error];
        assert(json && !error);
        NSDictionary *decoded = [NSJSONSerialization JSONObjectWithData:json options:0 error:&error];
        assert(decoded && !error && decoded[@"gpu"][@"mean"] == NSNull.null);
        std::puts("report stats: PASS");
    }
}
