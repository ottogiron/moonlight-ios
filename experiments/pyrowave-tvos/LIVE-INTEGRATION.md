# Apollo Pyrowave in Moonlight TV

This is the client side of the authenticated Apollo session experiment. The TV
setting **Experimental Video** defaults off. When enabled, the client checks
both `/serverinfo` tags and both RTSP DESCRIBE attributes for envelope version
`1` and pin `89f7e47d4abbf650c91fae766728af866c5e32a0`. Missing or
mismatched capability keeps conventional negotiation. The common-c selection
also requires the Sunshine SDP generation path used by Apollo. Non-60 fps, unsupported
dimensions, HDR preference, or a bitrate below the host's minimum also keep
conventional negotiation. Only selected sessions
send ANNOUNCE format `3` and the version/pin selection attributes. They keep
Moonlight's audio, input, encryption, RTP, FEC and loss recovery paths.

## Prepare a clean checkout

The tracked common-c gitlink stays at `f900dd4767759c7b9d0e93bcea666b55c69ea62f`.
The four common-c file edits are in `patches/common-c-pyrowave.patch`; the
submodule is expected to show **dirty** after preparation. Do not commit its
local gitlink. The patch uses zero context and is checked against the exact
base SHA before applying. From the repository root:

```sh
git submodule update --init --recursive moonlight-common/moonlight-common-c X1Kit
experiments/pyrowave-tvos/scripts/prepare-common-c.sh
experiments/pyrowave-tvos/scripts/prepare-common-c.sh # idempotence check
experiments/pyrowave-tvos/scripts/prepare-dependency.sh /path/to/pinned/pyrowave
```

`prepare-dependency.sh` verifies the source HEAD and byte-for-byte Metal
subset at the pin. Its generated output is ignored. A supplied prepared subset
can also be verified with `shasum -a 256 -c scripts/pyrowave-metal.sha256`
from `experiments/pyrowave-tvos`.

## Build and focused check

Use Xcode 27 and the `appletvos` SDK. Build unsigned for a generic tvOS
destination; no TV installation is part of this step.

```sh
heavy xcodebuild -project Moonlight.xcodeproj -scheme 'Moonlight TV' \
  -configuration Debug -sdk appletvos -destination 'generic/platform=tvOS' \
  -derivedDataPath experiments/pyrowave-tvos/build/DerivedData-live \
  CODE_SIGNING_ALLOWED=NO build
heavy xcodebuild -project Moonlight.xcodeproj -scheme 'Moonlight TV' \
  -configuration Release -sdk appletvos -destination 'generic/platform=tvOS' \
  -derivedDataPath experiments/pyrowave-tvos/build/DerivedData-live \
  CODE_SIGNING_ALLOWED=NO build
cc -std=c11 -Wall -Wextra -Werror Limelight/Stream/PyrowaveEnvelope.c \
  experiments/pyrowave-tvos/tests/envelope.c -o experiments/pyrowave-tvos/build/envelope
experiments/pyrowave-tvos/build/envelope
```

The parser accepts one complete decode unit only after checking its header,
negotiated dimensions and frame number, color profile, counts, packet lengths,
limits and exact consumption. Each frame independently clears the decoder.
One Metal command buffer owns decode, render and presentation; one in-flight
frame bounds texture reuse and teardown drains it. No CPU pixel readback is
used in live playback. The tvOS app ends an active experimental stream when it
becomes inactive and returns to the app list on resume. The fixture probe
remains unchanged.

## Current contract limits

The host contract currently lists 1920×1080 output. Its requested expansion
to 3840×2160 keeps version 1 and color profile 1; the client allocates the
negotiated 1080p or 4K dimensions now. A 1080p60 live session is the first
smoke test, followed by 4K60 once the host accepts it. The pinned Metal
decoder accepts even 4:2:0 dimensions and its allocation path has no 1080p
cap. Build success does not establish 4K quality, bandwidth or physical TV
playback. Current host capture at 2560×1440 can initially be scaled.

Profile 1 is **full-range BT.709 matrix, center-sited 4:2:0 SDR** with
nonlinear sRGB input/output. The live shader uses the full-range transform;
the probe's limited-range fixture shader is intentionally untouched. The
Metal API exposes R8 output planes and internal R16 wavelet precision, which
does not define an HDR output profile. HDR needs a new versioned color profile,
explicit bit depth and transfer/primaries metadata, suitable higher precision
output planes, and tvOS drawable/display color configuration. The current
selection excludes HDR settings and the renderer rejects HDR mode callbacks.
It neither displays unsupported HDR as SDR nor labels 10-bit SDR as HDR.

There is no automatic retry after a selected Pyrowave ANNOUNCE failure. Turning
the setting off restores a conventional connection; missing capability already
selects conventional negotiation in the same attempt.
