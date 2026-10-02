#include "PWDrainTracker.hpp"
#include <cassert>
#include <cstdio>

int main() {
    PWDrainTracker success;
    success.target = 2;
    success.onCallback(); success.onSubmit();
    success.onCallback(); success.onSubmit();
    assert(success.outcome(false, false, 12, 0, 0, 0) == PWDrainOutcome::Waiting);
    success.onCompletion(true); success.onPresentation(true);
    success.onCompletion(true);
    // GPU completion alone cannot finalize: the last drawable is unobserved.
    assert(success.pendingCompletions() == 0 && success.pendingPresentations() == 1);
    assert(success.outcome(true, false, 12, 0, 0, 0) == PWDrainOutcome::Waiting);
    assert(success.outcome(true, true, 12, 0, 0, 0) == PWDrainOutcome::TimedOut);
    PWDrainTracker timedOut = success;
    timedOut.freeze();
    timedOut.onPresentation(true); // Late callback after timeout cannot rewrite the report.
    timedOut.onCompletion(true);
    assert(timedOut.pendingPresentations() == 1 && timedOut.presentationCallbacks == 1);
    success.onPresentation(true);
    assert(success.outcome(true, false, 12, 0, 0, 0) == PWDrainOutcome::Passed);

    PWDrainTracker stalledGPU;
    stalledGPU.target = 1;
    stalledGPU.onCallback(); stalledGPU.onSubmit(); stalledGPU.onPresentation(true);
    assert(stalledGPU.pendingCompletions() == 1);
    assert(stalledGPU.outcome(true, false, 12, 0, 0, 0) == PWDrainOutcome::Waiting);
    assert(stalledGPU.outcome(true, true, 12, 0, 0, 0) == PWDrainOutcome::TimedOut);

    PWDrainTracker skipped;
    skipped.target = 1;
    skipped.onCallback(); skipped.onSubmit(); skipped.onCompletion(true);
    skipped.onPresentation(false);
    assert(skipped.drained() && skipped.presented() == 0);
    assert(skipped.outcome(true, false, 12, 0, 0, 0) == PWDrainOutcome::Failed);

    PWDrainTracker gpuFailure;
    gpuFailure.target = 1;
    gpuFailure.onCallback(); gpuFailure.onSubmit(); gpuFailure.onCompletion(false);
    gpuFailure.onPresentation(true);
    assert(gpuFailure.outcome(true, false, 12, 0, 0, 0) == PWDrainOutcome::Failed);

    PWDrainTracker missedCallback;
    missedCallback.target = 2;
    missedCallback.onCallback(); missedCallback.onSubmit();
    missedCallback.onCallback(); // Busy at the second display callback.
    missedCallback.onCompletion(true); missedCallback.onPresentation(true);
    assert(missedCallback.outcome(true, false, 12, 1, 0, 0) == PWDrainOutcome::Failed);
    std::puts("drain accounting: PASS");
}
