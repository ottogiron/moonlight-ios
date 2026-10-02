#include "PyrowaveEnvelope.h"

#include <string.h>

static uint16_t be16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] << 8 | p[1]);
}

static uint32_t be32(const uint8_t *p) {
    return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 |
           (uint32_t)p[2] << 8 | p[3];
}

bool PWParseEnvelope(const uint8_t *input, size_t length, uint16_t width,
                     uint16_t height, uint32_t frameNumber, size_t frameCap,
                     PWPacketRange ranges[PW_MAX_PACKETS], size_t *count) {
    if (!input || !ranges || !count || length < 32 || length > PW_MAX_FRAME_BYTES ||
        length > frameCap || !frameNumber || !width || !height ||
        memcmp(input, "PWR1", 4) || be16(input + 4) != 1 ||
        be16(input + 6) != 32 || be32(input + 8) != frameNumber ||
        be32(input + 12) != length || be16(input + 16) != width ||
        be16(input + 18) != height || be16(input + 22) != 1 ||
        be32(input + 24) != 1 || be32(input + 28) != 0) return false;

    size_t packets = be16(input + 20);
    if (!packets || packets > PW_MAX_PACKETS || packets > (length - 32) / 5) return false;
    size_t offset = 32;
    for (size_t i = 0; i < packets; ++i) {
        if (length - offset < 4) return false;
        size_t size = be32(input + offset);
        offset += 4;
        if (!size || size > 1200 || size > length - offset) return false;
        ranges[i] = (PWPacketRange){offset, size};
        offset += size;
    }
    if (offset != length) return false;
    *count = packets;
    return true;
}
