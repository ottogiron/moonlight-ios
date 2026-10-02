#pragma once

#import <Foundation/Foundation.h>
#include <cmath>

static inline NSDictionary *PWStats(NSArray<NSNumber *> *values, NSUInteger opportunities, NSUInteger pending) {
    double mean = 0, maximum = 0;
    NSUInteger samples = 0;
    for (NSNumber *number in values) {
        double value = number.doubleValue;
        if (!std::isfinite(value) || value < 0) continue;
        ++samples;
        mean += (value - mean) / samples;
        maximum = MAX(maximum, value);
    }
    NSUInteger unavailable = opportunities > samples + pending ? opportunities - samples - pending : 0;
    return @{ @"samples": @(samples), @"unavailable_samples": @(unavailable),
              @"pending_samples": @(pending),
              @"mean": samples ? @(mean) : NSNull.null,
              @"max": samples ? @(maximum) : NSNull.null };
}
