#ifndef PYROWAVE_ENVELOPE_H
#define PYROWAVE_ENVELOPE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PW_MAX_FRAME_BYTES (1024u * 1024u)
#define PW_MAX_PACKETS 1024u
#define PW_MAX_RECORD_BYTES 65536u

static inline bool PWLiveDimensionsSupported(size_t width, size_t height) {
    return (width == 1920 && height == 1080) ||
           (width == 2560 && height == 1440) ||
           (width == 3840 && height == 2160);
}

typedef struct {
    size_t offset;
    size_t length;
} PWPacketRange;

// The requested video rate bounds codec bytes per frame. Allow the full
// envelope header and one length prefix per possible record on top of it.
// Returns zero for invalid signed configuration values.
size_t PWFrameCapForBitrate(int bitrateKbps, int frameRate);

// Append a fragment of a reassembled common-c decode unit before parsing.
bool PWAppendFragment(uint8_t *frame, size_t frameLength, size_t *offset,
                      const uint8_t *fragment, size_t fragmentLength);

// Input is one fully reassembled common-c DECODE_UNIT, after the Sunshine short header.
// Output ranges refer to input and are only valid when this returns true.
bool PWParseEnvelope(const uint8_t *input, size_t length, uint16_t width,
                     uint16_t height, uint32_t frameNumber, size_t frameCap,
                     PWPacketRange ranges[PW_MAX_PACKETS], size_t *count);

#endif
