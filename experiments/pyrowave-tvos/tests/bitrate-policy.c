#include "../../../Limelight/Stream/PyrowaveBitratePolicy.h"

#include <assert.h>
#include <limits.h>
#include <stdio.h>

static int persisted(const char* value, size_t length) {
    return PWBitrateOverrideKbps(value, length);
}

#define STORED(value) persisted((value), sizeof(value) - 1)

int main(void) {
    const int ordinary = 150000;
    const int choices[] = { 150000, 200000, 250000, 300000, 400000, 500000 };
    const char* stored[] = { "150000", "200000", "250000", "300000", "400000", "500000" };

    assert(persisted(NULL, 0) == 0);
    assert(STORED("0") == 0);
    assert(PWRequestedBitrateKbps(ordinary, 0, true) == ordinary);
    for (size_t i = 0; i < sizeof(choices) / sizeof(choices[0]); i++) {
        int selected = persisted(stored[i], 6);
        assert(selected == choices[i]);
        assert(PWRequestedBitrateKbps(ordinary, selected, true) == choices[i]);
        assert(PWRequestedBitrateKbps(ordinary, selected, false) == ordinary);
    }

    // Malformed, wrong-unit, negative, out-of-range, and numeric overflow values
    // all leave the user's ordinary bitrate untouched.
    const char* invalid[] = {
        "-300000", "300", "300Mbps", "0300000", "300001", "500001",
        "999999", "2147483648", "18446744073709551616", " 300000", "300000 "
    };
    for (size_t i = 0; i < sizeof(invalid) / sizeof(invalid[0]); i++) {
        int selected = persisted(invalid[i], strlen(invalid[i]));
        assert(selected == 0);
        assert(PWRequestedBitrateKbps(ordinary, selected, true) == ordinary);
    }
    const char embeddedNul[] = { '3', '0', '0', '0', '0', '0', '\0', 'x' };
    assert(persisted(embeddedNul, sizeof(embeddedNul)) == 0);
    assert(PWRequestedBitrateKbps(ordinary, INT_MAX, true) == ordinary);
    assert(PWRequestedBitrateKbps(ordinary, -1, true) == ordinary);

    // This is the value handed from StreamManager to Connection for both
    // STREAM_CONFIGURATION.bitrate and the Pyrowave frame-cap calculation.
    assert(PWRequestedBitrateKbps(ordinary, STORED("300000"), true) == 300000);
    puts("Pyrowave bitrate policy: PASS");
    return 0;
}
