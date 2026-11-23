# SFTP / SSH in Vidrane

The Network tab can save SSH/SFTP servers, browse directories, upload
and download files, create directories and delete files or empty
directories. A full verified OpenSSH host public key is mandatory before
connecting; there is no accept-all-key or silent first-use trust option.

## Setup

Enter hostname, TCP port (default 22), username, password and absolute
root path (default /), plus a verified ssh-ed25519 or ecdsa OpenSSH
host public key. Verify the key independently with the SSH server
administrator, not only with an unverified first connection.

Passwords live in Keychain; public host keys and non-secret connection
metadata are saved in app preferences. The connection checks canonical
remote paths to reduce risks of symlink escapes.

## Operations

- Navigate nested SFTP folders, excluding symlinks where reported.
- Download/upload in bounded SSH blocks; SFTP uploads are foreground
  operations with no shared upload progress UI yet.
- Create remote folders and delete files or EMPTY folders after
  confirmation. Recursive deletion and rename/copy are not supported.
- Play MP4/MOV/M4V or compatible audio directly with AVFoundation via
  a synthetic URL and random-access SFTP reads.
- Play MKV and other libmpv formats via the tokenized localhost-only
  Range relay without saving the entire file. This is a local proxy,
  not direct FFmpeg SSH support.
- Downloads share the durable HTTPS/WebDAV/SMB/SFTP queue and can
  recover partial files on the next launch after an offset comparison.

## Remaining limitations

No SSH user private-key authentication, full SFTP file operations,
true post-termination background downloads, persistent upload queue,
automatic reconnection or full remote-file hash verification.
Physical-device interoperability is still untested.

Citadel 0.11.0 and NIOSSH 0.3.2 are pinned in the XcodeGen project.
Their independent licenses and dependencies require review before
distribution.
