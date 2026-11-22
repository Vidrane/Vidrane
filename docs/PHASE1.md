# Phase 1 implementation status

Implemented in source:
- Rust core and FFI tests
- Six-tab iOS SwiftUI shell and importable local file library
- AVKit playback, native PiP support when iOS/device permits
- Playlists and basic persistent settings
- HTTPS streams, one-shot downloads and WebKit browsing
- Personal/Developer signing targets and unsigned build workflows

Verification pending:
- Successful macOS Xcode compilation
- Signing and physical device playback
- PiP and background audio in real device conditions

Future development (not currently supported):
- SMB/SFTP/WebDAV/NFS/UPnP remote browsing and credentials
- FFmpeg/libmpv backend, advanced audio/video/subtitle handling
- Gesture mappings, resume downloads, complete background transfers
- Android, Windows, Linux and macOS UI

Playback controls: Vidrane custom player is the default on fresh installs. Apple AVPlayerViewController is an optional interface. Settings chooses the default for future playback; the in-player switch is session-only. Both share one AVPlayer and AVFoundation codec support. Old explicitly saved Apple preferences are preserved.
