#ifndef PYROWAVE_DRAWABLE_SIZE_H
#define PYROWAVE_DRAWABLE_SIZE_H

#include <math.h>
#include <stdbool.h>
#include <stddef.h>

// Convert the displayed layer's point extent to native pixels, bounded by the
// current screen mode. Recompute this when the view or display mode changes.
static inline bool PWNativeDrawableSize(double pointWidth, double pointHeight,
                                        double nativeScale, size_t nativeWidth,
                                        size_t nativeHeight, size_t *width,
                                        size_t *height) {
    if (!isfinite(pointWidth) || !isfinite(pointHeight) || !isfinite(nativeScale) ||
        pointWidth <= 0 || pointHeight <= 0 || nativeScale <= 0 ||
        !nativeWidth || !nativeHeight || !width || !height) return false;
    double scale = fmin(nativeScale,
                        fmin((double)nativeWidth / pointWidth,
                             (double)nativeHeight / pointHeight));
    *width = (size_t)llround(pointWidth * scale);
    *height = (size_t)llround(pointHeight * scale);
    return *width > 0 && *height > 0;
}

#endif
