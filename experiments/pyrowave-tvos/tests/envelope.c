#include "../../../Limelight/Stream/PyrowaveEnvelope.h"

#include <assert.h>
#include <limits.h>
#include <string.h>

static unsigned char frame[PW_MAX_FRAME_BYTES + 1];
static unsigned char assembled[PW_MAX_RECORD_BYTES + 36];
static PWPacketRange ranges[PW_MAX_PACKETS];

static void u16(unsigned char *p, unsigned value) { p[0] = value >> 8; p[1] = value; }
static void u32(unsigned char *p, unsigned value) {
    p[0] = value >> 24; p[1] = value >> 16; p[2] = value >> 8; p[3] = value;
}

static size_t makeFrame(const unsigned *sizes, size_t records) {
    size_t length = 32;
    memset(frame, 0, sizeof(frame));
    memcpy(frame, "PWR2", 4);
    u16(frame + 4, 2); u16(frame + 6, 32);
    u32(frame + 8, 7);
    u16(frame + 16, 3840); u16(frame + 18, 2160);
    u16(frame + 20, (unsigned)records); u16(frame + 22, 1);
    u32(frame + 24, 1);
    for (size_t i = 0; i < records; ++i) {
        assert(length + 4 + sizes[i] <= sizeof(frame));
        u32(frame + length, sizes[i]);
        length += 4;
        memset(frame + length, (int)(i + 1), sizes[i]);
        length += sizes[i];
    }
    u32(frame + 12, (unsigned)length);
    return length;
}

static bool parse(size_t length, size_t cap, size_t *count) {
    return PWParseEnvelope(frame, length, 3840, 2160, 7, cap, ranges, count);
}

static void testHeaders(void) {
    const unsigned sizes[] = {1, 1};
    size_t length = makeFrame(sizes, 2), count = 0;
    assert(length == 42);
    assert(parse(length, length, &count));
    assert(count == 2 && ranges[0].offset == 36 && ranges[0].length == 1);
    assert(ranges[1].offset == 41 && ranges[1].length == 1);
    assert(!parse(length - 1, length, &count));
    assert(!parse(length + 1, length + 1, &count));
    assert(!parse(length, length - 1, &count));
    assert(!PWParseEnvelope(frame, length, 1920, 1080, 7, length, ranges, &count));
    assert(!PWParseEnvelope(frame, length, 3840, 2160, 8, length, ranges, &count));
    assert(!parse(PW_MAX_FRAME_BYTES + 1, PW_MAX_FRAME_BYTES + 1, &count));
    memcpy(frame, "PWR1", 4); assert(!parse(length, length, &count));
    memcpy(frame, "PWR2", 4); u16(frame + 4, 1); assert(!parse(length, length, &count));
    u16(frame + 4, 2); u16(frame + 6, 31); assert(!parse(length, length, &count));
    u16(frame + 6, 32); u16(frame + 22, 3); assert(!parse(length, length, &count));
    u16(frame + 22, 1); u32(frame + 24, 2); assert(!parse(length, length, &count));
    u32(frame + 24, 1); frame[28] = 1; assert(!parse(length, length, &count));
    frame[28] = 0; u16(frame + 20, 1025); assert(!parse(length, length, &count));
    u16(frame + 20, 0); assert(!parse(length, length, &count));
    u16(frame + 20, 2); u32(frame + 37, 0); assert(!parse(length, length, &count));
    u32(frame + 37, 2); assert(!parse(length, length, &count));
}

static void testRecordLimits(void) {
    const unsigned medium[] = {1201};
    size_t length = makeFrame(medium, 1), count = 0;
    assert(parse(length, length, &count));
    assert(count == 1 && ranges[0].length == 1201);

    const unsigned maximum[] = {PW_MAX_RECORD_BYTES};
    length = makeFrame(maximum, 1);
    assert(parse(length, length, &count));
    assert(count == 1 && ranges[0].length == PW_MAX_RECORD_BYTES);

    const unsigned tooLarge[] = {PW_MAX_RECORD_BYTES + 1};
    length = makeFrame(tooLarge, 1);
    assert(!parse(length, length, &count));

    unsigned many[PW_MAX_PACKETS];
    for (size_t i = 0; i < PW_MAX_PACKETS; ++i) many[i] = 1;
    length = makeFrame(many, PW_MAX_PACKETS);
    assert(parse(length, length, &count) && count == PW_MAX_PACKETS);
}

