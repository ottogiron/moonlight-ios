#import <UIKit/UIKit.h>
#import <QuartzCore/QuartzCore.h>
#import "PWProbeCore.h"
#include "PWDrainTracker.hpp"

static const NSTimeInterval PWDrainTimeoutSeconds = 3.0;

static double PWMean(NSArray<NSNumber *> *values) {
    double total = 0;
    for (NSNumber *n in values) total += n.doubleValue;
    return values.count ? total / values.count : 0;
}
static double PWMax(NSArray<NSNumber *> *values) {
    double maximum = 0;
    for (NSNumber *n in values) maximum = MAX(maximum, n.doubleValue);
    return maximum;
}

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
    _status = [[UILabel alloc] initWithFrame:CGRectMake(60, 50, 1800, 180)];
    _status.autoresizingMask = UIViewAutoresizingFlexibleWidth;
    _status.numberOfLines = 4;
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
    [drawable addPresentedHandler:^(id<MTLDrawable> presentedDrawable) {
        dispatch_async(dispatch_get_main_queue(), ^{
            PWViewController *owner = weakSelf;
            if (!owner || owner->_finished || !measuring) return;
            owner->_drain.onPresentation(presentedDrawable.presentedTime > 0);
            if (presentedDrawable.presentedTime > 0) {
                if (owner->_lastPresentation > 0) {
                    double interval = presentedDrawable.presentedTime - owner->_lastPresentation;
                    [owner->_presentIntervals addObject:@(interval * 1000.0)];
                }
                owner->_lastPresentation = presentedDrawable.presentedTime;
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
                if (decode.GPUStartTime > 0 && decode.GPUEndTime >= decode.GPUStartTime)
                    [owner->_gpuDecode addObject:@((decode.GPUEndTime - decode.GPUStartTime) * 1000.0)];
                if (buffer.GPUStartTime > 0 && buffer.GPUEndTime >= buffer.GPUStartTime)
                    [owner->_gpuRender addObject:@((buffer.GPUEndTime - buffer.GPUStartTime) * 1000.0)];
            }
            [owner maybeFinishDrain];
        });
    }];
    [decode commit];
    [render commit];
    if (measuring) [_cpuSubmission addObject:@((CACurrentMediaTime() - cpuStart) * 1000.0)];
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
    double duration = _measureEnd > _measureStart ? _measureEnd - _measureStart + 1.0 / 60.0 : 0;
    uint64_t missed = _busyTicks + _noDrawableTicks + _cadenceMisses +
                      _drain.skippedPresentations + _drain.pendingPresentations();
    NSDictionary *report = @{
        @"schema_version": @1, @"program": @"Pyrowave TV Probe", @"passed": @(passed),
        @"failure": _failure ?: @"", @"pyrowave_commit": @"89f7e47d4abbf650c91fae766728af866c5e32a0",
        @"tolerance_lsb": @2, @"validation": _checks ?: @[],
        @"warmup_callback_target": @(_warmup), @"warmup_callbacks_observed": @(MIN(_ticks, _warmup)),
        @"measured_callback_target": @(_measured),
        @"measured_callbacks": @(_drain.callbacks), @"submitted_frames": @(_drain.submitted),
        @"completed_frames": @(_drain.completed), @"gpu_errors": @(_drain.gpuErrors),
        @"presentation_callbacks": @(_drain.presentationCallbacks),
        @"presented_drawables": @(_drain.presented()),
        @"skipped_presentations": @(_drain.skippedPresentations),
        @"unpresented_pending_callbacks": @(_drain.pendingPresentations()),
        @"pending_gpu_completions": @(_drain.pendingCompletions()),
        @"callback_accounting_complete": @(_drain.callbacks == _drain.target &&
                                            _drain.submitted == _drain.target && _drain.drained()),
        @"drain_timeout_seconds": @(PWDrainTimeoutSeconds), @"drain_timed_out": @(_drainTimedOut),
        @"busy_callbacks": @(_busyTicks),
        @"no_drawable_callbacks": @(_noDrawableTicks), @"cadence_missed_estimate": @(_cadenceMisses),
        @"missed_frame_estimate": @(missed),
        @"measured_duration_seconds": @(duration),
        @"observed_presented_fps": @(duration > 0 ? _drain.presented() / duration : 0),
        @"cpu_submission_ms": @{ @"samples": @(_cpuSubmission.count), @"mean": @(PWMean(_cpuSubmission)), @"max": @(PWMax(_cpuSubmission)) },
        @"gpu_decode_ms": @{ @"samples": @(_gpuDecode.count), @"mean": @(PWMean(_gpuDecode)), @"max": @(PWMax(_gpuDecode)) },
        @"gpu_render_ms": @{ @"samples": @(_gpuRender.count), @"mean": @(PWMean(_gpuRender)), @"max": @(PWMax(_gpuRender)) },
        @"presented_interval_ms": @{ @"samples": @(_presentIntervals.count), @"mean": @(PWMean(_presentIntervals)), @"max": @(PWMax(_presentIntervals)) }
    };
    NSError *error = nil;
    NSData *json = [NSJSONSerialization dataWithJSONObject:report options:NSJSONWritingPrettyPrinted error:&error];
    NSURL *documents = [NSFileManager.defaultManager URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *output = [documents URLByAppendingPathComponent:@"pyrowave-tv-probe-report.json"];
    if (![json writeToURL:output options:NSDataWritingAtomic error:&error]) NSLog(@"Pyrowave report write FAILED: %@", error);
    else NSLog(@"Pyrowave report %@: %@", summary, output.path);
    _status.text = [NSString stringWithFormat:@"Pyrowave TV Probe: %@\n%lu/12 Vulkan comparisons PASS (≤2 LSB)\n%lu/%lu presented (%.1f/s) | %lu missed estimate\n%@",
                    summary, (unsigned long)validationPasses,
                    (unsigned long)_drain.presented(), (unsigned long)_drain.callbacks,
                    duration > 0 ? _drain.presented() / duration : 0,
                    (unsigned long)missed,
                    _failure ?: @"Report saved in Documents/pyrowave-tv-probe-report.json"];
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
