# Vidrane: development status

One open-source free application, with no paid feature tiers. Personal and
Developer are Apple signing profiles, not app editions.

## Implemented in source

- Rust media classification, subtitle and WebDAV parsers, playlist,
  transfer-state, resume and decoder-selection policies.
- Six SwiftUI tabs, settings and WebKit browser.
- Vidrane custom controls by default; optional Apple system interface.
- AVFoundation playback, PiP, playback controls, track selection and resume.
- Experimental independently linked libmpv/FFmpeg iOS variant with actual
  decoder context and OpenGL ES video rendering; builds in GitHub Actions.
- SRT/WebVTT sidecar and user-selected subtitle overlay with delay and style.
- Folder-aware local media manager: nested import, browse, copy, move,
  rename, delete, share, search, filter and sort.
- Relative-path playlist/history IDs updated after rename or move.
- WebDAV: HTTPS Basic/Keychain, PROPFIND browsing, downloads, MKCOL, MOVE,
  COPY, DELETE and PUT uploads.
- Unified foreground HTTPS/WebDAV download queue with progress, cancel and
  retry. Personal/Developer unsigned IPAs build from the same code.

## Still planned or unverified

- Physical-device verification of playback, codec support, PiP and battery.
- Real-server interoperability tests for WebDAV mutations and transfers.
- SMB/CIFS, SFTP/FTP, NFS and DLNA/UPnP providers.
- libmpv PiP and full HDR/Dolby Vision/Atmos/DTS behavior and license audit.
- Authenticated range streaming without downloading the entire file.
- Durable background downloads, resumable transfers and upload progress.
- Local trash/undo, batch actions, archive extraction and external bookmarks.
- Android/desktop frontends and broader nPlayer Plus feature parity.

GitHub Actions currently validates Rust and standard iOS unsigned builds.
The experimental libmpv workflow validates the dependency-based iOS variant.
A passing CI build does NOT mean hardware testing has been completed.
