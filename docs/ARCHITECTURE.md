# Vidrane architecture

Vidrane is a free, open-source player with no subscriptions, paid tiers or
deliberately restricted features. Apple Personal and Developer are
provisioning profiles, not product versions.

## Core and platform integration

Rust provides format categories, resume policies, subtitles, DAV XML,
playback-engine selection, playlist and transfer-state rules through a C ABI.
SwiftUI implements iOS navigation and platform services: AVFoundation,
AVKit, Keychain, URLSession, WebKit and managed files.

- Local files live in a nested Documents/Media directory tree. Identifiers
  are relative paths; directory mutations update playlists/watch history.
- The native Vidrane and Apple presentations share an AVPlayer instance.
  Vidrane controls are the default; Apple is an optional UI mode.
- The optional MPVKit backend uses libmpv and FFmpeg, separate rendering
  and a separate decoder lifecycle. Switching engines recreates playback.
- WebDAV uses Rust parsing and Swift HTTPS transport for PROPFIND, file
  transfers and mutating operations, all scoped to one configured root.
- Personal and Developer build targets contain the same functionality;
  optional iOS entitlements require legitimate provisioning.

## Boundaries

SMB/SFTP, robust background transfers, advanced audio/HDR features,
libmpv PiP and other platform frontends are planned. Real-world codec
support, file operations and WebDAV behavior need physical-device testing.

No proprietary nPlayer code or graphics are distributed. MIT licensing
for Vidrane does not waive upstream codec licenses or patent obligations.
