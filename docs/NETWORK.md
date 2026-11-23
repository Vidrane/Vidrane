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

The URLSession adapter blocks redirects to avoid forwarding authorization
to an unknown destination. Returned DAV paths and generated child URLs
are constrained to the configured HTTPS origin and directory root.

MOVE and COPY send Overwrite: F. PUT sends If-None-Match: * to prevent
unintentional overwrites on compliant servers. Some servers ignore these
headers; there is no universal guarantee or cross-server transaction.

## Important limitations

- Basic auth and anonymous access only. No Digest/OAuth/bearer auth.
- Remote files are downloaded before playback. Authenticated streaming is
  not yet implemented.
- Uploads are foreground tasks with an activity indicator; upload progress
  is not yet in the shared Downloads queue.
- Downloads are not durable across application restarts and retry starts
  the transfer from scratch.
- Server-specific DAV behaviors can differ. These actions compile in CI
  but have not been tested against real WebDAV servers.
- Remote delete can be permanent. No trash/recycle bin, versions or undo.
- SMB, SFTP, NFS and DLNA are future providers.

## Architecture

Rust parses DAV multistatus replies. Swift handles URLSession, platform
Keychain and directory UI. Each request is checked against the stored
connection's HTTPS root and redirect policy.
