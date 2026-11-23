# Phase 1 status (iOS-first)

## Implemented

- Rust core and ABI plus unit-tested media classification, playlist rules,
  transfer state machine and playback-resume policy.
- Six-tab SwiftUI application; local file import, search, filters, sorting,
  rename, share, deletion and media information.
- Two playback presentations using a single AVPlayer and AVFoundation engine.
  Vidrane controls are the default; Apple system controls are optional.
- In-player presentation switching affects that session only. The setting
  selects the default for later sessions.
- Custom Vidrane controls: pause/play, seek bar, skip 10 seconds, speed,
  fit/fill scaling, double-tap to seek on the left/right half of the video.
- AVFoundation media selection menus for **embedded** audio and subtitle tracks
  when those groups are exposed by the asset.
- Local watch-history checkpoints with automatic restore, Continue Watching
  library section, and history cleanup on rename/deletion.
- Watch history can be disabled (auto-resume) or cleared in Settings. Persisted
  data stays in the iOS application sandbox; no account is required.
- Playlists, direct HTTPS streams/downloads, a WebKit browser and baseline
  persistent settings.
- Personal and Developer signing targets built from the **same code**; unsigned
  IPA artifacts via GitHub Actions.

## Compatibility and limitations

- The player still depends on AVFoundation for decoding in both UI modes.
  A filename being recognized does not prove it is playable by Apple's codecs.
- The custom presentation does not yet have its own Picture-in-Picture button;
  the system presentation supports it on compatible devices.
- Embedded media selection depends on the asset. External ASS/SRT subtitles,
  font rendering, codec fallback and audio DSP are not yet implemented.
- Resume history is currently keyed to unique *imported local filenames*.
  Network streams are intentionally excluded. Almost-finished media is reset.
- Background downloading is not persistent or resumable yet.
- Network file providers (SMB/SFTP/FTP/WebDAV/NFS/DLNA) are planned and not
  represented as functional in the interface.

## Validation

- [x] Rust tests and release builds have run successfully on GitHub Actions.
- [x] Both unsigned iOS target builds completed on earlier phase-one commits.
- [ ] Confirm latest SwiftUI playback/selection changes on macOS CI.
- [ ] Run manual iPhone tests for media formats, playback controls,
  restore, subtitle options, orientation, PiP and interrupted downloads.
- [ ] Add dedicated UI/device tests once a stable physical test setup exists.

## Next milestones

1. Pluggable FFmpeg/libmpv-backed decoder with per-format diagnostics.
2. Virtual filesystem for network providers and persistent connections.
3. Advanced subtitles, media metadata and cover art.
4. Download manager with progress, cancellation, retry and resume.
5. Other-platform frontends built over shared Rust services.

Vidrane remains one completely free and open-source application; the Apple
signing profiles are technical deployment profiles, not feature tiers.
