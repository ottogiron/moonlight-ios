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

tvOS also offers **Pyrowave Bitrate**: **Use Video Bitrate** (the default), or
150, 200, 250, 300, 400, and 500 Mbps. Values are stored as Kbps and accepted
only when they exactly match one of those choices. Invalid persisted values
behave as the default. The chosen value stays saved while Experimental Video is
off. It affects only an eligible Pyrowave request to a host advertising the
exact version and pin; HEVC, H.264, and AV1 retain **Video Bitrate**. An
explicit override requires Pyrowave selection at RTSP DESCRIBE. If the host
does not advertise the matching capability or rejects launch/RTSP setup, the
client shows an error rather than streaming a conventional codec at the
Pyrowave rate. High choices require the updated Apollo host and are intended
for wired networking.

The selected Kbps value reaches both common-c's stream configuration and the
Sunshine `x-ml-video.configuredBitrateKbps` RTSP attribute. The legacy RTSP
initial/maximum fields retain their existing FEC discount and 100 Mbps cap for
ordinary sessions and for Pyrowave at 150 Mbps or with no override. Explicit
Pyrowave choices above 150 Mbps bypass that cap; the configured attribute is
not discounted a second time. The selected bitrate is a transport budget that
includes error correction. Actual codec payload may be lower because of FEC,
encoder rate control, and scene content. This change makes no promise of HEVC
image quality parity or lower latency.

## Prepare a clean checkout

From the repository root, run one command before the first unsigned build:

```sh
experiments/pyrowave-tvos/scripts/prepare-build.sh
```

This initializes the pinned public `X1Kit`, common-c, `enet`, and `nanors`
submodules. It verifies the tracked Pyrowave Metal subset and copies it to the
ignored `experiments/pyrowave-tvos/generated/pyrowave-metal/` path used by Xcode.
It then applies the exact tracked common-c patch at base
`f900dd4767759c7b9d0e93bcea666b55c69ea62f`. Repeating the command verifies
the existing files and patch without changing them. Unexpected submodule commits,
local source edits, staged changes, untracked submodule files, or altered decoder
files make preparation fail rather than overwrite work.

The eight vendored files, including the MIT `LICENSE`, are exact blobs from the
reviewed Pyrowave commit `5e4a98f807dddd2498824e3b55ef2fe1845bcc59`.
`scripts/pyrowave-metal.sha256` records their hashes. The `COMMIT` marker records
the source pin. The private whole-repository source bundle is not a build input.
The public submodule URLs and exact Git commits are recorded in `.gitmodules`
and the repository gitlinks; their nested pins are in common-c. Reproducibility
needs only this repository and those pinned public submodules.
See `DEPENDENCY-MANIFEST.md` for every exact revision and decoder hash.

After preparation, `git status --short` should report only the common-c submodule
as modified. The decoder copy and Xcode products live in ignored directories.
`git -C moonlight-common/moonlight-common-c diff --binary --unified=0` must match
`experiments/pyrowave-tvos/patches/common-c-pyrowave.patch` byte for byte.
`experiments/pyrowave-tvos/scripts/prepare-common-c.sh --check` and
`experiments/pyrowave-tvos/scripts/verify-dependency.sh` check
those states without rewriting files. The submodule dirt is expected build setup;
changes to tracked project files, signing metadata, or other source are not.
Do not commit the local common-c gitlink or generated build output.

## Build and focused check

Use Xcode 27 and the `appletvos` SDK. These commands build unsigned for a
generic physical tvOS destination without a development team or signing profile.
The production Moonlight TV build does not need the old diagnostic fixture blobs.

```sh
python3 experiments/pyrowave-tvos/tests/test_dependency_preparation.py
heavy xcodebuild -project Moonlight.xcodeproj -scheme 'Moonlight TV' \
  -configuration Debug -sdk appletvos -destination 'generic/platform=tvOS' \
  -derivedDataPath experiments/pyrowave-tvos/build/DerivedData-live \
  CODE_SIGNING_ALLOWED=NO -jobs 4 build
heavy xcodebuild -project Moonlight.xcodeproj -scheme 'Moonlight TV' \
  -configuration Release -sdk appletvos -destination 'generic/platform=tvOS' \
  -derivedDataPath experiments/pyrowave-tvos/build/DerivedData-live \
  CODE_SIGNING_ALLOWED=NO -jobs 4 build
cc -std=c11 -Wall -Wextra -Werror \
  experiments/pyrowave-tvos/tests/bitrate-policy.c \
  -o experiments/pyrowave-tvos/build/bitrate-policy
experiments/pyrowave-tvos/build/bitrate-policy
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

For a device installation or later update, open `Moonlight.xcodeproj` in Xcode,
select **Moonlight TV**, and choose your own signing team in Xcode's **Signing &
Capabilities** UI. Keep the existing `com.ottogiron.moonlight.pyrowave` bundle ID
and current app settings so Xcode updates the same app. Build and install from
Xcode under your own account. No signing or device action is part of the setup
script or unsigned commands above.

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
For the first quality comparison, use 2560×1440 at 60 fps SDR with Pyrowave
at 300 Mbps against Pyrowave at 150 Mbps; keep HEVC at its existing 150 Mbps
**Video Bitrate** setting. Confirm the requested/configured RTSP Kbps and the
host's actual encoded rate before interpreting image quality. This is not a
4K, HDR, adaptive-bitrate, or renderer change.
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
