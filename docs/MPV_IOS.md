# Experimental iOS libmpv backend

The standard Vidrane Personal/Developer IPA builds still use AVFoundation.
An **additional** workflow prepares a real libmpv/FFmpeg video backend and
builds a second, explicitly labelled experimental IPA variant.

## Reproducible build inputs

- Upstream: https://github.com/libmpv-ios/mpv-ios
- Tag: v0.1.2
- Pinned source commit: 747cd35525cb7466475d8534b25480c8fe21c5ac
- Binary: Libmpv.xcframework.zip from that release, approx. 169 MiB
- SHA-256: ea5ca804e19167072493a3e2fc4c003c2eaec84dc123bb62248932c71a891807

The archive is downloaded at build time. Vidrane never commits the third-party
binary to its Git repository. The preparation script verifies the exact source
revision and SHA-256, then generates a second XcodeGen project specification
that depends on MPVKit. The regular Xcode project and CI remain independent.

Run on a Mac with Xcode, Rust iOS targets and XcodeGen:

    bash ios/mpv/prepare.sh
    cd ios/Vidrane
    xcodegen generate --spec project-mpv.generated.yml
    xcodebuild -project Vidrane.xcodeproj -scheme VidranePersonal \
      -configuration Release -sdk iphoneos \
      -destination 'generic/platform=iOS' VIDRANE_RUST_TARGET=aarch64-apple-ios \
      CODE_SIGNING_ALLOWED=NO build

The same code builds the VidraneDeveloper scheme. The unsigned results cannot
be installed without Apple signing/provisioning.

GitHub Actions workflow: .github/workflows/ios-mpv.yml

## Playback architecture

- Application settings -> decoder preference: Automatic / AVFoundation /
  libmpv, with libmpv shown only when the library is actually linked.
- The default player *interface* is Vidrane, not Apple.
- The Vidrane AVFoundation presentation and Apple system presentation share
  one AVPlayer; both are kept intact.
- The optional libmpv playback view owns a distinct MPVCore decoder context,
  renders via MPVGLView (OpenGL ES) and supports play/pause, seek, speed, track
  selection and external subtitle files.
- Automatic routing starts AVFoundation for typical native formats and prefers
  libmpv for media extensions such as MKV, FLAC, AVI and WebM. Extensions are
  a heuristic, not a reliable codec capability probe.
- On AVFoundation failure the user can try libmpv without reopening the file
  manually. libmpv can return to the native backend. Backend changes recreate
  a decoder session; the local shared watch history can restore positions.
- OpenGL ES and VideoToolbox behavior, actual codec support, battery use and
  audio session behavior all require tests on a physical device.

## Limitations and next work

- Native PiP in Apple's and Vidrane's AVFoundation UIs is present. libmpv
  PiP needs a separate sample-buffer renderer and is NOT implemented here.
- The optional MPVKit backend's source and binary were obtained from a
  third-party open-source project; passing iOS compilation does not prove
  playback of every Matroska, Dolby, DTS or HDR format.
- The prebuilt libmpv bundle includes transitive libraries and codecs. Their
  licenses are not covered by Vidrane's MIT license. Before redistribution,
  review whether the particular binary enables GPL components and determine
  the corresponding source, notices and relinking obligations. Do not claim
  that open-source publication alone removes codec patents or third-party
  licensing duties.
- The experimental binary variant is not auto-signed; release to users
  should follow both device testing and the license audit.
