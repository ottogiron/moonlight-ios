# Clean-checkout build evidence

Baseline: `927ad9542795e0de93994feb42edccc506828074`. Verification used Apple
Silicon, Xcode 27.0 (27A266), the tvOS 27.0 SDK, and at most four Xcode jobs.
No signing, device installation, or playback was run.

| Check | Result |
| --- | --- |
| Compared all eight preserved Metal subset files and the MIT license with `git show 5e4a98f...:<path>` from the pinned source checkout | Exact byte matches; `scripts/pyrowave-metal.sha256` passes for the tracked subset and generated copy |
| `python3 experiments/pyrowave-tvos/tests/test_dependency_preparation.py` | Five tests pass: clean generation, repeat without rewriting, altered vendor, wrong pin, altered or extra generated file refusal |
| `experiments/pyrowave-tvos/scripts/prepare-build.sh` twice | First run applied the exact common-c patch; second run detected it unchanged and accepted the generated decoder |
| Added an untracked file in common-c, then ran preparation | Refused with `common-c has unexpected local changes`; the temporary file was removed and preparation passed again |
| `git -C moonlight-common/moonlight-common-c diff --binary --unified=0 \| cmp - experiments/pyrowave-tvos/patches/common-c-pyrowave.patch` | Exact match |
| Existing focused C/C++/Objective-C checks | Bitrate policy, envelope, renderer gate, drawable size, drain accounting, and report stats passed |
| `sh -n` on four preparation scripts; staged whitespace check with upstream blank-line whitespace exempted | Passed; the embedded MSL's original bytes were preserved for exact hash matching |

Fresh-clone check: `git clone --local --no-hardlinks .` produced commit
`5a49a4a62414a742d82d088372f22ac1b55e16bf` with no `generated/`
directory and both top-level submodules uninitialized. In that clone,
`scripts/prepare-build.sh` initialized all four public submodules, generated
the exact decoder files, and applied the patch. A second run passed without
changing files. `git status --short` showed only the expected modified common-c
submodule; its diff matched the tracked patch byte for byte. The clone was
used for the following additional native builds.

Both native builds used this command shape from the repository root, with
`CONFIGURATION` set to `Debug` and `Release` in separate runs:

```sh
heavy xcodebuild -project Moonlight.xcodeproj -scheme 'Moonlight TV' \
  -configuration CONFIGURATION -sdk appletvos \
  -destination 'generic/platform=tvOS' \
  -derivedDataPath experiments/pyrowave-tvos/build/DerivedData-live \
  CODE_SIGNING_ALLOWED=NO -jobs 4 build
```

Debug: `** BUILD SUCCEEDED **` in
`build/repro-evidence/moonlight-tv-debug-network.log` (ignored local log).
Release: `** BUILD SUCCEEDED **` in
`build/repro-evidence/moonlight-tv-release-escalated.log` (ignored local log).
Fresh clone Debug: `** BUILD SUCCEEDED **` in its ignored
`build/repro-evidence/fresh-debug.log`.
Fresh clone Release: `** BUILD SUCCEEDED **` in its ignored
`build/repro-evidence/fresh-release.log`.
The first sandboxed Debug attempt could not resolve GitHub for the locked public
OpenSSL package; the first sandboxed Release attempt could not write Swift/Clang
caches outside the workspace. Both passed when run with the access Xcode needs.
No project or signing setting was changed to resolve those environment limits.

The app outputs are in `build/DerivedData-live/Build/Products/{Debug,Release}-appletvos/`.
Production Moonlight TV built with no diagnostic fixture blobs staged.
