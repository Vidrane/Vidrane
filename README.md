# Vidrane

Vidrane is a free, open-source, cross-platform multimedia player in
development, with a Rust shared core and a native SwiftUI iOS frontend.
There are **no subscriptions, paid tiers or feature restrictions**.

The main iOS Personal and Developer unsigned IPA builds include both
AVFoundation and the real libmpv/FFmpeg decoder. These names are Apple
signing profiles, not separate app editions. Vidrane Player is the
default interface, and Apple system controls remain optional.

## Implemented iOS modules

- Local file manager: nested directories, import, rename, copy, move,
  delete, sharing, sorting, searching, metadata and playlists.
- Playback: AVFoundation/Apple and Vidrane controls, Picture-in-Picture
  where available, subtitle/audio tracks, speed, gestures and resume.
- libmpv: alternative hardware/software decoder, advanced formats,
  custom controls and audio/subtitle settings.
- Network: HTTPS WebDAV, SFTP with verified SSH host key, and encrypted
  SMB3 shares, including directory browsing and basic operations.
- Direct network playback: native-compatible media through
  AVAssetResourceLoader; MKV and other libmpv formats via an internal
  localhost-only HTTP Range bridge from SMB3/SFTP/WebDAV sources.
- Foreground download queue: HTTPS, WebDAV, SFTP and SMB, with
  progress/cancel/retry, on-disk partial files and restoration after
  the app is relaunched. Transfers do not continue while iOS has
  terminated the app.
- Embedded web browser, settings, download manager, local watch
  history, subtitles and customizable playback behavior.

## Source structure

- crates/vidrane-core: Rust media, parsers, playback policies and tests.
- crates/vidrane-ffi: C ABI for platform frontends.
- ios/Vidrane/Sources: SwiftUI, AVKit, MPVKit and network integration.
- ios/mpv/prepare.sh: pinned MPVKit/libmpv XCFramework preparation.
- .github/workflows/ios.yml: dual unsigned IPA build.
- docs: architecture, networking, streaming, transfers and limitations.

## Build

Rust:

    cargo fmt --all -- --check
    cargo test --workspace
    cargo build --workspace --release

iOS device (macOS, Xcode, XcodeGen and Rust iOS target required):

    rustup target add aarch64-apple-ios
    bash ios/mpv/prepare.sh
    cd ios/Vidrane
    xcodegen generate
    xcodebuild -project Vidrane.xcodeproj -scheme VidranePersonal \
      -configuration Release -sdk iphoneos \
      -destination 'generic/platform=iOS' \
      VIDRANE_RUST_TARGET=aarch64-apple-ios \
      CODE_SIGNING_ALLOWED=NO build

Use VidraneDeveloper for the alternate Apple signing profile. The
unsigned artifacts require legitimate signing/provisioning for a phone.

## Documentation

- [Development roadmap and milestone checklist](docs/ROADMAP.md)
- [nPlayer Plus feature parity matrix](docs/NPLAYER_PARITY.md)

- [Architecture](docs/ARCHITECTURE.md)
- [Development status](docs/PHASE1.md)
- [Local file manager](docs/LOCAL_FILES.md)
- [Network providers](docs/NETWORK.md)
- [SMB3](docs/SMB.md)
- [SFTP security](docs/SFTP.md)
- [Remote libmpv playback](docs/REMOTE_STREAMING.md)
- [Persistent downloads](docs/TRANSFERS.md)
- [Player engines](docs/ENGINE.md)
- [Experimental and third-party codec licensing](docs/MPV_IOS.md)
- [Subtitles](docs/SUBTITLES.md)

## License and compatibility

Vidrane-owned source is MIT. The project uses no proprietary nPlayer
assets or code. AMSMB2/libsmb2, Citadel/NIOSSH, libmpv/FFmpeg and their
transitive code have independent license requirements; including LGPL
library replacement/relinking obligations, GPL configurations and
possible codec patents. Audit before public redistribution.

Vidrane is **not yet nPlayer Plus feature-complete**. Passing CI does
not prove that all networking, media formats, iOS hardware, battery or
Picture-in-Picture behavior works. Device tests remain postponed at the
user's request until broader functionality is complete.
