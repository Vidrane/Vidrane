# Vidrane architecture

Vidrane is a single, free, open-source application. There are no Free, Lite, Plus, premium features or subscriptions.

## Implemented layers

- Shared Rust workspace: media classification and capability requirements in vidrane-core; a C ABI in vidrane-ffi.
- Native iOS UI: SwiftUI and AVKit, with six major tabs based on the supplied nPlayer Plus walkthrough.
- Local storage: copy Files picker imports into the sandbox; playlists persist as JSON.
- Network: direct HTTPS media playback and basic URLSession downloads, with WebKit browser.

## Personal and Developer signing

These are two Xcode targets compiled from one codebase. The profile is a deployment mechanism, not a product tier. Both default to empty optional entitlement files. App Groups, push and iCloud require separately configured Apple provisioning, entitlements and runtime checks; paid membership alone is insufficient. Unsigned CI IPAs cannot be installed without signing.

## Upcoming subsystems

Virtual filesystem (SMB, SFTP, FTP, WebDAV, NFS, DLNA), a libmpv/FFmpeg-backed codec fallback, subtitle/audio processing, advanced player settings, persistent and resumable transfer queues, and native Android/desktop clients.

None of these future features is represented as already operational. Open-source licensing does not automatically waive third-party codec patents.
