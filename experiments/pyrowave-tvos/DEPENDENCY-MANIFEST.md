# Moonlight TV clean-checkout dependency manifest

This milestone starts from client commit `927ad9542795e0de93994feb42edccc506828074`.
Run `experiments/pyrowave-tvos/scripts/prepare-build.sh` from the repository root, then use the unsigned
`Moonlight TV` commands in `LIVE-INTEGRATION.md`. No old generated directory,
private Git bundle, or other checkout is required.

| Input | Exact source | Applied in this checkout |
| --- | --- | --- |
| Pyrowave Metal decoder subset and MIT license | Pyrowave Git `5e4a98f807dddd2498824e3b55ef2fe1845bcc59` | Tracked `experiments/pyrowave-tvos/vendor/pyrowave-metal/`; eight exact SHA-256 values in `experiments/pyrowave-tvos/scripts/pyrowave-metal.sha256`; copied to ignored `experiments/pyrowave-tvos/generated/pyrowave-metal/` |
| moonlight-common-c | Public Git `f900dd4767759c7b9d0e93bcea666b55c69ea62f` | Tracked gitlink plus `experiments/pyrowave-tvos/patches/common-c-pyrowave.patch` (SHA-256 `56f98c8b591986be78fa94cde1f308c0be8c193f2c8f7ac53d3342e03bdd2245`) |
| X1Kit | Public Git `6e842ae9d5a21916d7c9693c7385d1ac672bc4fa` | Tracked gitlink |
| common-c/enet | Public Git `aca87840b57f045a1f7f9299e4b1b9b8e2a5e2f1` | Nested common-c gitlink |
| common-c/nanors | Public Git `b1e3c22ca0cdc0bb83e3cd6ed1a2fc77869ed99a` | Nested common-c gitlink |
| OpenSSL-Package | Public Git `a3809db22a45e3ff658377a24da252982a306b9b`, version `3.6.3000` | Tracked `Moonlight.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved` |

The decoder source files and license were compared byte for byte with `git show`
of their exact paths in the preserved pinned source checkout before vendoring.
`experiments/pyrowave-tvos/scripts/verify-dependency.sh` verifies both the tracked and generated copies against
the original SHA-256 manifest. Its `COMMIT` marker is the Pyrowave source pin.
The full private source checkout has no role in preparation or builds.

The expected post-setup Git dirt is the four-file common-c patch. Generated
Metal files, Xcode products, and optional probe fixtures are ignored. The
fixture generator pin `89f7e47d4abbf650c91fae766728af866c5e32a0` belongs
to the separate diagnostic probe and is not a production build dependency.
