#include "../../../Limelight/Stream/PyrowaveEnvelope.h"

#include <assert.h>
#include <string.h>

static void u16(unsigned char *p, unsigned value) { p[0] = value >> 8; p[1] = value; }
static void u32(unsigned char *p, unsigned value) {
    p[0] = value >> 24; p[1] = value >> 16; p[2] = value >> 8; p[3] = value;
}

int main(void) {
    unsigned char frame[42] = {0};
    memcpy(frame, "PWR1", 4);
    u16(frame + 4, 1); u16(frame + 6, 32);
    u32(frame + 8, 7); u32(frame + 12, sizeof(frame));
    u16(frame + 16, 3840); u16(frame + 18, 2160);
    u16(frame + 20, 2); u16(frame + 22, 1); u32(frame + 24, 1);
    u32(frame + 32, 1); frame[36] = 0xa5;
    u32(frame + 37, 1); frame[41] = 0x5a;
    PWPacketRange ranges[PW_MAX_PACKETS]; size_t count = 0;
    assert(PWParseEnvelope(frame, sizeof(frame), 3840, 2160, 7, 50000, ranges, &count));
    assert(count == 2 && ranges[0].offset == 36 && ranges[1].offset == 41);
    assert(!PWParseEnvelope(frame, 41, 3840, 2160, 7, 50000, ranges, &count));
    unsigned char trailing[43]; memcpy(trailing, frame, sizeof(frame)); trailing[42] = 0;
    assert(!PWParseEnvelope(trailing, sizeof(trailing), 3840, 2160, 7, 50000, ranges, &count));
    assert(!PWParseEnvelope(frame, PW_MAX_FRAME_BYTES + 1, 3840, 2160, 7,
                            PW_MAX_FRAME_BYTES + 1, ranges, &count));
    assert(!PWParseEnvelope(frame, sizeof(frame), 1920, 1080, 7, 50000, ranges, &count));
    assert(!PWParseEnvelope(frame, sizeof(frame), 3840, 2160, 8, 50000, ranges, &count));
    assert(!PWParseEnvelope(frame, sizeof(frame), 3840, 2160, 7, 41, ranges, &count));
    u16(frame + 22, 3);
    assert(!PWParseEnvelope(frame, sizeof(frame), 3840, 2160, 7, 50000, ranges, &count));
    u16(frame + 22, 1); u32(frame + 37, 1201);
    assert(!PWParseEnvelope(frame, sizeof(frame), 3840, 2160, 7, 50000, ranges, &count));
    u32(frame + 37, 1); u16(frame + 20, 1025);
    assert(!PWParseEnvelope(frame, sizeof(frame), 3840, 2160, 7, 50000, ranges, &count));
    u16(frame + 20, 2); u32(frame + 24, 2);
    assert(!PWParseEnvelope(frame, sizeof(frame), 3840, 2160, 7, 50000, ranges, &count));
    u32(frame + 24, 1); frame[28] = 1;
    assert(!PWParseEnvelope(frame, sizeof(frame), 3840, 2160, 7, 50000, ranges, &count));
    frame[28] = 0; u32(frame + 8, 8);
    assert(PWParseEnvelope(frame, sizeof(frame), 3840, 2160, 8, 50000, ranges, &count));
    return 0;
}
