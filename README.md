# Vidrane

**Vidrane** is a free, open-source media player with a shared Rust core and native platform frontends. Our long-term goal is comprehensive media, network and subtitle functionality. There are **no paid feature tiers**.

**Status: v0.1.0-dev, first iOS foundation.** The project is not yet at nPlayer Plus feature parity.

## Current implementation

- Dark iOS interface with six major areas: Local, Network, Playlists, Browser, Downloads and Settings.
- Imports files from iOS Files to the app's own Media directory; file deletion and local library.
- AVFoundation audio/video playback with native controls and system PiP where available.
- Locally persisted playlists: create, add items, remove items.
- Direct HTTPS streaming and basic one-file HTTPS downloads.
- Embedded WebKit browser; persistent display and playback settings.
- Rust workspace with C ABI for media classification, unit tests and capability requirements.

## Architecture

- crates/vidrane-core: shared Rust domain and capability primitives.
- crates/vidrane-ffi: native C ABI, currently used by iOS file classification.
- ios/Vidrane/Sources: SwiftUI frontend with AVKit, WebKit and URLSession.
- ios/Vidrane/Config: Personal and Developer signing configurations.
- docs/PHASE1.md: implemented, unverified and future work.
- docs/ARCHITECTURE.md: project boundaries.

Swift is used for iOS UI and system framework bridging; shared cross-platform code lives in Rust.

## Build Rust

    cargo test --workspace
    cargo build --workspace --release

## Build iOS on a Mac

Install Xcode, Rust and XcodeGen. Then:

    rustup target add aarch64-apple-ios aarch64-apple-ios-sim
    cd ios/Vidrane
    xcodegen generate
    xcodebuild -project Vidrane.xcodeproj -scheme VidranePersonal -configuration Debug -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' VIDRANE_RUST_TARGET=aarch64-apple-ios-sim CODE_SIGNING_ALLOWED=NO build

GitHub Actions attempts device builds for both signing profiles and publishes unsigned IPA files. They are **not installable until signed** with an authorized Apple ID and matching provisioning. No certificates or private keys are stored here.

## Apple profile policy

VidranePersonal and VidraneDeveloper contain the same features; they differ only in intended code signing and future platform entitlement configuration. Personal Team remains subject to Apple's restrictions; paid Developer Program membership does not itself grant every entitlement.

## License

MIT. Independent source code; no proprietary nPlayer assets or code are included.

## iOS player interface

Vidrane's custom interface is the default for fresh installations. In Settings → Playback, users can select Apple's system video player as the default for future files; changing the interface from the playback screen affects only that viewing session. Both modes currently use the same AVFoundation engine, and system Picture-in-Picture is provided by the Apple control mode on supported devices.

## Subtitle and decoder roadmap

Vidrane now parses external UTF-8 SRT and WebVTT in Rust, with on-screen captions on iOS. Playback still uses AVFoundation in both player interfaces; a Rust decoder routing policy is present, but libmpv/FFmpeg decoding is not integrated yet. See [subtitle support](docs/SUBTITLES.md) and [engine architecture](docs/ENGINE.md).

## Network and transfers

An iOS HTTPS WebDAV browser supports Basic authorization, folder navigation and importing remote files into local media. Direct HTTPS downloads and authenticated WebDAV downloads now share a foreground queue with progress, cancel and retry. For security details and limits see [network architecture](docs/NETWORK.md). WebDAV interoperability still needs live-server testing.


## Experimental libmpv iOS build

Vidrane has a separately built libmpv/FFmpeg adapter using a pinned
third-party MPVKit wrapper and XCFramework. The default app remains
AVFoundation-based, so Personal and Developer builds remain lightweight.
With libmpv linked, the decoder can be selected in Settings, and
unsupported native formats can be retried with the alternative backend.
The experiments are not yet tested on a physical iPhone.
See [MPV iOS build guide](docs/MPV_IOS.md).
