# Apollo Pyrowave in Moonlight TV

This is the client side of the authenticated Apollo session experiment. The TV
setting **Experimental Video** defaults off. When enabled, the client checks
both `/serverinfo` tags and both RTSP DESCRIBE attributes for envelope version
`2` and pin `5e4a98f807dddd2498824e3b55ef2fe1845bcc59`. Missing or
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
bundle=/path/to/codec-source.bundle
printf '%s  %s\n' ad0bb91576bfaa134947aa6bc021a4f3e2de48ec607f63a6648e214c7e0d3e26 "$bundle" | shasum -a 256 -c -
source_dir="$PWD/experiments/pyrowave-tvos/generated/codec-scan-5e4a98f-source"
git clone --no-checkout "$bundle" "$source_dir"
git -C "$source_dir" checkout --detach 5e4a98f807dddd2498824e3b55ef2fe1845bcc59
experiments/pyrowave-tvos/scripts/prepare-dependency.sh "$source_dir"
```

`prepare-dependency.sh` verifies the source HEAD and byte-for-byte Metal
subset at the pin. The private commit is supplied by the verified bundle; the
default preparation path only reuses an existing local `generated/source`
checkout and never fetches it from public upstream. Its generated output is
ignored. A supplied prepared subset
can also be verified with `shasum -a 256 -c scripts/pyrowave-metal.sha256`
from `experiments/pyrowave-tvos`.

If an existing main checkout still has the old common-c patch, identify it
exactly before replacing it. From the repository root, use the saved
`common-c-before.patch` snapshot (SHA-256
`fdc80c96ab83878ebbbb0e77e900caa43d15bf52a24d5a962714044707b1006c`):

```sh
common=moonlight-common/moonlight-common-c
old_patch=/path/to/common-c-before.patch
new_patch="$PWD/experiments/pyrowave-tvos/patches/common-c-pyrowave.patch"
test "$(git -C "$common" rev-parse HEAD)" = f900dd4767759c7b9d0e93bcea666b55c69ea62f
printf '%s  %s\n' fdc80c96ab83878ebbbb0e77e900caa43d15bf52a24d5a962714044707b1006c "$old_patch" | shasum -a 256 -c -
git -C "$common" diff --binary --unified=0 | cmp - "$old_patch"
test -z "$(git -C "$common" ls-files --others --exclude-standard)"
git -C "$common" apply --reverse --unidiff-zero --check "$old_patch"
git -C "$common" apply --reverse --unidiff-zero "$old_patch"
git -C "$common" apply --unidiff-zero --check "$new_patch"
git -C "$common" apply --unidiff-zero "$new_patch"
experiments/pyrowave-tvos/scripts/prepare-common-c.sh # confirms exact new patch
```

The original phase-2 fixture manifest still records generator commit
`89f7e47d4abbf650c91fae766728af866c5e32a0`. The decoder and bitstream
sources are byte-identical at the new pin, so those fixtures remain suitable
for decoder compatibility checks. Probe reports identify the current codec
binary separately from the fixture generator. They are not a new physical
performance or playback result.

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
cc -std=c11 -DDEBUG=1 -Wall -Wextra -Werror \
  experiments/pyrowave-tvos/tests/renderer-gate.c -o experiments/pyrowave-tvos/build/renderer-gate
experiments/pyrowave-tvos/build/renderer-gate
cc -std=c11 -Wall -Wextra -Werror \
  experiments/pyrowave-tvos/tests/drawable-size.c -o experiments/pyrowave-tvos/build/drawable-size
experiments/pyrowave-tvos/build/drawable-size
```

The parser accepts one complete decode unit only after checking its header,
negotiated dimensions and frame number, color profile, counts, record lengths,
limits and exact consumption. common-c reassembles RTP fragments before the
client parses the envelope and passes each complete codec record to the decoder.
Each frame independently clears the decoder.
One Metal command buffer owns decode, render and presentation; one in-flight
frame bounds texture reuse and teardown drains it. No CPU pixel readback is
used in live playback. The tvOS app ends an active experimental stream when it
becomes inactive and returns to the app list on resume. The fixture probe
remains unchanged.

## Current contract limits

Apollo accepts exactly 1920×1080, 2560×1440, or 3840×2160 at 60 fps SDR.
All three sizes use the same
version 2 big-endian `PWR2` envelope (32-byte header, flags 1, color profile 1),
1 MiB absolute frame cap, 1–1024 codec records and 1–65536 bytes per record.
The codec record limit is independent of RTP MTU; transport packet size, FEC
and encryption remain unchanged. A v1 capability or envelope is rejected.
The negotiated client frame cap is the smaller of 1 MiB and
`ceil(requested_kbps * 1000 / (8 * fps)) + 32 + 4 * 1024` bytes. The extra
bytes cover the header and all possible record-length prefixes. At 60 fps,
100/150/200 Mbps give 212462/316628/420795 bytes. Invalid nonpositive
bitrate or frame rate yields a zero cap; the host still enforces its tighter
padded RTP/FEC/wire budget.
The tvOS settings already offer 1440p. The client opts in only for one of these
three exact modes, and the parser and renderer reject other dimensions.
common-c has no separate geometry allowlist: it sends the configured width and
height through the same v2 negotiation. The client allocates the negotiated
dimensions. Smoke-test 1080p60, then 1440p60 on a native 2560×1440 output:
confirm the live log records decoded 2560×1440 and a 2560×1440 **actual
drawable texture**, sustained presentation, bandwidth and image quality.
On a 4K TV, 1440p decoded content may scale to a 3840×2160 drawable normally;
check the logged native display, requested drawable and actual texture size.
Validate 4K60 separately on a 4K output. On lower-resolution displays the
requested drawable is limited by the native mode. Current 2560×1440 host
capture means 4K output is scaled capture, not native 4K detail. Unsigned
builds do not establish physical TV playback, quality or latency benefit.

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

In Debug builds, `MOONLIGHT_PYROWAVE_FORCE_INIT_FAILURE=1` forces the actual
renderer initialization gate to fail once so the connection-error and teardown
path can be checked on a device later. The focused C check exercises this same
gate's one-shot failure and healthy initialization decisions; it does not
replace a live UI or drawable-size check. Selected-session renderer failure
ends the session with an error. There is no automatic reconnect loop.
