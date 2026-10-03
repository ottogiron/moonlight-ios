#pragma once

#include <stdbool.h>
#include <stddef.h>
#include <string.h>

// Settings.bundle stores these values as Kbps strings. An unrecognized or
// malformed persisted value means no override, never a numeric conversion.
static inline int PWBitrateOverrideKbps(const char* persistedValue, size_t length) {
    if (persistedValue == NULL) return 0;
    if (length != 6) return 0;
    if (memcmp(persistedValue, "150000", 6) == 0) return 150000;
    if (memcmp(persistedValue, "200000", 6) == 0) return 200000;
    if (memcmp(persistedValue, "250000", 6) == 0) return 250000;
    if (memcmp(persistedValue, "300000", 6) == 0) return 300000;
    if (memcmp(persistedValue, "400000", 6) == 0) return 400000;
    if (memcmp(persistedValue, "500000", 6) == 0) return 500000;
    return 0;
}

static inline int PWRequestedBitrateKbps(int videoBitrateKbps, int pyrowaveBitrateKbps,
                                          bool pyrowaveRequested) {
    switch (pyrowaveBitrateKbps) {
        case 150000: case 200000: case 250000:
        case 300000: case 400000: case 500000:
            return pyrowaveRequested ? pyrowaveBitrateKbps : videoBitrateKbps;
        default:
            return videoBitrateKbps;
    }
}
