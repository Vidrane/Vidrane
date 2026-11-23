# libmpv/FFmpeg in main iOS builds

libmpv is now included in **both standard VidranePersonal and
VidraneDeveloper unsigned IPA builds**, rather than published as a separate
experimental flavor. Both signing profiles have identical feature access.

## Reproducible dependency

- Upstream wrapper: https://github.com/libmpv-ios/mpv-ios
- Pinned release: v0.1.2
- Pinned source SHA: 747cd35525cb7466475d8534b25480c8fe21c5ac
- Third-party file: Libmpv.xcframework.zip (release artifact)
- Pinned SHA-256: ea5ca804e19167072493a3e2fc4c003c2eaec84dc123bb62248932c71a891807

The binary is downloaded at build time. The checked-in preparation script
verifies the source revision and archive SHA-256 before unzipping. Vidrane
does not commit this third-party binary to its Git repository.

## Build main IPA on macOS

Prerequisites: Xcode, XcodeGen and Rust target aarch64-apple-ios.

    bash ios/mpv/prepare.sh
    cd ios/Vidrane
    xcodegen generate
    xcodebuild -project Vidrane.xcodeproj -scheme VidranePersonal \
      -configuration Release -sdk iphoneos \
      -destination 'generic/platform=iOS' \
      VIDRANE_RUST_TARGET=aarch64-apple-ios \
      CODE_SIGNING_ALLOWED=NO build

For Developer use the VidraneDeveloper scheme. The same source and libmpv
package are linked in both. The default CI is .github/workflows/ios.yml
and publishes two unsigned IPA artifacts.

The framework may not provide all targets needed by an iOS Simulator.
The documented command builds an iOS device artifact. IPA files must be
legitimately signed before installing on a real device.

## Decoder and interface selection

- Vidrane Player UI is the default. Apple controls are an alternative.
- The Apple presentation uses AVPlayer/AVFoundation; it cannot wrap libmpv.
- Selecting libmpv explicitly uses Vidrane's custom libmpv controls,
  even when Apple controls are configured as the default interface.
- Automatic decoder preference with Apple presentation starts AVFoundation.
- With Vidrane UI, automatic mode initially prefers native playback for
  typical Apple formats and libmpv for a set of alternative extensions;
  extension matching is a heuristic, not codec inspection.
- Failed AVFoundation playback offers a retry with libmpv.
- libmpv uses MPVCore, an MPVGLView rendering surface and FFmpeg; playback
  controls include seeking, double-tap skip, scaling, speed, tracks,
  external subtitles, adjustable subtitle delay and a VideoToolbox or
  software decoder preference for subsequent sessions.
- Changing backend recreates its playback session. On locally imported
  media the shared watch-history store can restore playback position.

## Outstanding compatibility and redistribution work

libmpv performance, VideoToolbox compatibility, audio output, HDR and real
codec support have not yet been verified on a physical iPhone. libmpv PiP
is not implemented; native AVFoundation PiP remains available.

The upstream prebuilt library and its transitive dependencies are under
their own licenses, independently of Vidrane's MIT source license.
Before distributing signed public builds, audit the actual upstream build,
its FFmpeg/libmpv configuration, transitive LGPL/GPL requirements, source
offer, notices and any applicable codec patent obligations. A successful
CI build does not satisfy these requirements by itself.
