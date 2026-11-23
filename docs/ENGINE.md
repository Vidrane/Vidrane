# Playback architecture

Both AVFoundation and libmpv/FFmpeg are compiled into the standard
Personal and Developer iOS builds. Vidrane Player is the default UI;
Apple AVPlayerViewController controls can be selected separately.

The native interface supports AVFoundation decoding and PiP on
compatible devices. The separate MPVKit backend uses libmpv's own
decoder and GPU surface, with playback/seek/speed, track and subtitle
selection, subtitle delay, video scaling and VideoToolbox or software
decoding. Apple AVPlayerViewController cannot control libmpv directly.

Native-compatible media can be streamed from authenticated WebDAV and
SFTP through AVAssetResourceLoader. A separate internal local-only
HTTP Range relay now allows libmpv to consume protected SMB, WebDAV
and SFTP file fragments without a full download; it is forced to
the Vidrane custom player UI. See REMOTE_STREAMING.md.

No production codec coverage or libmpv PiP has been validated. Video
extension heuristics are not guarantees of decoding support. See
MPV_IOS.md for build dependency details and third-party licensing.
