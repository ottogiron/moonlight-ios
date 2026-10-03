# Pyrowave TV Probe

This is an isolated 1080p SDR decode probe; the live streaming path is described
in `LIVE-INTEGRATION.md`. The macOS verifier and tvOS viewer compile the same
Metal decode core. The current Pyrowave Metal source is MIT licensed and pinned
to `5e4a98f807dddd2498824e3b55ef2fe1845bcc59`. The exact reviewed
decoder, bitstream parser, embedded MSL, and MIT license are tracked in
`vendor/pyrowave-metal/`; the preparation script copies them into ignored
`generated/pyrowave-metal/`. `scripts/verify-dependency.sh` verifies both copies
against `scripts/pyrowave-metal.sha256` and the recorded pin. The live Moonlight
TV clean-checkout path is in `LIVE-INTEGRATION.md`.

The original fixtures were generated at
`89f7e47d4abbf650c91fae766728af866c5e32a0`. The decoder, bitstream source,
and API are unchanged between the two commits; the current embedded MSL changes
one encoder rate-control scan loop. Fixture manifests keep their original pin.
New verifier and TV probe reports use `pyrowave_commit` for the compiled source
and `fixture_pyrowave_commit` for the fixture generator.

## Prepare and verify on an Apple Silicon Mac

From this directory:

```sh
scripts/prepare-dependency.sh
scripts/verify-dependency.sh
scripts/stage-fixtures.sh /path/to/fixture-directory
heavy scripts/build-mac.sh
python3 scripts/test-fixture-loader.py
scripts/test-drain.sh
scripts/test-report.sh
heavy build/pyrowave-mac-verify Fixtures > build/mac-report.json
```

The private full-source bundle is no longer needed for this build. The
vendored subset was compared byte for byte with each Git blob at the pinned
commit before tracking it. Fixture staging and the macOS verifier below are
optional diagnostics, separate from the production Moonlight TV build.

The external directory must contain `manifest.json` and all six named payload,
packet CSV, and Vulkan reference files. `Fixtures/`, `generated/`, `build/`, and
`DerivedData/` are ignored. The loader checks the schema, commit, BT.709 limited
metadata, 1920×1080 4:2:0 dimensions, SHA-256 values, exact packet coverage,
and reference size. The verifier compiles upstream decode shaders and the viewer
shader at runtime. It requires a real Apple7 or newer Metal device, waits for GPU
completion, and compares each Y/Cb/Cr pixel against Vulkan precision 1. All
planes must have maximum absolute error ≤2 LSB. The JSON records mean and
maximum error per plane for every run, including a reverse-order reuse pass.

## Build the separate tvOS app

```sh
heavy xcodebuild -project PyrowaveTVProbe.xcodeproj -scheme 'Pyrowave TV Probe' \
  -configuration Debug -sdk appletvos -destination 'generic/platform=tvOS' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
heavy xcodebuild -project PyrowaveTVProbe.xcodeproj -scheme 'Pyrowave TV Probe' \
  -configuration Release -sdk appletvos -destination 'generic/platform=tvOS' \
  -derivedDataPath DerivedData CODE_SIGNING_ALLOWED=NO build
```

The project uses bundle ID `com.ottogiron.moonlight.pyrowave.probe` and has no
signing team. Stage fixtures before building so the folder reference copies
them into the app bundle. A signed device run is a separate operator step.

On launch, the app checks all six fixtures twice before starting display. It
shows fixture names and a pass/fail summary. The default run has 60 warmup
display callbacks and 3,600 measured callbacks (about 60 seconds at 60 Hz).
Launch arguments `--warmup N --frames N` cap either count at 3,600. One decode
and render pair is in flight at a time. The app creates `Library/Caches` in its
data container and writes `Library/Caches/pyrowave-tv-probe-report.json`. Retrieve
it after an operator-run device launch:

```sh
xcrun devicectl device copy from --device "$TV_UDID" \
  --domain-type appDataContainer \
  --domain-identifier com.ottogiron.moonlight.pyrowave.probe \
  --source Library/Caches/pyrowave-tv-probe-report.json \
  --destination ./pyrowave-tv-probe-report.json
```

The console logs final counters and the complete JSON before attempting the
write. If a console line is truncated, concatenate the numbered `Pyrowave report
JSON base64` chunks between `BEGIN` and `END`, then base64-decode them. The TV
screen reports serialization, directory, and write failures separately.

After the last measured display callback, the app stops submitting frames. It
finalizes immediately once every submitted measured frame has both a GPU
completion and a drawable presentation callback. A missing callback produces a
failure report after a three-second drain timeout; late callbacks cannot change
that frozen report. `PASS` requires 12/12 Vulkan comparisons, all target display
callbacks submitted, completed without GPU errors, and observed as presented
without skips or cadence misses. Busy callbacks and unavailable drawables fail
that strict 60 Hz result. The report includes pending callbacks and GPU work,
skipped presentations, raw zero or unavailable presentation timestamps, drawable
ID mismatches, the timeout flag, and the observed presentation rate. A presented
drawable requires a finite positive timestamp and a matching ID captured in the
Metal presentation callback. These snapshots record callback-time values; they
do not establish why the previous device run reported zero timestamps. Unavailable
timing statistics are JSON `null`, with
sample and unavailable counts, instead of made-up zero values.

The report separates CPU submission duration, GPU decode and render timestamps
when valid, display callback cadence, busy/drawable misses, completed command
buffers, and observed drawable presentations. Presentation intervals are display
observations, not photon latency. CPU readback and Vulkan comparison happen
before the timed loop. The render shader converts limited-range BT.709 YCbCr to
linear RGB; the BGRA8 sRGB drawable applies the output transfer function once.
