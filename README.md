# Moonlight iOS/tvOS

[![CI](https://github.com/moonlight-stream/moonlight-ios/actions/workflows/ci.yml/badge.svg)](https://github.com/moonlight-stream/moonlight-ios/actions/workflows/ci.yml)

[Moonlight for iOS/tvOS](https://moonlight-stream.org) is an open source client for [Sunshine](https://github.com/LizardByte/Sunshine) and NVIDIA GameStream. Moonlight for iOS/tvOS allows you to stream your full collection of games and apps from your powerful desktop computer to your iOS device or Apple TV.

Moonlight also has a [PC client](https://github.com/moonlight-stream/moonlight-qt) and [Android client](https://github.com/moonlight-stream/moonlight-android).

Check out [the Moonlight wiki](https://github.com/moonlight-stream/moonlight-docs/wiki) for more detailed project information, setup guide, or troubleshooting steps.

[![Moonlight for iOS and tvOS](https://moonlight-stream.org/images/App_Store_Badge_135x40.svg)](https://apps.apple.com/us/app/moonlight-game-streaming/id1000551566)

## Building

### Pyrowave tvOS baseline

The fork's **Moonlight TV** target uses bundle ID
`com.ottogiron.moonlight.pyrowave` in Debug and Release and displays
**Moonlight Pyrowave** on the home screen. This identity is intended for an
installation alongside stock Moonlight. Streaming still uses the existing
standard codecs (H.264/HEVC, with AV1 where supported); Pyrowave decoding and
protocol integration have not been added. The iOS target retains its upstream
settings.

On a Mac, complete full Xcode's first-launch setup and install tvOS platform
support and any requested toolchain components. Check `xcodebuild -version`
and `xcodebuild -showsdks` to confirm the selected developer directory points
to full Xcode and includes `appletvos`.

```sh
git clone --recursive https://github.com/ottogiron/moonlight-ios.git
cd moonlight-ios
git submodule update --init --recursive
```

For an existing checkout, run the recursive submodule command after updating.
Use a revision containing these baseline changes, or apply the baseline patch
locally if it is still uncommitted. Xcode also resolves the project's OpenSSL
Swift package.

Set your signing team before opening the project: copy `Local.xcconfig.example`
to `Local.xcconfig` and put your team ID in it. Git ignores `Local.xcconfig`,
and the app targets and the tvOS probe read the team from it through
`Signing.xcconfig`, so the project files stay unchanged. Then open
`Moonlight.xcodeproj` and select the **Moonlight TV** scheme; automatic signing
is already enabled. Do not choose a team in **Signing & Capabilities**: Xcode
would write it into the project file.

Pair the Apple TV on the same network. In Xcode 27, open **Xcode > Open
Developer Tool > Device Hub**, then choose **+ > Pair Nearby Device** and
**Apple TV**; earlier Xcode versions use **Devices and Simulators**. Follow
[Apple's pairing instructions](https://developer.apple.com/documentation/xcode/pairing-your-devices-with-your-mac),
select the TV as the run destination, and run. For a signed CLI build, replace
these placeholders with your local team and paired device IDs:

```sh
TVOS_TEAM_ID='YOUR_TEAM_ID'
TVOS_DEVICE_ID='YOUR_PAIRED_APPLE_TV_ID'
heavy xcodebuild -project Moonlight.xcodeproj -scheme "Moonlight TV" \
  -configuration Debug -sdk appletvos \
  -destination "platform=tvOS,id=$TVOS_DEVICE_ID" \
  -allowProvisioningUpdates DEVELOPMENT_TEAM="$TVOS_TEAM_ID" \
  CODE_SIGN_STYLE=Automatic build
```

The CLI override applies to dependencies too and leaves project files unchanged;
Xcode must have access to your signing account. Build unsigned for the physical
tvOS platform without provisioning:

```sh
heavy xcodebuild -project Moonlight.xcodeproj -scheme "Moonlight TV" \
  -configuration Debug -sdk appletvos -destination 'generic/platform=tvOS' \
  -derivedDataPath /tmp/moonlight-pyrowave-unsigned \
  CODE_SIGNING_ALLOWED=NO CODE_SIGNING_REQUIRED=NO build
```

Repeat with `-configuration Release`. An unsigned build cannot be installed on
the TV. Native builds, signed installation alongside stock, and conventional
1080p60 playback remain the baseline gate before codec work. Refresh signing
through Xcode and rebuild/reinstall when your provisioning profile expires.

### Fork layout

`master` mirrors upstream `master` exactly and takes no commits of its own.
`otto` is the personal branch and the fork's default: upstream plus the
Pyrowave work. The `moonlight-common-c` submodule points at a fork with the
same layout, because the Pyrowave negotiation lives in that library.

```sh
git checkout otto
git fetch origin
git fetch upstream
git branch -f master upstream/master
git merge master
git submodule update --init --recursive
git push origin master otto
```

The fork is public. Machine names, home-directory paths, network addresses,
device identifiers and signing identities do not belong in commits or commit
messages.

### Upstream build instructions

* Install Xcode from the [App Store page](https://apps.apple.com/us/app/xcode/id497799835)
* Run `git clone --recursive https://github.com/moonlight-stream/moonlight-ios.git`
  *  If you've already clone the repo without `--recursive`, run `git submodule update --init --recursive`
* Open Moonlight.xcodeproj in Xcode
* To run on a real device, you will need to locally modify the signing options:
    * Click on "Moonlight" at the top of the left sidebar
    * Click on the "Signing & Capabilities" tab
    * Under "Targets", select "Moonlight" (for iOS/iPadOS) or "Moonlight TV" (for tvOS)
    * In the "Team" dropdown, select your name. If your name doesn't appear, you may need to sign into Xcode with your Apple account.
    * Change the "Bundle Identifier" to something different. You can add your name or some random letters to make it unique.
    * Now you can select your Apple device in the top bar as a target and click the Play button to run.
