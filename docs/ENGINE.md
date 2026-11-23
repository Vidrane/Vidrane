# Playback engine architecture

Both Vidrane controls and the optional Apple controls currently share the
same AVPlayer instance and AVFoundation decoding backend. Changing UI does
not alter codec support.

Rust now contains an explicit playback backend selection policy:
- Automatic: native decoding is preferred when the host reports support.
  It may fall back to an installed libmpv backend only if that decoder is
  actually present and supports the requested asset.
- Native-only: never silently selects libmpv.
- Libmpv-only: reports unavailable if the adapter is not installed.

IMPORTANT: libmpv and FFmpeg are not bundled or operating on iOS yet.
This policy is preparation for a real decoder adapter, not playback support.
The iOS player now surfaces AVFoundation errors rather than quietly showing
a black screen.

A complete integration still requires a reproducible iOS libmpv build, video
rendering, audio session and PiP integration, hardware decoding checks,
subtitles and track routing, license review and physical device validation.
