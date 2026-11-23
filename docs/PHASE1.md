# Vidrane development status

Vidrane is free and open-source. Personal and Developer refer only to
Apple account signing profiles; they are not different product tiers.
The default player interface remains Vidrane, with optional Apple
system controls and a selectable decoder.

## Implemented in source

- Rust core, C ABI, media classification, resume and playlists,
  subtitle parsing, WebDAV XML and strict HTTP Content-Range validation.
- Native SwiftUI tabs Local, Network, Playlists, Browser, Downloads and
  Settings, with nested local file management and path-stable history.
- AVFoundation media playback, customizable Vidrane controls,
  optional Apple presentation, PiP where supported, media tracks,
  gestures, scaling, speed and timed-text subtitles.
- Real libmpv/FFmpeg with VideoToolbox or software decoding, integrated
  into BOTH regular iOS unsigned IPA builds.
- HTTPS WebDAV with Keychain, protected downloads, file operations,
  AVFoundation streaming and libmpv remote MKV via byte-range relay.
- SFTP with host-key pinning, Keychain, remote browsing, limited file
  mutations, native AVFoundation media streaming and libmpv relay.
- SMB3 encrypted connection, manual share setup, browse/download,
  directory creation/removal and libmpv remote playback.
- Durable HTTPS/WebDAV/SFTP/SMB foreground download queue with local
  partial-file restoration and verified-offset continuation on relaunch.

## Still incomplete or unverified

- Real iPhone tests of all code paths, codecs, VideoToolbox, PiP,
  subtitles, battery and LAN permissions; real network-server tests.
- Compatibility beyond SMB3 encryption, SMB upload/rename, automatic
  share discovery, FTP, NFS and DLNA/UPnP.
- App-independent background transfers, persistent upload queue,
  robust network reconnection and full content integrity verification.
- libmpv Picture-in-Picture and advanced HDR/audio/color controls.
- Advanced library operations, archive extraction, accessibility,
  Android/desktop implementations and nPlayer Plus feature parity.
- Third-party LGPL/GPL/codec licensing and redistribution audit.

GitHub Actions tests/builds Rust and creates two unsigned iOS IPA
artifacts. Compilation is not proof of functionality on a device or
redistribution compliance. Per user's plan, iPhone testing is deferred
until further feature parity.
