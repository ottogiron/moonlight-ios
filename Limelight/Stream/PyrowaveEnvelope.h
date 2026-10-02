#ifndef PYROWAVE_ENVELOPE_H
#define PYROWAVE_ENVELOPE_H

#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>

#define PW_MAX_FRAME_BYTES (1024u * 1024u)
#define PW_MAX_PACKETS 1024u

typedef struct {
    size_t offset;
    size_t length;
} PWPacketRange;

// Input is one fully reassembled common-c DECODE_UNIT, after the Sunshine short header.
// Output ranges refer to input and are only valid when this returns true.
bool PWParseEnvelope(const uint8_t *input, size_t length, uint16_t width,
                     uint16_t height, uint32_t frameNumber, size_t frameCap,
                     PWPacketRange ranges[PW_MAX_PACKETS], size_t *count);

#endif
