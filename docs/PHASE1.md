# Vidrane — development status

Implemented:
- Rust core for format classification, playlists, downloads state policy,
  playback resume, provider registry, backend selection policy and UTF-8
  SRT/WebVTT subtitle parsing with unit tests.
- C ABI to native frontends, including subtitle JSON allocation/free.
- Six-tab iOS interface, local file import, search, sorting, rename, share,
  delete and media information.
- Vidrane player controls by default; optional Apple controls using the
  same AVPlayer. Session-only player UI switching.
- Speed, seek gestures, scale, native PiP on supported devices, saved
  watch position and Continue Watching.
- Embedded AVFoundation audio and subtitle track selection where available.
- External SRT/VTT subtitles via sidecar discovery or Files picker.
  Synchronised text overlay and user-configurable subtitle typography.
- AVFoundation playback failure reporting; simple HTTPS playback/downloads;
  Playlists, WebKit browser and user settings.
- Personal and Developer iOS unsigned IPA targets using the same source.

Not implemented:
- Actual libmpv/FFmpeg codec backend, Dolby/DTS/HDR features beyond what
  AVFoundation provides, or automatic codec failover. See ENGINE.md.
- Advanced styled/bitmap subtitles, system PiP external captions. See
  SUBTITLES.md.
- SMB/SFTP/FTP/NFS/DLNA network browsing. An iOS HTTPS WebDAV client now supports
  folder navigation and authenticated downloads; real-server validation is pending.
- Persistent background transfers and resumable offsets across restarts.
  Foreground downloads now support progress, cancellation and retry.
- Full nPlayer Plus parity; Android and desktop frontends.

Validation:
- Rust CI checks formatting, unit tests and release build.
- macOS GitHub Actions builds two unsigned iOS app variants.
- Neither unsigned IPA can be installed without suitable code signing.
- Physical-device testing of decoder, PiP and subtitle behavior is pending.

Current network work: iOS WebDAV browsing, Keychain credentials, shared Rust DAV XML parsing, foreground transfer queue; see NETWORK.md. Testing on a physical device is intentionally deferred until broader basic feature coverage.
