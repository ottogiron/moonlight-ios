#include "../../../Limelight/Stream/PyrowaveDrawableSize.h"

#include <assert.h>

int main(void) {
    size_t width, height;
    // A 1920x1080 tvOS point surface may target a 4K physical output.
    assert(PWNativeDrawableSize(1920, 1080, 2, 3840, 2160, &width, &height));
    assert(width == 3840 && height == 2160);
    // Changing to a 1080p output recomputes the drawable rather than retaining 4K.
    assert(PWNativeDrawableSize(1920, 1080, 1, 1920, 1080, &width, &height));
    assert(width == 1920 && height == 1080);
    // Even a stale scale cannot request more pixels than the current mode.
    assert(PWNativeDrawableSize(1920, 1080, 2, 1920, 1080, &width, &height));
    assert(width == 1920 && height == 1080);
    // A 1440p output can use its native drawable for a 1440p decode.
    assert(PWNativeDrawableSize(1920, 1080, 4.0 / 3.0, 2560, 1440, &width, &height));
    assert(width == 2560 && height == 1440);
    // A 4K TV can display the same decoded 1440p frame in a 4K drawable.
    assert(PWNativeDrawableSize(1920, 1080, 2, 3840, 2160, &width, &height));
    assert(width == 3840 && height == 2160);
    assert(!PWNativeDrawableSize(1920, 1080, 0, 3840, 2160, &width, &height));
    return 0;
}
