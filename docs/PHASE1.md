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
