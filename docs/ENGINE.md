# Playback engine architecture

Vidrane has a native iOS AVFoundation decoder and two possible presentations
for it: the default Vidrane Player UI and the optional Apple system UI.

The Rust shared core defines an explicit selection policy, which never
treats an absent backend as available. In the native iOS app, only
AVFoundation is compiled. An experimental separate iOS build now compiles
a real libmpv backend (using MPVKit) if the pinned framework and sources
are prepared correctly. See [experimental iOS libmpv](MPV_IOS.md).

The libmpv variant has its own MPVCore lifecycle and MPVGLView rendering
surface, rather than reusing AVPlayer and pretending to extend codecs.
Settings expose automatic/native/libmpv preference only when available.
The app displays AVFoundation errors and offers a manual libmpv fallback.

Do not equate an extension such as .mkv with guaranteed codec compatibility;
automatic routing starts from a heuristic and actual success depends on
the decoder, device and content. PiP is not yet implemented for libmpv.

The optional prebuilt dependency has independent GPL/LGPL source and binary
license obligations that require a pre-distribution audit.
