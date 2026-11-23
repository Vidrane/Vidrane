# Vidrane

**Vidrane** is an open-source multimedia player with a Rust core and native
frontends. All implemented features are free, with no subscriptions or
paid tiers. Current status: **v0.1.0-dev**, not yet feature-complete versus
nPlayer Plus.

## Main iOS application

The **main Personal and Developer IPA builds both include AVFoundation and
libmpv/FFmpeg**. There is no extra premium, Lite or experimental IPA edition.

- Vidrane Player is the default interface. Apple's system controls remain
  optional when using the native AVFoundation decoder.
- Select Automatic, AVFoundation or libmpv in Settings. Automatic routing is
  heuristic and real codec support still requires device testing.
- Native PiP, playback gestures, scaling, audio/subtitle track selection,
  resume history and external timed-text subtitles where supported.
- libmpv adds a real alternative decoder, with VideoToolbox/software
  preferences, track selection, subtitle timing and video scaling.
- Six tabs: Local, Network, Playlists, Browser, Downloads and Settings.
- Nested local files with import, rename, copy, move, delete, search, sort,
  filter, file details, share sheet and persistent playlists/watch history.
- SFTP with verified SSH host keys, Keychain passwords, folder browsing,
  chunked download/upload, mkdir and confirmed remote delete.
- HTTPS WebDAV with Keychain-backed Basic auth, folder operations,
  remote file uploads, authenticated downloads and native-compatible
  byte-range streaming without full-file imports.
- A foreground download queue with progress, cancellation and retries.

## Architecture

- `crates/vidrane-core`: shared Rust media, parsing and domain policies.
- `crates/vidrane-ffi`: native C ABI bridge.
- `ios/Vidrane/Sources`: SwiftUI, AVKit, MPVKit and platform APIs.
- `ios/mpv/prepare.sh`: fetches pinned MPVKit sources and verified XCFramework.
- `.github/workflows/ios.yml`: main iOS Personal/Developer unsigned IPA builds.

## Build

Rust:

    cargo fmt --all -- --check
    cargo test --workspace
    cargo build --workspace --release

iOS device (requires macOS, Xcode, XcodeGen, Rust iOS target):

    rustup target add aarch64-apple-ios
    bash ios/mpv/prepare.sh
    cd ios/Vidrane
    xcodegen generate
    xcodebuild -project Vidrane.xcodeproj -scheme VidranePersonal \
      -configuration Release -sdk iphoneos \
      -destination 'generic/platform=iOS' \
      VIDRANE_RUST_TARGET=aarch64-apple-ios \
      CODE_SIGNING_ALLOWED=NO build

Build the second signing profile with the `VidraneDeveloper` scheme.
Both variants have the same features but still need legitimate signing
to install on a physical iPhone.

## Documentation

- [Architecture](docs/ARCHITECTURE.md)
- [Implementation status](docs/PHASE1.md)
- [Local files](docs/LOCAL_FILES.md)
- [WebDAV and SFTP](docs/NETWORK.md)
- [SFTP setup and security](docs/SFTP.md)
- [Subtitle support](docs/SUBTITLES.md)
- [Media engines](docs/ENGINE.md)
- [Pinned libmpv build and licensing](docs/MPV_IOS.md)

## License and status

Vidrane-owned code is released under MIT. Upstream MPVKit/libmpv/FFmpeg and
transitive codec libraries have independent licenses and possible patents.
Review the actual upstream binary and distribution obligations before
redistributing a signed public release.

Compilation in GitHub Actions is not a substitute for real iPhone tests.
Device testing will begin after sufficient basic nPlayer-like functionality
is implemented, as requested.
