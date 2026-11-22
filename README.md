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
