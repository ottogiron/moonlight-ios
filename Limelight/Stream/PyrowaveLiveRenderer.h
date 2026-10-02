#import <UIKit/UIKit.h>

#include "PyrowaveEnvelope.h"

@protocol ConnectionCallbacks;

#ifdef __cplusplus
extern "C" {
#endif
BOOL PyrowaveLiveDecoderSupported(void);
#ifdef __cplusplus
}
#endif

@interface PyrowaveLiveRenderer : NSObject
- (instancetype)initWithView:(UIView *)view width:(NSUInteger)width height:(NSUInteger)height
                   callbacks:(id<ConnectionCallbacks>)callbacks;
- (BOOL)submitFrame:(const uint8_t *)bytes length:(size_t)length
             ranges:(const PWPacketRange *)ranges count:(size_t)count;
- (void)stop;
@end
