#include "../../../Limelight/Stream/PyrowaveRendererGate.h"

#include <assert.h>

typedef struct {
    int initializeCount;
    int failureCount;
} Fixture;

static bool initialize(void *context) {
    ((Fixture *)context)->initializeCount++;
    return true;
}

static bool initializeFails(void *context) {
    ((Fixture *)context)->initializeCount++;
    return false;
}

static void fail(void *context) {
    ((Fixture *)context)->failureCount++;
}

int main(void) {
    Fixture fixture = {0};
    PWRendererState state = PW_RENDERER_PENDING;

    assert(setenv("MOONLIGHT_PYROWAVE_FORCE_INIT_FAILURE", "1", 1) == 0);
    assert(!PWEnsureRenderer(&state, initialize, fail, &fixture));
    assert(state == PW_RENDERER_FAILED);
    assert(fixture.initializeCount == 0 && fixture.failureCount == 1);
    assert(!PWEnsureRenderer(&state, initialize, fail, &fixture));
    assert(fixture.initializeCount == 0 && fixture.failureCount == 1);

    assert(unsetenv("MOONLIGHT_PYROWAVE_FORCE_INIT_FAILURE") == 0);
    state = PW_RENDERER_PENDING;
    assert(PWEnsureRenderer(&state, initialize, fail, &fixture));
    assert(PWEnsureRenderer(&state, initialize, fail, &fixture));
    assert(state == PW_RENDERER_READY);
    assert(fixture.initializeCount == 1 && fixture.failureCount == 1);

    state = PW_RENDERER_PENDING;
    assert(!PWEnsureRenderer(&state, initializeFails, fail, &fixture));
    assert(!PWEnsureRenderer(&state, initialize, fail, &fixture));
    assert(state == PW_RENDERER_FAILED);
    assert(fixture.initializeCount == 2 && fixture.failureCount == 2);
    return 0;
}
