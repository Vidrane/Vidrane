# Vidrane architecture

Vidrane is one free open-source media player, with **no subscription or feature
tiers**. Personal and Developer are iOS signing configurations only; no Apple
Developer membership is required to access basic Vidrane features.

## Current vertical slice

iOS SwiftUI -> MediaLibrary / WatchHistory -> Rust C ABI (classification and
resume policy) -> AVFoundation (playback, audio/subtitle groups) -> AVKit or
custom AVPlayerLayer presentation.

- The **same AVPlayer** survives switching presentation to avoid restarting
  the track or losing the playback position.
- Vidrane presentation is the new-install default; Settings persists the
  user's chosen default. An in-player override remains session-local.
- AVKit controls use AVPlayerViewController and system PiP if the device and
  current playback session support it.
- Vidrane controls use AVPlayerLayer, custom seeking, scale and track menus,
  and AVPictureInPictureController for native PiP when available. Both
  modes use the same Apple decoding backend until Rust engine work lands.
- Rust functions decide whether a saved position is resumable or completed.
  Swift's WatchHistory owns the local JSON file, and MediaLibrary updates
  checkpoint keys on rename/deletion.
- SwiftUI code is a platform integration layer. Core provider abstractions,
  media metadata/queue policy and engine negotiation will move into Rust
  with future cross-platform frontends.
- Local storage is app-sandboxed; direct remote URLs require HTTPS; never
  bundle third-party signing credentials in the repository.

## System capabilities

The iOS application requests no speculative optional entitlements. Native
PiP and audio background modes are independent of the signer's membership.
CloudKit, APNs, and App Groups must be enabled only with suitable provisioning
and confirmed platform support. No iOS entitlement is bypassed.

## Roadmap boundaries

Network SMB/SFTP/FTP/WebDAV/NFS/DLNA file browsing, libmpv/FFmpeg codec
fallback, external subtitles and full background transfer support are pending.
The current Rust transfer registry is a policy layer, **not** a working
background download engine.

The reference nPlayer Plus walkthrough guided navigation and UX, but no
proprietary nPlayer assets, SDK or source code are redistributed. Open source
licensing does not waive third-party codec patents or trademark rights.
