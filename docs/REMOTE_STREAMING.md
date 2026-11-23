# Remote streaming in Vidrane

## Native AVFoundation

AVFoundation-compatible MP4/MOV/M4V and common audio formats can play
directly from protected WebDAV or SFTP without a complete file download.
Each protocol provides bounded random-access reads to an
AVAssetResourceLoader using an opaque synthetic URL.

The Apple Player presentation remains optional. The Vidrane Player UI is
the default, independently of the AVFoundation/libmpv decoder setting.

## libmpv and additional formats

For SMB, SFTP and WebDAV the app now includes a local byte-range relay.
A protocol-specific client first authenticates to the remote share and
determines its file size. The relay binds only to 127.0.0.1 on an
ephemeral port and creates a unique unpredictable per-session 256-bit
token in the request path.

libmpv receives a local HTTP URL with the original media extension, so
it can recognize formats like MKV, AVI and WebM. Its HTTP Range requests
are translated into bounded SMB3, SSH/SFTP or authenticated HTTPS reads.
The remote password, user, share and full remote URI never appear in
the local player URL. Each request is checked against the session token
and the transport refuses external bindings. The relay is closed when
the libmpv session is torn down.

- HTTP GET and HEAD with single RFC-style byte ranges, including suffix
  ranges, are implemented by the local relay.
- The relay restricts concurrency and sends content in bounded chunks.
- WebDAV remote reads require HTTP 206 and valid Content-Range responses.
  Compressed HTTP responses are rejected for byte-accurate seeking.
- SFTP verifies the pinned SSH host key and server root.
- SMB requires an encrypted SMB3 share.
- Direct libmpv network playback always uses Vidrane's custom controls:
  Apple AVPlayerViewController cannot host a libmpv decoder.
- The existing AVFoundation and libmpv backends are both linked in the
  standard Personal and Developer IPA builds.

Limitations: this is application-proxy streaming, not a native mpv
SFTP/SMB filesystem driver. The relay works while the app and session
are active. No automatic stream reconnect/cache, libmpv PiP or hardware
codec guarantee is implied. Actual HDR, audio format compatibility,
seek latency and reliability need tests with real servers on an iPhone.
