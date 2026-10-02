#include "PyrowaveEnvelope.h"

#include <string.h>

static uint16_t be16(const uint8_t *p) {
    return (uint16_t)((uint16_t)p[0] << 8 | p[1]);
}

static uint32_t be32(const uint8_t *p) {
    return (uint32_t)p[0] << 24 | (uint32_t)p[1] << 16 |
           (uint32_t)p[2] << 8 | p[3];
}

size_t PWFrameCapForBitrate(int bitrateKbps, int frameRate) {
    if (bitrateKbps <= 0 || frameRate <= 0) return 0;
    uint64_t bitsPerSecond = (uint64_t)bitrateKbps * 1000u;
    uint64_t bitsPerFrame = (uint64_t)frameRate * 8u;
    uint64_t codecBytes = (bitsPerSecond + bitsPerFrame - 1) / bitsPerFrame;
    uint64_t envelopeBytes = 32u + 4u * PW_MAX_PACKETS;
    uint64_t total = codecBytes + envelopeBytes;
    return (size_t)(total > PW_MAX_FRAME_BYTES ? PW_MAX_FRAME_BYTES : total);
}

bool PWAppendFragment(uint8_t *frame, size_t frameLength, size_t *offset,
                      const uint8_t *fragment, size_t fragmentLength) {
    if (!frame || !offset || !fragment || !fragmentLength ||
        *offset > frameLength || fragmentLength > frameLength - *offset) return false;
    memcpy(frame + *offset, fragment, fragmentLength);
    *offset += fragmentLength;
    return true;
}

bool PWParseEnvelope(const uint8_t *input, size_t length, uint16_t width,
                     uint16_t height, uint32_t frameNumber, size_t frameCap,
                     PWPacketRange ranges[PW_MAX_PACKETS], size_t *count) {
    if (!input || !ranges || !count || length < 32 || length > PW_MAX_FRAME_BYTES ||
        length > frameCap || !frameNumber || !PWLiveDimensionsSupported(width, height) ||
        memcmp(input, "PWR2", 4) || be16(input + 4) != 2 ||
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
        if (!size || size > PW_MAX_RECORD_BYTES || size > length - offset) return false;
        ranges[i] = (PWPacketRange){offset, size};
        offset += size;
    }
    if (offset != length) return false;
    *count = packets;
    return true;
}
