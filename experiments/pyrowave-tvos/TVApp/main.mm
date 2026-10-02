#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "PWProbeCore.h"
#import "PWReportStats.h"
#include "PWDrainTracker.hpp"

static const NSTimeInterval PWDrainTimeoutSeconds = 3.0;

@interface PWMetalView : UIView
@end
@implementation PWMetalView
+ (Class)layerClass { return CAMetalLayer.class; }
@end

@interface PWViewController : UIViewController
@end
@implementation PWViewController {
    PWMetalView *_metalView;
    UILabel *_status;
    PWProbeCore *_core;
    NSArray<PWFixture *> *_fixtures;
    NSMutableArray *_checks;
    NSMutableArray<NSNumber *> *_cpuSubmission;
    NSMutableArray<NSNumber *> *_gpuDecode;
    NSMutableArray<NSNumber *> *_gpuRender;
    NSMutableArray<NSNumber *> *_presentIntervals;
    CADisplayLink *_displayLink;
    NSTimer *_drainTimer;
    PWDrainTracker _drain;
    NSUInteger _warmup, _measured, _ticks;
    NSUInteger _busyTicks, _noDrawableTicks, _cadenceMisses;
    CFTimeInterval _lastTick, _lastPresentation, _measureStart, _measureEnd;
    BOOL _inFlight, _draining, _drainTimedOut, _finished;
    NSString *_failure;
}
- (void)loadView {
    self.view = [UIView new];
    self.view.backgroundColor = UIColor.blackColor;
    _metalView = [[PWMetalView alloc] initWithFrame:self.view.bounds];
    _metalView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:_metalView];
    _status = [[UILabel alloc] initWithFrame:CGRectMake(60, 50, 1800, 260)];
    _status.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _status.numberOfLines = 5;
    _status.textColor = UIColor.whiteColor;
    _status.backgroundColor = [UIColor colorWithWhite:0 alpha:0.72];
    _status.font = [UIFont monospacedSystemFontOfSize:34 weight:UIFontWeightMedium];
    _status.text = @"Pyrowave TV Probe\nLoading fixtures…";
    [self.view addSubview:_status];
}
- (void)viewDidAppear:(BOOL)animated {
    [super viewDidAppear:animated];
    if (_checks) return;
    _checks = [NSMutableArray new];
    _cpuSubmission = [NSMutableArray new];
    _gpuDecode = [NSMutableArray new];
    _gpuRender = [NSMutableArray new];
    _presentIntervals = [NSMutableArray new];
    _warmup = 60; _measured = 3600;
    NSArray<NSString *> *args = NSProcessInfo.processInfo.arguments;
    for (NSUInteger i = 1; i + 1 < args.count; ++i) {
        NSString *flag = args[i];
        NSInteger value = [args[i + 1] integerValue];
        if (value < 1 || value > 3600) continue;
        if ([flag isEqualToString:@"--frames"]) { _measured = (NSUInteger)value; ++i; }
        else if ([flag isEqualToString:@"--warmup"]) { _warmup = (NSUInteger)value; ++i; }
    }
    _drain.target = _measured;
    [self start];
}
- (void)start {
    NSURL *fixturesURL = [NSBundle.mainBundle.resourceURL URLByAppendingPathComponent:@"Fixtures" isDirectory:YES];
    NSError *error = nil;
    _fixtures = PWLoadFixtures(fixturesURL, &error);
    if (!_fixtures) { [self fail:[NSString stringWithFormat:@"Fixtures: %@", error.localizedDescription]]; return; }
    _core = [[PWProbeCore alloc] initWithError:&error];
    if (!_core) { [self fail:[NSString stringWithFormat:@"Metal: %@", error.localizedDescription]]; return; }
    CAMetalLayer *layer = (CAMetalLayer *)_metalView.layer;
    layer.device = _core.metalDevice;
    layer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    layer.framebufferOnly = YES;
    layer.drawableSize = CGSizeMake(1920, 1080);
    layer.maximumDrawableCount = 3;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    layer.colorspace = colorSpace;
    CGColorSpaceRelease(colorSpace);
    if (![_core prepareRendererWithPixelFormat:layer.pixelFormat error:&error]) {
        [self fail:[NSString stringWithFormat:@"Renderer: %@", error.localizedDescription]]; return;
    }
    // Readback correctness is outside the timed display loop. Alternating the
    // second pass also tests parser clearing and shared texture reuse.
    for (NSUInteger pass = 0; pass < 2; ++pass) {
        for (NSUInteger i = 0; i < _fixtures.count; ++i) {
            PWFixture *fixture = _fixtures[pass ? _fixtures.count - 1 - i : i];
            error = nil;
            NSDictionary *planes = [_core verifyFixture:fixture error:&error];
            BOOL passed = planes != nil && error == nil;
            [_checks addObject:@{ @"fixture": fixture.name, @"pass": @(pass + 1),
                                  @"planes": planes ?: @{}, @"passed": @(passed),
                                  @"error": error.localizedDescription ?: @"" }];
            NSLog(@"Pyrowave verification %@ pass %lu: %@ %@", fixture.name,
                  (unsigned long)(pass + 1), passed ? @"PASS" : @"FAIL", error.localizedDescription ?: @"");
            if (!passed) { [self fail:[NSString stringWithFormat:@"%@ verification: %@", fixture.name, error.localizedDescription]]; return; }
        }
    }
    _status.text = [NSString stringWithFormat:@"Pyrowave TV Probe\n12/12 Vulkan comparisons PASS (≤2 LSB)\nWarmup: 0/%lu", (unsigned long)_warmup];
    _displayLink = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick:)];
    _displayLink.preferredFramesPerSecond = 60;
    [_displayLink addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)tick:(CADisplayLink *)link {
    if (_finished || _draining) return;
    BOOL measuring = _ticks >= _warmup;
    if (measuring) {
        if (!_measureStart) _measureStart = link.timestamp;
        _measureEnd = link.timestamp;
    }
    if (_lastTick && measuring && link.timestamp - _lastTick > (1.5 / 60.0))
        _cadenceMisses += MAX(1, (NSInteger)llround((link.timestamp - _lastTick) * 60.0) - 1);
    _lastTick = link.timestamp;
    if (measuring) _drain.onCallback();
    if (_inFlight) { if (measuring) _busyTicks++; [self advance]; return; }
    CAMetalLayer *layer = (CAMetalLayer *)_metalView.layer;
    id<CAMetalDrawable> drawable = [layer nextDrawable];
    if (!drawable) { if (measuring) _noDrawableTicks++; [self advance]; return; }
    PWFixture *fixture = _fixtures[_ticks % _fixtures.count];
    CFTimeInterval cpuStart = CACurrentMediaTime();
    id<MTLCommandBuffer> decode = [_core.queue commandBuffer];
    id<MTLCommandBuffer> render = [_core.queue commandBuffer];
    NSError *error = nil;
    if (!decode || !render || ![_core encodeFixture:fixture commandBuffer:decode error:&error] ||
        ![_core encodeRender:render drawable:drawable error:&error]) {
        [self fail:error.localizedDescription ?: @"Could not encode Metal work"]; return;
    }
    _inFlight = YES;
    if (measuring) _drain.onSubmit();
    __weak PWViewController *weakSelf = self;
    NSUInteger submittedDrawableID = drawable.drawableID;
    [drawable addPresentedHandler:^(id<MTLDrawable> presentedDrawable) {
        // Preserve the callback's timestamp and ID as one observation before main-queue accounting.
        CFTimeInterval presentedTime = presentedDrawable.presentedTime;
        NSUInteger presentedDrawableID = presentedDrawable.drawableID;
        dispatch_async(dispatch_get_main_queue(), ^{
            PWViewController *owner = weakSelf;
            if (!owner || owner->_finished || !measuring) return;
            BOOL presented = owner->_drain.onPresentation(presentedTime, presentedDrawableID,
                                                           submittedDrawableID);
            if (presented) {
                double interval;
                if (PWElapsedMilliseconds(owner->_lastPresentation, presentedTime, &interval))
                    [owner->_presentIntervals addObject:@(interval)];
                owner->_lastPresentation = presentedTime;
            } else {
                owner->_lastPresentation = 0;
            }
            [owner maybeFinishDrain];
        });
    }];
    [render presentDrawable:drawable];
    [render addCompletedHandler:^(id<MTLCommandBuffer> buffer) {
        dispatch_async(dispatch_get_main_queue(), ^{
            PWViewController *owner = weakSelf;
            if (!owner || owner->_finished) return;
            owner->_inFlight = NO;
            BOOL gpuOK = decode.status == MTLCommandBufferStatusCompleted &&
                         buffer.status == MTLCommandBufferStatusCompleted;
            if (measuring) owner->_drain.onCompletion(gpuOK);
            if (!gpuOK) {
                [owner fail:[NSString stringWithFormat:@"GPU completion: %@ / %@", decode.error, buffer.error]];
                return;
            }
            if (measuring) {
                double milliseconds;
                if (PWElapsedMilliseconds(decode.GPUStartTime, decode.GPUEndTime, &milliseconds))
                    [owner->_gpuDecode addObject:@(milliseconds)];
                if (PWElapsedMilliseconds(buffer.GPUStartTime, buffer.GPUEndTime, &milliseconds))
                    [owner->_gpuRender addObject:@(milliseconds)];
            }
            [owner maybeFinishDrain];
        });
    }];
    [decode commit];
    [render commit];
    if (measuring) {
        double milliseconds;
        if (PWElapsedMilliseconds(cpuStart, CACurrentMediaTime(), &milliseconds))
            [_cpuSubmission addObject:@(milliseconds)];
    }
    if (_ticks % 60 == 0)
        _status.text = [NSString stringWithFormat:@"Pyrowave TV Probe | %@\n12/12 Vulkan comparisons PASS (≤2 LSB)\n%@ %lu/%lu | Presented %lu | Busy %lu",
                        fixture.name, measuring ? @"Measured" : @"Warmup",
                        (unsigned long)(measuring ? _ticks - _warmup : _ticks),
                        (unsigned long)(measuring ? _measured : _warmup),
                        (unsigned long)_drain.presented(), (unsigned long)_busyTicks];
    [self advance];
}
- (void)advance {
    _ticks++;
    if (_ticks >= _warmup + _measured) [self beginDrain];
}
- (void)beginDrain {
    if (_finished || _draining) return;
    _draining = YES;
    [_displayLink invalidate]; _displayLink = nil;
    [self maybeFinishDrain];
    if (_finished) return;
    __weak PWViewController *weakSelf = self;
    _drainTimer = [NSTimer timerWithTimeInterval:PWDrainTimeoutSeconds repeats:NO block:^(NSTimer *timer) {
        (void)timer;
        PWViewController *owner = weakSelf;
        if (!owner || owner->_finished) return;
        owner->_drainTimedOut = YES;
        NSString *timeout = [NSString stringWithFormat:@"Drain timed out after %.0f s: %llu GPU and %llu presentation callbacks pending",
                             PWDrainTimeoutSeconds, owner->_drain.pendingCompletions(),
                             owner->_drain.pendingPresentations()];
        owner->_failure = owner->_failure ? [owner->_failure stringByAppendingFormat:@"; %@", timeout] : timeout;
        [owner finish];
    }];
    [NSRunLoop.mainRunLoop addTimer:_drainTimer forMode:NSRunLoopCommonModes];
}
- (void)maybeFinishDrain {
    if (_draining && !_finished && _drain.drained()) [self finish];
}
- (void)fail:(NSString *)reason {
    if (_finished) return;
    if (!_failure) _failure = reason;
    [self beginDrain];
    [self maybeFinishDrain];
}
- (void)finish {
    if (_finished || (!_drain.drained() && !_drainTimedOut)) return;
    _finished = YES;
    _drain.freeze();
    [_drainTimer invalidate]; _drainTimer = nil;
    NSUInteger validationPasses = 0;
    for (NSDictionary *check in _checks) if ([check[@"passed"] boolValue]) validationPasses++;
    PWDrainOutcome outcome = _drain.outcome(_draining, _drainTimedOut, validationPasses,
                                           _busyTicks, _noDrawableTicks, _cadenceMisses);
    BOOL passed = _failure == nil && outcome == PWDrainOutcome::Passed;
    if (!passed && !_failure) _failure = @"Measured 60 Hz callback, submission, or presentation criteria failed";
    NSString *summary = passed ? @"PASS" : @"FAIL";
    double duration = std::isfinite(_measureStart) && _measureStart > 0 &&
                      std::isfinite(_measureEnd) && _measureEnd >= _measureStart
                          ? _measureEnd - _measureStart + 1.0 / 60.0 : NAN;
    if (!std::isfinite(duration) || duration <= 0) duration = NAN;
    double presentedFPS = _drain.presented() / duration;
    if (!std::isfinite(presentedFPS)) presentedFPS = NAN;
    uint64_t missed = _busyTicks + _noDrawableTicks + _cadenceMisses +
                      _drain.skippedPresentations + _drain.pendingPresentations();
    NSDictionary *counters = @{
        @"validation_passes": @(validationPasses),
        @"warmup_callback_target": @(_warmup), @"warmup_callbacks_observed": @(MIN(_ticks, _warmup)),
        @"measured_callback_target": @(_measured),
        @"measured_callbacks": @(_drain.callbacks), @"submitted_frames": @(_drain.submitted),
        @"completed_frames": @(_drain.completed), @"gpu_errors": @(_drain.gpuErrors),
        @"presentation_callbacks": @(_drain.presentationCallbacks),
        @"presented_drawables": @(_drain.presented()),
        @"skipped_presentations": @(_drain.skippedPresentations),
        @"presented_time_zero": @(_drain.zeroPresentationTimes),
        @"presented_time_unavailable": @(_drain.unavailablePresentationTimes),
        @"drawable_id_mismatches": @(_drain.drawableIDMismatches),
        @"unpresented_pending_callbacks": @(_drain.pendingPresentations()),
        @"pending_gpu_completions": @(_drain.pendingCompletions()),
        @"callback_accounting_complete": @(_drain.callbacks == _drain.target &&
                                            _drain.submitted == _drain.target && _drain.drained()),
        @"drain_timeout_seconds": @(PWDrainTimeoutSeconds), @"drain_timed_out": @(_drainTimedOut),
        @"busy_callbacks": @(_busyTicks),
        @"no_drawable_callbacks": @(_noDrawableTicks), @"cadence_missed_estimate": @(_cadenceMisses),
        @"missed_frame_estimate": @(missed),
        @"measured_duration_seconds": std::isfinite(duration) ? @(duration) : NSNull.null,
        @"observed_presented_fps": std::isfinite(presentedFPS) ? @(presentedFPS) : NSNull.null
    };
    NSMutableDictionary *report = [counters mutableCopy];
    [report addEntriesFromDictionary:@{
        @"schema_version": @1, @"program": @"Pyrowave TV Probe", @"passed": @(passed),
        @"failure": _failure ?: @"", @"pyrowave_commit": @"89f7e47d4abbf650c91fae766728af866c5e32a0",
        @"tolerance_lsb": @2, @"validation": _checks ?: @[],
        @"cpu_submission_ms": PWStats(_cpuSubmission, _drain.submitted, 0),
        @"gpu_decode_ms": PWStats(_gpuDecode, _drain.submitted, _drain.pendingCompletions()),
        @"gpu_render_ms": PWStats(_gpuRender, _drain.submitted, _drain.pendingCompletions()),
        @"presented_interval_ms": PWStats(_presentIntervals,
                                          _drain.presentationCallbacks > 0 ? _drain.presentationCallbacks - 1 : 0, 0)
    }];
    NSError *error = nil;
    NSData *counterJSON = [NSJSONSerialization dataWithJSONObject:counters options:NSJSONWritingSortedKeys error:&error];
    if (counterJSON) NSLog(@"Pyrowave final counters JSON: %@", [[NSString alloc] initWithData:counterJSON encoding:NSUTF8StringEncoding]);
    else NSLog(@"Pyrowave final counters serialization FAILED: %@", error);

    error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingSortedKeys error:&error];
    NSString *reportStatus;
    if (!json) {
        NSLog(@"Pyrowave report serialization FAILED: %@", error);
        reportStatus = [NSString stringWithFormat:@"Report serialization FAILED: %@", error.localizedDescription];
    } else {
        NSLog(@"Pyrowave report JSON: %@", [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding]);
        // Bounded lines survive console line limits; concatenate and base64-decode to recover the JSON.
        NSString *encoded = [json base64EncodedStringWithOptions:0];
        NSUInteger chunks = (encoded.length + 767) / 768;
        NSLog(@"Pyrowave report JSON base64 BEGIN bytes=%lu chunks=%lu", (unsigned long)json.length, (unsigned long)chunks);
        for (NSUInteger i = 0; i < chunks; ++i) {
            NSString *part = [encoded substringWithRange:NSMakeRange(i * 768, MIN(768, encoded.length - i * 768))];
            NSLog(@"Pyrowave report JSON base64 %lu/%lu: %@", (unsigned long)(i + 1), (unsigned long)chunks, part);
        }
        NSLog(@"Pyrowave report JSON base64 END");

        NSURL *caches = [NSFileManager.defaultManager URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask].firstObject;
        if (!caches) {
            reportStatus = @"Report directory FAILED: Library/Caches unavailable";
            NSLog(@"Pyrowave %@", reportStatus);
        } else if (![NSFileManager.defaultManager createDirectoryAtURL:caches withIntermediateDirectories:YES attributes:nil error:&error]) {
            NSLog(@"Pyrowave report directory FAILED: %@", error);
            reportStatus = [NSString stringWithFormat:@"Report directory FAILED: %@", error.localizedDescription];
        } else {
            NSURL *output = [caches URLByAppendingPathComponent:@"pyrowave-tv-probe-report.json"];
            error = nil;
            if (![json writeToURL:output options:NSDataWritingAtomic error:&error]) {
                NSLog(@"Pyrowave report write FAILED: %@", error);
                reportStatus = [NSString stringWithFormat:@"Report write FAILED: %@", error.localizedDescription];
            } else {
                NSLog(@"Pyrowave report %@ saved: %@", summary, output.path);
                reportStatus = @"Report saved: Library/Caches/pyrowave-tv-probe-report.json";
            }
        }
    }
    _status.text = [NSString stringWithFormat:@"Pyrowave TV Probe: %@\n%lu/12 Vulkan comparisons PASS (≤2 LSB)\n%lu/%lu presented (%@/s) | %lu missed estimate\nResult: %@\n%@",
                    summary, (unsigned long)validationPasses,
                    (unsigned long)_drain.presented(), (unsigned long)_drain.callbacks,
                    std::isfinite(presentedFPS) ? [NSString stringWithFormat:@"%.1f", presentedFPS] : @"unavailable",
                    (unsigned long)missed,
                    _failure ?: @"Measured criteria PASS", reportStatus];
}
@end

@interface PWAppDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow *window;
@end
@implementation PWAppDelegate
- (BOOL)application:(UIApplication *)application didFinishLaunchingWithOptions:(NSDictionary *)launchOptions {
    (void)application; (void)launchOptions;
    self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
    self.window.rootViewController = [PWViewController new];
    [self.window makeKeyAndVisible];
    return YES;
}
@end

int main(int argc, char *argv[]) {
    @autoreleasepool { return UIApplicationMain(argc, argv, nil, NSStringFromClass(PWAppDelegate.class)); }
}
