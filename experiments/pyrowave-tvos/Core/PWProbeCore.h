#import <Foundation/Foundation.h>
#import <Metal/Metal.h>
#import <QuartzCore/CAMetalLayer.h>

NS_ASSUME_NONNULL_BEGIN

@interface PWFixture : NSObject
@property(nonatomic, readonly) NSString *name;
@property(nonatomic, readonly) NSUInteger width;
@property(nonatomic, readonly) NSUInteger height;
@property(nonatomic, readonly) NSData *packets;
@property(nonatomic, readonly) NSData *reference;
@property(nonatomic, readonly) NSArray<NSValue *> *ranges;
@end

NSArray<PWFixture *> * _Nullable PWLoadFixtures(NSURL *directory, NSError **error);

@interface PWProbeCore : NSObject
@property(nonatomic, readonly) id<MTLDevice> metalDevice;
@property(nonatomic, readonly) id<MTLCommandQueue> queue;
@property(nonatomic, readonly) NSArray<id<MTLTexture>> *planes;
- (nullable instancetype)initWithError:(NSError **)error;
- (BOOL)encodeFixture:(PWFixture *)fixture commandBuffer:(id<MTLCommandBuffer>)commandBuffer error:(NSError **)error;
- (nullable NSDictionary *)verifyFixture:(PWFixture *)fixture error:(NSError **)error;
- (BOOL)prepareRendererWithPixelFormat:(MTLPixelFormat)format error:(NSError **)error;
- (BOOL)encodeRender:(id<MTLCommandBuffer>)commandBuffer drawable:(id<CAMetalDrawable>)drawable error:(NSError **)error;
@end

NS_ASSUME_NONNULL_END
