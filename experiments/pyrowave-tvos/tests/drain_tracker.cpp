#include "PWDrainTracker.hpp"
#include <cassert>
#include <cstdio>
#include <limits>

int main() {
    double milliseconds = -1;
    assert(PWElapsedMilliseconds(1.0, 1.002, &milliseconds));
    assert(milliseconds > 1.99 && milliseconds < 2.01);
    assert(!PWElapsedMilliseconds(0, 1, &milliseconds));
    assert(!PWElapsedMilliseconds(2, 1, &milliseconds));
    assert(!PWElapsedMilliseconds(1, std::numeric_limits<double>::infinity(), &milliseconds));
    assert(!PWElapsedMilliseconds(std::numeric_limits<double>::quiet_NaN(), 2, &milliseconds));

    PWDrainTracker success;
    success.target = 2;
    success.onCallback(); success.onSubmit();
    success.onCallback(); success.onSubmit();
    assert(success.outcome(false, false, 12, 0, 0, 0) == PWDrainOutcome::Waiting);
    success.onCompletion(true); success.onPresentation(1.0, 11, 11);
    success.onCompletion(true);
    // GPU completion alone cannot finalize: the last drawable is unobserved.
    assert(success.pendingCompletions() == 0 && success.pendingPresentations() == 1);
    assert(success.outcome(true, false, 12, 0, 0, 0) == PWDrainOutcome::Waiting);
    assert(success.outcome(true, true, 12, 0, 0, 0) == PWDrainOutcome::TimedOut);
    PWDrainTracker timedOut = success;
    timedOut.freeze();
    timedOut.onPresentation(2.0, 12, 12); // Late callback after timeout cannot rewrite the report.
    timedOut.onCompletion(true);
    assert(timedOut.pendingPresentations() == 1 && timedOut.presentationCallbacks == 1);
    success.onPresentation(2.0, 12, 12);
    assert(success.outcome(true, false, 12, 0, 0, 0) == PWDrainOutcome::Passed);

    PWDrainTracker stalledGPU;
    stalledGPU.target = 1;
    stalledGPU.onCallback(); stalledGPU.onSubmit(); stalledGPU.onPresentation(1.0, 11, 11);
    assert(stalledGPU.pendingCompletions() == 1);
    assert(stalledGPU.outcome(true, false, 12, 0, 0, 0) == PWDrainOutcome::Waiting);
    assert(stalledGPU.outcome(true, true, 12, 0, 0, 0) == PWDrainOutcome::TimedOut);

    PWDrainTracker skipped;
    skipped.target = 1;
    skipped.onCallback(); skipped.onSubmit(); skipped.onCompletion(true);
    assert(!skipped.onPresentation(0, 11, 11));
    assert(skipped.drained() && skipped.presented() == 0);
    assert(skipped.zeroPresentationTimes == 1 && skipped.unavailablePresentationTimes == 0);
    assert(skipped.outcome(true, false, 12, 0, 0, 0) == PWDrainOutcome::Failed);

    PWDrainTracker unavailable;
    unavailable.target = 3;
    for (int i = 0; i < 3; ++i) { unavailable.onCallback(); unavailable.onSubmit(); unavailable.onCompletion(true); }
    assert(!unavailable.onPresentation(std::numeric_limits<double>::quiet_NaN(), 11, 11));
    assert(!unavailable.onPresentation(std::numeric_limits<double>::infinity(), 12, 12));
    assert(!unavailable.onPresentation(-1.0, 13, 13));
    assert(unavailable.unavailablePresentationTimes == 3 && unavailable.skippedPresentations == 3);

    PWDrainTracker wrongDrawable;
    wrongDrawable.target = 1;
    wrongDrawable.onCallback(); wrongDrawable.onSubmit(); wrongDrawable.onCompletion(true);
    assert(!wrongDrawable.onPresentation(1.0, 12, 11));
    assert(wrongDrawable.drawableIDMismatches == 1 && wrongDrawable.presented() == 0);
    assert(wrongDrawable.outcome(true, false, 12, 0, 0, 0) == PWDrainOutcome::Failed);

    PWDrainTracker gpuFailure;
    gpuFailure.target = 1;
    gpuFailure.onCallback(); gpuFailure.onSubmit(); gpuFailure.onCompletion(false);
    gpuFailure.onPresentation(1.0, 11, 11);
    assert(gpuFailure.outcome(true, false, 12, 0, 0, 0) == PWDrainOutcome::Failed);

    PWDrainTracker missedCallback;
    missedCallback.target = 2;
    missedCallback.onCallback(); missedCallback.onSubmit();
    missedCallback.onCallback(); // Busy at the second display callback.
    missedCallback.onCompletion(true); missedCallback.onPresentation(1.0, 11, 11);
    assert(missedCallback.outcome(true, false, 12, 1, 0, 0) == PWDrainOutcome::Failed);
    std::puts("drain accounting: PASS");
}
