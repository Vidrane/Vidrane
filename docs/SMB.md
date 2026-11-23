# SMB2/SMB3 in Vidrane

The iOS Network tab now supports manually configured SMB shares using
AMSMB2 4.0.3, backed by libsmb2. Both Personal and Developer builds
contain the same implementation.

## Connection configuration

Provide the hostname/IP, TCP port (default 445), share name, optional
domain and starting folder, username and password. Account passwords are
stored in the device-only iOS Keychain. Non-secret settings are persisted
in app preferences.

The current client requires SMB3 share encryption. SMB1 is deliberately
unsupported, and this version does not downgrade to unencrypted SMB2.
Older NAS devices that cannot negotiate encryption will fail to connect.
No automatic LAN discovery is implemented yet. iOS may ask for permission
to access the local network.

## Files and playback

- Browse nested folders, with checks on the configured share root.
- Download files into Vidrane's local library.
- Create folders; delete files or empty folders with user confirmation.
- Read bounded byte ranges for on-demand libmpv playback, including MKV,
  without pre-downloading the complete file.
- Recover partial SMB downloads on the next app launch after verifying
  the remote length and a sample of saved local bytes.

No SMB upload, rename, batch copy, share browsing or SMB1 support yet.
SMB symlink entries are excluded where identified by the server; a
malicious server changing paths mid-operation is outside the present
threat model. SMB encryption does not itself provide SSH-style host-key
pinning or equivalent server identity verification.

## Licensing and tests

AMSMB2 Swift code uses MIT, while libsmb2 has LGPL-2.1 obligations.
The package is linked as a dynamic framework; a compliant redistributable
release must separately review LGPL notices, replacement/relinking,
source distribution and all included dependencies.

The iOS CI verifies compilation and unsigned IPA packaging. Connection
compatibility, encryption negotiation, playback, LAN permissions and file
operations are not yet verified on a physical iPhone or SMB server.
