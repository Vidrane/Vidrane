# Vidrane architecture

One free, open-source application. Apple Personal/Developer are signing
profiles without paid feature differences.

## Modules

- Rust shared core + C ABI: media types, playlist/transfer state,
  subtitles, resume behavior, WebDAV XML and HTTP Range validation.
- SwiftUI: six-tab interface, preferences, media library with nested
  folders, WebKit browser and native iOS file integrations.
- Native media: AVFoundation with Vidrane or Apple presentation.
- libmpv: independently linked MPVKit decoder and render surface,
  included in both standard iOS IPA build configurations.
- Remote network: WebDAV HTTPS with Keychain, SFTP with SSH host-key
  pinning, SMB3 with share encryption and Keychain. A localhost-only,
  randomly tokenized HTTP byte-range bridge serves remote fragments
  to libmpv. Native AVAssetResourceLoader supports compatible WebDAV
  and SFTP media streams.
- Transfers: persisted journal and .part files in Application Support;
  credential and signed URL secrets in Keychain; resumed foreground
  downloads after relaunch with limited remote-content verification.

## Security and distribution constraints

Network transports reject unsupported or unsafe modes where identified.
SMB3 encryption is required; there is no SMB1 fallback. The local relay
is bound to 127.0.0.1 and requires an unpredictable per-session token.
A third-party codec and LGPL/GPL licensing review is needed before
redistributing a public signed app. Real iOS hardware and network
interoperability have not yet been validated.
