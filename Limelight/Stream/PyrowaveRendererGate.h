#ifndef PYROWAVE_RENDERER_GATE_H
#define PYROWAVE_RENDERER_GATE_H

#include <stdbool.h>
#include <stdlib.h>
#include <string.h>

typedef enum {
    PW_RENDERER_PENDING,
    PW_RENDERER_READY,
    PW_RENDERER_FAILED,
} PWRendererState;

typedef bool (*PWRendererInitialize)(void *context);
typedef void (*PWRendererFailure)(void *context);

// Shared by the live submission path and its forced-failure check. A failed
// selected session reports exactly once and cannot retry initialization.
static inline bool PWEnsureRenderer(PWRendererState *state, PWRendererInitialize initialize,
                                    PWRendererFailure fail, void *context) {
    if (*state == PW_RENDERER_READY) return true;
    if (*state == PW_RENDERER_FAILED) return false;

#if defined(DEBUG) && DEBUG
    const char *forced = getenv("MOONLIGHT_PYROWAVE_FORCE_INIT_FAILURE");
    const bool forceFailure = forced && strcmp(forced, "1") == 0;
#else
    const bool forceFailure = false;
#endif
    if (!forceFailure && initialize(context)) {
        *state = PW_RENDERER_READY;
        return true;
    }
    *state = PW_RENDERER_FAILED;
    fail(context);
    return false;
}

#endif
