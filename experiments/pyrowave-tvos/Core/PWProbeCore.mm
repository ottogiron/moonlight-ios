#import "PWProbeCore.h"
#import "pyrowave_metal.h"
#import <CommonCrypto/CommonDigest.h>

#include <errno.h>
#include <stdlib.h>
#include <string.h>

static NSError *PWError(NSString *message) {
    return [NSError errorWithDomain:@"PyrowaveTVProbe" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}
static BOOL PWFail(NSError **error, NSString *message) {
    if (error) *error = PWError(message);
    return NO;
}
static BOOL PWNumber(id value, NSUInteger expected) {
    return [value isKindOfClass:NSNumber.class] && [value unsignedIntegerValue] == expected &&
           [value doubleValue] == (double)expected;
}
static NSString *PWSHA256(NSData *data) {
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *hex = [NSMutableString stringWithCapacity:64];
    for (unsigned char byte : digest) [hex appendFormat:@"%02x", byte];
    return hex;
}
static NSData *PWFile(NSURL *root, NSString *name, NSString *hash, NSError **error) {
    if (![name isKindOfClass:NSString.class] || !name.length ||
        ![[name lastPathComponent] isEqualToString:name] || [name isEqualToString:@"."] ||
        [name isEqualToString:@".."] || [name containsString:@"\\"] ||
        ![hash isKindOfClass:NSString.class] || hash.length != 64) {
        PWFail(error, @"Fixture filename or SHA-256 is invalid");
        return nil;
    }
    NSData *data = [NSData dataWithContentsOfURL:[root URLByAppendingPathComponent:name] options:0 error:error];
    if (!data) return nil;
    if (![PWSHA256(data) isEqualToString:hash]) {
        PWFail(error, [NSString stringWithFormat:@"SHA-256 mismatch: %@", name]);
        return nil;
    }
    return data;
}
static BOOL PWUnsigned(NSString *field, NSUInteger *value) {
    if (!field.length) return NO;
    for (NSUInteger i = 0; i < field.length; ++i)
        if ([field characterAtIndex:i] < '0' || [field characterAtIndex:i] > '9') return NO;
    errno = 0;
    unsigned long long parsed = strtoull(field.UTF8String, nullptr, 10);
    if (errno || parsed > NSUIntegerMax) return NO;
    *value = (NSUInteger)parsed;
    return YES;
}
static NSArray<NSValue *> *PWParseLayout(NSData *data, NSUInteger payloadSize, NSError **error) {
    NSString *csv = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
    csv = [csv stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
    NSArray<NSString *> *lines = [csv componentsSeparatedByString:@"\n"];
    if (!csv || lines.count < 2 || ![lines[0] isEqualToString:@"packet_index,offset,size"]) {
        PWFail(error, @"Packet CSV header is invalid");
        return nil;
    }
    NSMutableArray<NSValue *> *ranges = [NSMutableArray new];
    NSUInteger next = 0;
    for (NSUInteger lineNumber = 1; lineNumber < lines.count; lineNumber++) {
        NSString *line = lines[lineNumber];
        if (!line.length && lineNumber == lines.count - 1) continue;
        NSArray<NSString *> *fields = [line componentsSeparatedByString:@","];
        NSUInteger index, offset, size;
        if (fields.count != 3 || !PWUnsigned(fields[0], &index) ||
            !PWUnsigned(fields[1], &offset) || !PWUnsigned(fields[2], &size) ||
            index != ranges.count || offset != next || size == 0 ||
            offset > payloadSize || size > payloadSize - offset) {
            PWFail(error, [NSString stringWithFormat:@"Invalid packet CSV row %lu", (unsigned long)lineNumber]);
            return nil;
        }
        [ranges addObject:[NSValue valueWithRange:NSMakeRange(offset, size)]];
        next += size;
    }
    if (!ranges.count || next != payloadSize) {
        PWFail(error, @"Packet layout does not cover payload exactly");
        return nil;
    }
    return ranges;
}

@interface PWFixture ()
@property(nonatomic, readwrite) NSString *name;
@property(nonatomic, readwrite) NSUInteger width;
@property(nonatomic, readwrite) NSUInteger height;
@property(nonatomic, readwrite) NSData *packets;
@property(nonatomic, readwrite) NSData *reference;
@property(nonatomic, readwrite) NSArray<NSValue *> *ranges;
@end
@implementation PWFixture
@end

NSArray<PWFixture *> *PWLoadFixtures(NSURL *directory, NSError **error) {
    NSData *manifestData = [NSData dataWithContentsOfURL:[directory URLByAppendingPathComponent:@"manifest.json"] options:0 error:error];
    if (!manifestData) return nil;
    id manifest = [NSJSONSerialization JSONObjectWithData:manifestData options:0 error:error];
    if (![manifest isKindOfClass:NSDictionary.class]) { PWFail(error, @"Manifest must be an object"); return nil; }
    NSDictionary *m = manifest;
    if (!PWNumber(m[@"schema_version"], 1) ||
        ![m[@"pyrowave_commit"] isEqual:@"89f7e47d4abbf650c91fae766728af866c5e32a0"] ||
        (m[@"reference_precision"] && !PWNumber(m[@"reference_precision"], 1)) ||
        ![m[@"color_space"] isEqual:@"bt709"] || ![m[@"color_range"] isEqual:@"limited"] ||
        ![m[@"fixtures"] isKindOfClass:NSArray.class] || [m[@"fixtures"] count] != 6) {
        PWFail(error, @"Manifest schema, pin, color metadata, or fixture count is invalid"); return nil;
    }
    NSMutableSet<NSString *> *expected = [NSMutableSet new];
    for (NSString *kind in @[@"mixed", @"entropy"])
        for (NSString *rate in @[@"200", @"250", @"300"])
            [expected addObject:[NSString stringWithFormat:@"1920x1080_%@_%@", kind, rate]];
    NSMutableArray<PWFixture *> *fixtures = [NSMutableArray new];
    for (id entry in m[@"fixtures"]) {
        if (![entry isKindOfClass:NSDictionary.class]) { PWFail(error, @"Fixture entry must be an object"); return nil; }
        NSDictionary *f = entry;
        NSString *name = f[@"name"];
        if (![name isKindOfClass:NSString.class] || ![expected containsObject:name] ||
            !PWNumber(f[@"width"], 1920) || !PWNumber(f[@"height"], 1080) ||
            !PWNumber(f[@"chroma"], 420) || !PWNumber(f[@"frame_index"], 5) ||
            ![f[@"sha256"] isKindOfClass:NSDictionary.class]) {
            PWFail(error, @"Fixture identity or dimensions are invalid"); return nil;
        }
        [expected removeObject:name];
        NSDictionary *hashes = f[@"sha256"];
        NSString *packetName = f[@"packet_file"], *layoutName = f[@"packet_layout"], *referenceName = f[@"reference_file"];
        if (![packetName hasSuffix:@".packetized.bin"] || ![layoutName hasSuffix:@".packets.csv"] ||
            ![referenceName hasSuffix:@".vulkan-reference.yuv"]) {
            PWFail(error, @"Fixture file suffix is invalid"); return nil;
        }
        NSData *packets = PWFile(directory, packetName, hashes[@"packet_file"], error);
        NSData *layout = PWFile(directory, layoutName, hashes[@"packet_layout"], error);
        NSData *reference = PWFile(directory, referenceName, hashes[@"reference_file"], error);
        if (!packets || !layout || !reference) return nil;
        if (reference.length != 1920 * 1080 * 3 / 2 || packets.length > 128 * 1024 * 1024) {
            PWFail(error, @"Reference size or packet payload size is invalid"); return nil;
        }
        NSArray<NSValue *> *ranges = PWParseLayout(layout, packets.length, error);
        if (!ranges) return nil;
        PWFixture *fixture = [PWFixture new];
        fixture.name = name; fixture.width = 1920; fixture.height = 1080;
        fixture.packets = packets; fixture.reference = reference; fixture.ranges = ranges;
        [fixtures addObject:fixture];
    }
    if (expected.count) { PWFail(error, @"Expected fixture is missing or duplicated"); return nil; }
    return fixtures;
}

static const char *PWRenderMSL = R"msl(
#include <metal_stdlib>
using namespace metal;
struct Out { float4 position [[position]]; float2 uv; };
vertex Out pwVertex(uint vertexID [[vertex_id]]) {
    const float2 p[3] = {float2(-1,-1), float2(3,-1), float2(-1,3)};
    Out o; o.position = float4(p[vertexID], 0, 1);
    o.uv = float2((p[vertexID].x + 1) * 0.5, 1 - (p[vertexID].y + 1) * 0.5);
    return o;
}
float bt709ToLinear(float c) {
    c = clamp(c, 0.0, 1.0);
    return c < 0.081 ? c / 4.5 : pow((c + 0.099) / 1.099, 1.0 / 0.45);
}
fragment float4 pwFragment(Out in [[stage_in]],
                           texture2d<float> yTex [[texture(0)]],
                           texture2d<float> cbTex [[texture(1)]],
                           texture2d<float> crTex [[texture(2)]]) {
    constexpr sampler s(coord::normalized, address::clamp_to_edge, filter::linear);
    float y = (yTex.sample(s, in.uv).r * 255.0 - 16.0) / 219.0;
    float cb = (cbTex.sample(s, in.uv).r * 255.0 - 128.0) / 224.0;
    float cr = (crTex.sample(s, in.uv).r * 255.0 - 128.0) / 224.0;
    float3 encoded = float3(y + 1.5748 * cr,
                            y - 0.187324 * cb - 0.468124 * cr,
                            y + 1.8556 * cb);
    return float4(bt709ToLinear(encoded.r), bt709ToLinear(encoded.g),
                  bt709ToLinear(encoded.b), 1.0);
}
)msl";

@implementation PWProbeCore {
    pyrowave_device _device;
    pyrowave_decoder _decoder;
    NSUInteger _width, _height;
    id<MTLRenderPipelineState> _renderPipeline;
}
- (instancetype)initWithError:(NSError **)error {
    if (!(self = [super init])) return nil;
    _metalDevice = MTLCreateSystemDefaultDevice();
    if (!_metalDevice || !pyrowave_device_is_supported((__bridge void *)_metalDevice)) {
        PWFail(error, [NSString stringWithFormat:@"An Apple7 or newer Metal device is required (default device: %@, Apple7: %@)",
                       _metalDevice.name ?: @"none", _metalDevice && [_metalDevice supportsFamily:MTLGPUFamilyApple7] ? @"yes" : @"no"]);
        return nil;
    }
    pyrowave_device_create_info info = {};
    info.mtl_device = (__bridge void *)_metalDevice;
    // The paired Vulkan references were generated at precision 1.
    setenv("PYROWAVE_PRECISION", "1", 1);
    pyrowave_result result = pyrowave_device_create(&info, &_device);
    if (result != PYROWAVE_SUCCESS) {
        PWFail(error, [NSString stringWithFormat:@"Pyrowave shader/pipeline init: %s", pyrowave_result_to_string(result)]);
        return nil;
    }
    _queue = [_metalDevice newCommandQueue];
    if (!_queue) { PWFail(error, @"Could not create Metal command queue"); return nil; }
    return self;
}
- (void)dealloc {
    if (_decoder) pyrowave_decoder_destroy(_decoder);
    if (_device) pyrowave_device_destroy(_device);
}
- (BOOL)preparePlanes:(PWFixture *)fixture error:(NSError **)error {
    if (_decoder && _width == fixture.width && _height == fixture.height) return YES;
    if (_decoder) { pyrowave_decoder_destroy(_decoder); _decoder = nullptr; }
    pyrowave_decoder_create_info info = {_device, (int)fixture.width, (int)fixture.height, PYROWAVE_CHROMA_SUBSAMPLING_420};
    pyrowave_result result = pyrowave_decoder_create(&info, &_decoder);
    if (result != PYROWAVE_SUCCESS) return PWFail(error, [NSString stringWithFormat:@"Decoder creation: %s", pyrowave_result_to_string(result)]);
    NSMutableArray *planes = [NSMutableArray new];
    for (int i = 0; i < 3; ++i) {
        MTLTextureDescriptor *desc = [MTLTextureDescriptor texture2DDescriptorWithPixelFormat:MTLPixelFormatR8Unorm
                               width:fixture.width / (i ? 2 : 1) height:fixture.height / (i ? 2 : 1) mipmapped:NO];
        desc.usage = MTLTextureUsageShaderWrite | MTLTextureUsageShaderRead;
        desc.storageMode = MTLStorageModeShared;
        id<MTLTexture> plane = [_metalDevice newTextureWithDescriptor:desc];
        if (!plane) return PWFail(error, @"Could not allocate R8 output texture");
        [planes addObject:plane];
    }
    _planes = planes;
    _width = fixture.width; _height = fixture.height;
    return YES;
}
- (BOOL)encodeFixture:(PWFixture *)fixture commandBuffer:(id<MTLCommandBuffer>)commandBuffer error:(NSError **)error {
    if (!commandBuffer || ![self preparePlanes:fixture error:error]) return NO;
    pyrowave_decoder_clear(_decoder);
    const uint8_t *bytes = (const uint8_t *)fixture.packets.bytes;
    for (NSValue *value in fixture.ranges) {
        NSRange range = value.rangeValue;
        if (range.length == 0 || range.location > fixture.packets.length ||
            range.length > fixture.packets.length - range.location)
            return PWFail(error, @"Packet range exceeded payload");
        pyrowave_result result = pyrowave_decoder_push_packet(_decoder, bytes + range.location, range.length);
        if (result != PYROWAVE_SUCCESS)
            return PWFail(error, [NSString stringWithFormat:@"Packet rejected: %s", pyrowave_result_to_string(result)]);
    }
    if (!pyrowave_decoder_decode_is_ready(_decoder, false)) return PWFail(error, @"Whole frame is not ready");
    pyrowave_gpu_buffers output = {{(__bridge void *)_planes[0], (__bridge void *)_planes[1], (__bridge void *)_planes[2]}};
    pyrowave_result result = pyrowave_decoder_decode_gpu_buffer(_decoder, (__bridge void *)commandBuffer, &output);
    if (result != PYROWAVE_SUCCESS) return PWFail(error, [NSString stringWithFormat:@"GPU decode encode: %s", pyrowave_result_to_string(result)]);
    return YES;
}
- (NSDictionary *)verifyFixture:(PWFixture *)fixture error:(NSError **)error {
    id<MTLCommandBuffer> cmd = [_queue commandBuffer];
    if (!cmd || ![self encodeFixture:fixture commandBuffer:cmd error:error]) return nil;
    [cmd commit]; [cmd waitUntilCompleted];
    if (cmd.status != MTLCommandBufferStatusCompleted) {
        PWFail(error, [NSString stringWithFormat:@"GPU completion: %@", cmd.error.localizedDescription ?: @"unknown error"]); return nil;
    }
    NSMutableDictionary *results = [NSMutableDictionary new];
    NSMutableArray<NSString *> *failures = [NSMutableArray new];
    NSUInteger offset = 0;
    for (NSUInteger i = 0; i < 3; ++i) {
        NSUInteger width = fixture.width / (i ? 2 : 1), height = fixture.height / (i ? 2 : 1);
        NSUInteger size = width * height;
        NSMutableData *actual = [NSMutableData dataWithLength:size];
        [_planes[i] getBytes:actual.mutableBytes bytesPerRow:width fromRegion:MTLRegionMake2D(0, 0, width, height) mipmapLevel:0];
        const uint8_t *a = (const uint8_t *)actual.bytes;
        const uint8_t *r = (const uint8_t *)fixture.reference.bytes + offset;
        NSUInteger maxError = 0; uint64_t sum = 0;
        for (NSUInteger pixel = 0; pixel < size; ++pixel) {
            NSUInteger delta = (NSUInteger)abs((int)a[pixel] - (int)r[pixel]);
            if (delta > maxError) maxError = delta;
            sum += delta;
        }
        NSString *key = @[@"Y", @"Cb", @"Cr"][i];
        results[key] = @{ @"max_abs_error": @(maxError), @"mean_abs_error": @((double)sum / size),
                          @"within_tolerance": @(maxError <= 2) };
        offset += size;
        if (maxError > 2)
            [failures addObject:[NSString stringWithFormat:@"%@ max %lu mean %.4f", key, (unsigned long)maxError, (double)sum / size]];
    }
    if (failures.count) PWFail(error, [NSString stringWithFormat:@"Exceeds 2 LSB: %@", [failures componentsJoinedByString:@"; "]]);
    return results;
}
- (BOOL)prepareRendererWithPixelFormat:(MTLPixelFormat)format error:(NSError **)error {
    if (format != MTLPixelFormatBGRA8Unorm_sRGB) return PWFail(error, @"Renderer requires BGRA8Unorm_sRGB");
    NSError *compileError = nil;
    id<MTLLibrary> lib = [_metalDevice newLibraryWithSource:@(PWRenderMSL) options:nil error:&compileError];
    if (!lib) return PWFail(error, [NSString stringWithFormat:@"Render shader compile: %@", compileError.localizedDescription]);
    MTLRenderPipelineDescriptor *desc = [MTLRenderPipelineDescriptor new];
    desc.vertexFunction = [lib newFunctionWithName:@"pwVertex"];
    desc.fragmentFunction = [lib newFunctionWithName:@"pwFragment"];
    desc.colorAttachments[0].pixelFormat = format;
    _renderPipeline = [_metalDevice newRenderPipelineStateWithDescriptor:desc error:&compileError];
    if (!_renderPipeline) return PWFail(error, [NSString stringWithFormat:@"Render pipeline init: %@", compileError.localizedDescription]);
    return YES;
}
- (BOOL)encodeRender:(id<MTLCommandBuffer>)commandBuffer drawable:(id<CAMetalDrawable>)drawable error:(NSError **)error {
    if (!_renderPipeline || !drawable || drawable.texture.pixelFormat != MTLPixelFormatBGRA8Unorm_sRGB || _planes.count != 3)
        return PWFail(error, @"Render pipeline, drawable, or YCbCr planes are invalid");
    MTLRenderPassDescriptor *pass = MTLRenderPassDescriptor.renderPassDescriptor;
    pass.colorAttachments[0].texture = drawable.texture;
    pass.colorAttachments[0].loadAction = MTLLoadActionClear;
    pass.colorAttachments[0].storeAction = MTLStoreActionStore;
    pass.colorAttachments[0].clearColor = MTLClearColorMake(0, 0, 0, 1);
    id<MTLRenderCommandEncoder> encoder = [commandBuffer renderCommandEncoderWithDescriptor:pass];
    if (!encoder) return PWFail(error, @"Could not create render encoder");
    [encoder setRenderPipelineState:_renderPipeline];
    for (NSUInteger i = 0; i < 3; ++i) [encoder setFragmentTexture:_planes[i] atIndex:i];
    [encoder drawPrimitives:MTLPrimitiveTypeTriangle vertexStart:0 vertexCount:3];
    [encoder endEncoding];
    return YES;
}
@end
