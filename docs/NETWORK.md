# WebDAV and downloads

## What works in the iOS implementation

- Add named HTTPS WebDAV connections under Network -> Add WebDAV.
- Browse directories using WebDAV PROPFIND requests with Depth: 1.
- Parse DAV:multistatus XML in the shared Rust core.
- Connect anonymously or using HTTP Basic credentials over HTTPS.
- Store connection names, URLs and usernames in local preferences and
  passwords in iOS Keychain with a device-only accessibility policy.
- Download remote files into Vidrane's local Media directory and optionally
  open playable media after transfer.
- Queue direct HTTPS downloads and WebDAV downloads in the same Downloads tab;
  show transfer progress when the HTTP server reports a content length.
- Cancel, retry and remove transfers while the app remains open.
- Refuse HTTP redirects in listing and download operations to avoid
  forwarding authorization headers to an unknown origin.
- Constrain listed WebDAV hrefs to the configured HTTPS origin and root path.

## How to use

1. Add a connection with an HTTPS WebDAV folder URL, e.g. /remote.php/dav/files/user/.
2. Enter optional account credentials. Passwords go to Keychain.
3. Browse the directories under the new server.
4. Select a file: Download or Download and Play.
5. Check transfer progress in the Downloads tab.

## Limitations

- Standard DAV multistatus and 207 responses are expected; unconventional
  servers may require additional compatibility.
- Only HTTPS with Basic authentication (or anonymous access) is supported.
  Digest, OAuth, bearer tokens, client TLS certificates and custom proxies
  are not implemented.
- Authenticated WebDAV files are downloaded before playback: remote
  authenticated range streaming in AVFoundation is not implemented.
- Downloads run with foreground URLSession; there is no durable resumable
  transfer state after process termination. Retry starts from byte zero.
- Saved WebDAV credentials are not added to the transfer history. Active
  retries keep required request headers in process memory.
- Removing a server deletes its saved Keychain secret but does not alter a
  transfer that was already queued with its own in-memory request.
- These features compile in iOS CI but have not yet been exercised against
  real WebDAV services on a physical iPhone.

## Separation of responsibility

Rust handles the untrusted DAV XML document and protocol-neutral parsing.
Swift handles URLSession transport, HTTPS restrictions and platform Keychain.
The existing Rust provider registry describes shared provider implementations;
the new iOS-specific WebDAV adapter is an additional platform capability.
