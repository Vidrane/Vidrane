# Network support (iOS)

## Currently implemented

| Protocol | Browsing | Downloads | Direct playback | File mutations |
| --- | --- | --- | --- | --- |
| HTTPS | Direct URL | Durable queue | AVFoundation/libmpv by URL | — |
| WebDAV HTTPS | Yes | Durable queue | Native AVFoundation and libmpv via local Range relay | MKCOL, MOVE, COPY, DELETE, PUT |
| SFTP / SSH | Yes | Durable queue | Native AVFoundation and libmpv via local Range relay | Upload, mkdir, file/empty-dir delete |
| SMB3 encrypted | Yes | Durable queue | libmpv via local Range relay | Mkdir, file/empty-dir delete |

All transports are part of the same free Personal/Developer builds.
SMB1 and plaintext SMB2 downgrades are disabled in this stage.

## Architecture and verification

The shared Rust core parses untrusted WebDAV XML and validates
Content-Range. Swift implements networking and iOS Keychain.
SFTP requires a user-verified pinned SSH host public key. SMB requires
SMB3 encryption. WebDAV is HTTPS-only, with redirect blocking and a
configured root. libmpv uses an authenticated localhost-only HTTP
Range relay; see REMOTE_STREAMING.md.

Download state and partial files are restored after relaunch. See
TRANSFERS.md. SFTP account setup is described in SFTP.md, while
SMB configuration is in SMB.md.

These are source-code implementations. CI builds alone do not verify
real-world SMB/SFTP/WebDAV behavior, network performance, codecs or
iOS permissions. Real-device validation and a third-party license
audit remain required.

## Future network work

FTP, NFS, DLNA/UPnP, LAN discovery, public-key SSH user login, full
SMB file operations, persistent background uploads, richer connection
recovery and automatic remote transcoding are not yet implemented.
