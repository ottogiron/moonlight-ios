#import "PyrowaveLiveRenderer.h"
#import "ConnectionCallbacks.h"

#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>
#import "pyrowave_metal.h"

BOOL PyrowaveLiveDecoderSupported(void) {
    id<MTLDevice> device = MTLCreateSystemDefaultDevice();
    return device && pyrowave_device_is_supported((__bridge void *)device);
}

// Color profile 1: full range BT.709 matrix, nonlinear sRGB, center 4:2:0.
// The sRGB drawable applies the forward transfer after this shader returns linear RGB.
static const char *PWLiveMSL = R"msl(
#include <metal_stdlib>
using namespace metal;
struct Out { float4 position [[position]]; float2 uv; };
vertex Out pwLiveVertex(uint index [[vertex_id]]) {
    const float2 p[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    Out o; o.position = float4(p[index], 0, 1);
    o.uv = float2((p[index].x + 1) * 0.5, 1 - (p[index].y + 1) * 0.5);
    return o;
}
float srgbToLinear(float c) {
    c = clamp(c, 0.0, 1.0);
    return c <= 0.04045 ? c / 12.92 : pow((c + 0.055) / 1.055, 2.4);
}
fragment float4 pwLiveFragment(Out in [[stage_in]],
    texture2d<float> yTex [[texture(0)]], texture2d<float> cbTex [[texture(1)]],
    texture2d<float> crTex [[texture(2)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float y = yTex.sample(s, in.uv).r;
    float cb = cbTex.sample(s, in.uv).r - 128.0 / 255.0;
    float cr = crTex.sample(s, in.uv).r - 128.0 / 255.0;
    float3 rgb = float3(y + 1.5748 * cr,
                        y - 0.187324 * cb - 0.468124 * cr,
                        y + 1.8556 * cb);
    return float4(srgbToLinear(rgb.r), srgbToLinear(rgb.g), srgbToLinear(rgb.b), 1);
}
)msl";

@implementation PyrowaveLiveRenderer {
    UIView *_view;
    id<ConnectionCallbacks> _callbacks;
    id<MTLDevice> _metalDevice;
    id<MTLCommandQueue> _queue;
    id<MTLRenderPipelineState> _pipeline;
    CAMetalLayer *_layer;
    NSArray<id<MTLTexture>> *_planes;
    pyrowave_device _device;
    pyrowave_decoder _decoder;
    id<MTLCommandBuffer> _inFlight;
    BOOL _stopped;
    BOOL _contentShown;
    NSUInteger _width, _height;
}

- (instancetype)initWithView:(UIView *)view width:(NSUInteger)width height:(NSUInteger)height
                   callbacks:(id<ConnectionCallbacks>)callbacks {
    if (!(self = [super init])) return nil;
    if (![NSThread isMainThread] || !view || !callbacks || !width || !height ||
        (width & 1) || (height & 1) || width > 3840 || height > 2160) return nil;
    _view = view; _callbacks = callbacks; _width = width; _height = height;
    _metalDevice = MTLCreateSystemDefaultDevice();
    if (!_metalDevice || !pyrowave_device_is_supported((__bridge void *)_metalDevice)) return nil;
    pyrowave_device_create_info deviceInfo = {};
    deviceInfo.mtl_device = (__bridge void *)_metalDevice;
    if (pyrowave_device_create(&deviceInfo, &_device) != PYROWAVE_SUCCESS) return nil;
    pyrowave_decoder_create_info decoderInfo = {_device, (int)width, (int)height,
                                                  PYROWAVE_CHROMA_SUBSAMPLING_420};
    if (pyrowave_decoder_create(&decoderInfo, &_decoder) != PYROWAVE_SUCCESS) return nil;
    _queue = [_metalDevice newCommandQueue];
    NSMutableArray *planes = [NSMutableArray arrayWithCapacity:3];
    for (NSUInteger i = 0; i < 3; ++i) {
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
            width:width / (i ? 2 : 1) height:height / (i ? 2 : 1) mipmapped:NO];
        desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
        desc.storageMode = MTLStorageModePrivate;
        id<MTLTexture> plane = [_metalDevice newTextureWithDescriptor:desc];
        if (!plane) return nil;
        [planes addObject:plane];
    }
    _planes = planes;
    NSError *error = nil;
    id<MTLLibrary> library = [_metalDevice newLibraryWithSource:@(PWLiveMSL) options:nil error:&error];
    MTLRenderPipelineDescriptor *pipeline = [MTLRenderPipelineDescriptor new];
    pipeline.vertexFunction = [library newFunctionWithName:@"pwLiveVertex"];
    pipeline.fragmentFunction = [library newFunctionWithName:@"pwLiveFragment"];
    pipeline.colorAttachments[0].pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    if (!pipeline.vertexFunction || !pipeline.fragmentFunction ||
        !(_pipeline = [_metalDevice newRenderPipelineStateWithDescriptor:pipeline error:&error]) || !_queue) {
        NSLog(@"Experimental video Metal pipeline failed: %@", error);
        return nil;
    }
    _layer = [CAMetalLayer layer];
    _layer.device = _metalDevice;
    _layer.pixelFormat = MTLPixelFormatBGRA8Unorm_sRGB;
    CGColorSpaceRef colorSpace = CGColorSpaceCreateWithName(kCGColorSpaceSRGB);
    _layer.colorspace = colorSpace;
    CGColorSpaceRelease(colorSpace);
    _layer.framebufferOnly = YES;
    _layer.opaque = YES;
    _layer.hidden = YES;
    [self updateLayerSize];
    [_view.layer addSublayer:_layer];
    return self;
}

- (void)updateLayerSize {
    CGFloat aspect = (CGFloat)_width / _height;
    CGRect bounds = _view.bounds;
    CGFloat h = MIN(bounds.size.height, bounds.size.width / aspect);
    CGFloat w = h * aspect;
    _layer.frame = CGRectMake((bounds.size.width - w) / 2, (bounds.size.height - h) / 2, w, h);
    CGFloat scale = UIScreen.mainScreen.scale;
    _layer.contentsScale = scale;
    _layer.drawableSize = CGSizeMake(w * scale, h * scale);
}

- (BOOL)submitFrame:(const uint8_t *)bytes length:(size_t)length
             ranges:(const PWPacketRange *)ranges count:(size_t)count {
    if (_stopped || _inFlight || !bytes || !ranges || !count || count > PW_MAX_PACKETS) return NO;
    [self updateLayerSize];
    id<CAMetalDrawable> drawable = [_layer nextDrawable];
    id<MTLCommandBuffer> command = [_queue commandBuffer];
    if (!drawable || !command) return NO;
    pyrowave_decoder_clear(_decoder);
    for (size_t i = 0; i < count; ++i) {
        if (ranges[i].offset > length || ranges[i].length > length - ranges[i].offset ||
            pyrowave_decoder_push_packet(_decoder, bytes + ranges[i].offset, ranges[i].length) != PYROWAVE_SUCCESS) {
            pyrowave_decoder_clear(_decoder);
            return NO;
        }
    }
    if (!pyrowave_decoder_decode_is_ready(_decoder, false)) {
        pyrowave_decoder_clear(_decoder);
        return NO;
    }
    pyrowave_gpu_buffers output = {{(__bridge void *)_planes[0], (__bridge void *)_planes[1],
                                     (__bridge void *)_planes[2]}};
    if (pyrowave_decoder_decode_gpu_buffer(_decoder, (__bridge void *)command, &output) != PYROWAVE_SUCCESS) {
        pyrowave_decoder_clear(_decoder);
        return NO;
    }
    MTLRenderPassDescriptor *pass = MTLRenderPassDescriptor.renderPassDescriptor;
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLRenderCommandEncoder> render = [command renderCommandEncoderWithDescriptor:pass];
    if (!render) return NO;
    [render setRenderPipelineState:_pipeline];
    for (NSUInteger i = 0; i < 3; ++i) [render setFragmentTexture:_planes[i] atIndex:i];
    [render drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [render endEncoding];
    __weak PyrowaveLiveRenderer *weakSelf = self;
    [drawable addPresentedHandler:^(id<MTLDrawable> presented) {
        dispatch_async(dispatch_get_main_queue(), ^{
            PyrowaveLiveRenderer *owner = weakSelf;
            if (owner && !owner->_stopped && !owner->_contentShown) {
                owner->_contentShown = YES;
                owner->_layer.hidden = NO;
                [owner->_callbacks videoContentShown];
            }
        });
    }];
    [command presentDrawable:drawable];
    _inFlight = command;
    [command addCompletedHandler:^(id<MTLCommandBuffer> completed) {
        dispatch_async(dispatch_get_main_queue(), ^{
            PyrowaveLiveRenderer *owner = weakSelf;
            if (owner && owner->_inFlight == completed) owner->_inFlight = nil;
        });
    }];
    [command commit];
    return YES;
}

- (void)stop {
    _stopped = YES;
    if (_inFlight) [_inFlight waitUntilCompleted];
    _inFlight = nil;
    [_layer removeFromSuperlayer];
    _layer = nil;
    if (_decoder) { pyrowave_decoder_destroy(_decoder); _decoder = nullptr; }
    if (_device) { pyrowave_device_destroy(_device); _device = nullptr; }
}

- (void)dealloc {
    // A failed initialization has no drawable or in-flight command buffer.
    if (_decoder) pyrowave_decoder_destroy(_decoder);
    if (_device) pyrowave_device_destroy(_device);
}
@end