static void testStreamGeometry(void) {
    const unsigned sizes[] = {1201};
    size_t length = makeFrame(sizes, 1), count = 0;
    assert(PWLiveDimensionsSupported(1920, 1080));
    assert(PWLiveDimensionsSupported(2560, 1440));
    assert(PWLiveDimensionsSupported(3840, 2160));
    assert(!PWLiveDimensionsSupported(1280, 720));
    assert(!PWLiveDimensionsSupported(2560, 1080));

    u16(frame + 16, 2560); u16(frame + 18, 1440);
    assert(PWParseEnvelope(frame, length, 2560, 1440, 7, length, ranges, &count));
    assert(count == 1 && ranges[0].length == 1201);
    assert(!PWParseEnvelope(frame, length, 3840, 2160, 7, length, ranges, &count));
    u16(frame + 22, 2);
    assert(!PWParseEnvelope(frame, length, 2560, 1440, 7, length, ranges, &count));
    u16(frame + 22, 1);
    u16(frame + 16, 1920); u16(frame + 18, 1080);
    assert(PWParseEnvelope(frame, length, 1920, 1080, 7, length, ranges, &count));
    u16(frame + 16, 1280); u16(frame + 18, 720);
    assert(!PWParseEnvelope(frame, length, 1280, 720, 7, length, ranges, &count));
}

static void testFragmentedDecodeUnit(void) {
    const unsigned maximum[] = {PW_MAX_RECORD_BYTES};
    size_t length = makeFrame(maximum, 1), offset = 0, count = 0;
    // Model common-c DECODE_UNIT entries: a codec record crosses many
    // transport-sized fragments, then the complete frame reaches the parser.
    for (size_t source = 0; source < length; ) {
        size_t fragmentLength = length - source < 1137 ? length - source : 1137;
        assert(PWAppendFragment(assembled, length, &offset, frame + source, fragmentLength));
        source += fragmentLength;
    }
    assert(offset == length && memcmp(assembled, frame, length) == 0);
    assert(PWParseEnvelope(assembled, length, 3840, 2160, 7, length, ranges, &count));
    assert(count == 1 && ranges[0].offset == 36 && ranges[0].length == PW_MAX_RECORD_BYTES);
    assert(!PWAppendFragment(assembled, length, &offset, frame, 1));
    assert(!PWAppendFragment(assembled, length, &offset, frame, 0));
}

static void testBitrateCaps(void) {
    size_t cap100 = PWFrameCapForBitrate(100000, 60);
    size_t cap150 = PWFrameCapForBitrate(150000, 60);
    size_t cap200 = PWFrameCapForBitrate(200000, 60);
    assert(cap100 == 212462 && cap150 == 316628 && cap200 == 420795);
    assert(cap100 < cap150 && cap150 < cap200);
    assert(PWFrameCapForBitrate(300000, 60) == 629128);
    assert(PWFrameCapForBitrate(500000, 60) == 1045795);
    assert(PWFrameCapForBitrate(500000, 60) < PW_MAX_FRAME_BYTES);
    assert(PWFrameCapForBitrate(0, 60) == 0);
    assert(PWFrameCapForBitrate(-1, 60) == 0);
    assert(PWFrameCapForBitrate(100000, 0) == 0);
    assert(PWFrameCapForBitrate(100000, -1) == 0);
    assert(PWFrameCapForBitrate(INT_MAX, 1) == PW_MAX_FRAME_BYTES);

    const unsigned four[] = {65536, 65536, 65536, 65536};
    size_t length = makeFrame(four, 4), count = 0;
    assert(length > cap100 && length < cap150);
    assert(!parse(length, cap100, &count));
    assert(parse(length, cap150, &count) && count == 4);

    const unsigned six[] = {65536, 65536, 65536, 65536, 65536, 65536};
    length = makeFrame(six, 6);
    assert(length > cap150 && length < cap200);
    assert(!parse(length, cap150, &count));
    assert(parse(length, cap200, &count) && count == 6);
}

int main(void) {
    testHeaders();
    testRecordLimits();
    testStreamGeometry();
    testFragmentedDecodeUnit();
    testBitrateCaps();
    return 0;
}
