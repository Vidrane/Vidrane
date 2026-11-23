# Media engine architecture

Both libmpv/FFmpeg and AVFoundation are included in the **main iOS
Personal and Developer builds**. There is no separate experimental flavor
and no feature-tier difference between signing profiles.

AVFoundation supports two UI presentations: default Vidrane controls and
optional Apple system AVPlayerViewController controls. A real MPVKit
adapter provides separate libmpv decoding with MPVGLView rendering.

The Rust shared core contains backend-selection policy, while the iOS
presentation host currently chooses an initial backend using user preference
and extension heuristics. A declared extension does not guarantee support
for its codec. A native playback failure offers libmpv retry.

Apple UI only works with AVPlayer. If the default Apple UI is selected and
decoder preference is automatic, the app starts native playback. Explicit
libmpv preference uses custom Vidrane libmpv controls. For protected
WebDAV streams the AVAssetResourceLoader transport is AVFoundation-only:
those sessions override libmpv preference and disable an invalid
libmpv fallback.

Within libmpv sessions Vidrane exposes playback speed, audio and subtitle
tracks, external text subtitle files, seek gestures, scale controls,
subtitle timing, and hardware VideoToolbox or software decoder preference.
Some operations use MPVCore and do not share the same player object as
AVFoundation. Watch history uses relative paths for local media.

The libmpv binary is sourced from pinned MPVKit upstream release files,
verified during CI. See [iOS build instructions](MPV_IOS.md).
Real-device playback, PiP, codec coverage and third-party license compliance
are not yet fully verified.
