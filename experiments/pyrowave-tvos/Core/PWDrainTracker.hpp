#pragma once

#include <cstdint>
#include <cmath>

enum class PWDrainOutcome { Waiting, Passed, Failed, TimedOut };

inline bool PWElapsedMilliseconds(double start, double end, double *milliseconds) {
    if (!std::isfinite(start) || start <= 0 || !std::isfinite(end) || end < start)
        return false;
    double elapsed = (end - start) * 1000.0;
    if (!std::isfinite(elapsed)) return false;
    *milliseconds = elapsed;
    return true;
}

// Main-thread accounting for measured display callbacks only. A submitted
// frame has exactly one render-command-buffer completion and one drawable
// presentation callback. Warmup frames are deliberately outside these counts.
struct PWDrainTracker {
    uint64_t target = 0;
    uint64_t callbacks = 0;
    uint64_t submitted = 0;
    uint64_t completed = 0;
    uint64_t gpuErrors = 0;
    uint64_t presentationCallbacks = 0;
    uint64_t skippedPresentations = 0;
    uint64_t zeroPresentationTimes = 0;
    uint64_t unavailablePresentationTimes = 0;
    uint64_t drawableIDMismatches = 0;
    bool frozen = false;

    void freeze() { frozen = true; }
    void onCallback() { if (!frozen) ++callbacks; }
    void onSubmit() { if (!frozen) ++submitted; }
    void onCompletion(bool succeeded) {
        if (frozen) return;
        ++completed;
        if (!succeeded) ++gpuErrors;
    }
    bool onPresentation(double presentedTime, uint64_t drawableID, uint64_t submittedDrawableID) {
        if (frozen) return false;
        ++presentationCallbacks;
        if (presentedTime == 0) ++zeroPresentationTimes;
        else if (!std::isfinite(presentedTime) || presentedTime < 0) ++unavailablePresentationTimes;
        if (drawableID != submittedDrawableID) ++drawableIDMismatches;
        bool wasPresented = std::isfinite(presentedTime) && presentedTime > 0 &&
                            drawableID == submittedDrawableID;
        if (!wasPresented) ++skippedPresentations;
        return wasPresented;
    }
    uint64_t presented() const { return presentationCallbacks - skippedPresentations; }
    uint64_t pendingCompletions() const { return completed < submitted ? submitted - completed : 0; }
    uint64_t pendingPresentations() const {
        return presentationCallbacks < submitted ? submitted - presentationCallbacks : 0;
    }
    bool drained() const {
        return completed == submitted && presentationCallbacks == submitted;
    }
    PWDrainOutcome outcome(bool stopping, bool timedOut, uint64_t validationPasses,
                           uint64_t busyCallbacks, uint64_t noDrawableCallbacks,
                           uint64_t cadenceMisses) const {
        if (!stopping) return PWDrainOutcome::Waiting;
        if (timedOut) return PWDrainOutcome::TimedOut;
        if (!drained()) return PWDrainOutcome::Waiting;
        return validationPasses == 12 && callbacks == target && submitted == target &&
               completed == target && presentationCallbacks == target &&
               skippedPresentations == 0 && gpuErrors == 0 &&
               busyCallbacks == 0 && noDrawableCallbacks == 0 && cadenceMisses == 0
                   ? PWDrainOutcome::Passed : PWDrainOutcome::Failed;
    }
};
