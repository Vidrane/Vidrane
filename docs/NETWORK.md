# WebDAV and transfers (iOS)

## Implemented HTTP/DAV operations

- HTTPS connections with optional Basic authorization, with credentials
  saved to iOS Keychain.
- PROPFIND Depth: 1 and shared Rust DAV XML parser for directory browsing.
- GET downloads: authenticated WebDAV and public HTTPS URLs use the shared
  foreground transfer queue with progress, cancel and retry.
- MKCOL creates remote directories.
- MOVE renames remote files or directories.
- COPY creates a duplicate within the same remote folder.
- DELETE removes files or directories after UI confirmation.
- PUT uploads files from the iOS Files picker to the current remote folder.
- AVFoundation streaming of authenticated MP4/MOV/M4V and compatible audio
  files using bounded HTTPS Range requests, without importing the full file.

The URLSession adapter blocks redirects to avoid forwarding authorization
to an unknown destination. Returned DAV paths and generated child URLs
are constrained to the configured HTTPS origin and directory root.

MOVE and COPY send Overwrite: F. PUT sends If-None-Match: * to prevent
unintentional overwrites on compliant servers. Some servers ignore these
headers; there is no universal guarantee or cross-server transaction.

## Important limitations

- Basic auth and anonymous access only. No Digest/OAuth/bearer auth.
- Authenticated streaming is currently AVFoundation-only and restricted to
  formats/extensions known to be plausible with Apple's native decoder. It
  is not a libmpv WebDAV transport or general MKV streaming adapter.
- The server MUST support byte-range GET (HTTP 206 with a correct
  Content-Range), including seeking. If it returns 200 for the one-byte
  probe, the app declines streaming instead of downloading the whole file.
- Media must remain accessible during playback; server-side changes and
  network interruptions can interrupt decoding.
- Uploads are foreground tasks with an activity indicator; upload progress
  is not yet in the shared Downloads queue.
- Downloads are not durable across application restarts and retry starts
  the transfer from scratch.
- Server-specific DAV behaviors can differ. These actions compile in CI
  but have not been tested against real WebDAV servers.
- Remote delete can be permanent. No trash/recycle bin, versions or undo.
- SMB, SFTP, NFS and DLNA are future providers.

## Architecture

Rust parses DAV multistatus replies and strictly validates HTTP
Content-Range through C ABI tests. Swift handles URLSession, platform
Keychain, directory UI and AVAssetResourceLoader. The streaming adapter
uses ephemeral URLSession requests for at most 256 KiB at a time and
rejects HTTP redirects. Server credentials exist only in process memory;
the AVURLAsset uses a synthetic URL without secrets. Streaming closes
pending network work when the playback view is dismissed. Remote streams
are excluded from local watch history.
