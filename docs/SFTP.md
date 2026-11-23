# SFTP/SSH support in Vidrane (initial iOS implementation)

Vidrane's Network tab can add SFTP servers, browse remote directories
and download files to the local media library, create directories,
upload files and remove files or empty directories. The SSH transport uses
Citadel 0.11.0 / NIOSSH 0.3.2. Both signing configurations ship the
same source and libraries; there is no paid SFTP tier.

## Adding a server

Enter hostname, TCP port (default 22), SSH username, password and
a configured absolute root directory (default "/"). You must also
supply a **verified OpenSSH host public key** of the form:

    ssh-ed25519 AAAAC3... comment
    ecdsa-sha2-nistp256 AAAAE2... comment

These lines are examples of syntax, not actual server keys. Retrieve
the public key through a channel independent of the connection you are
about to make; for instance, ask the server administrator for the
host's /etc/ssh/ssh_host_ed25519_key.pub and verify it independently.
Do not enter a private host key or your own private SSH key.

Citadel rejects mismatched server keys with a trusted-key SSH
handshake validator. There is no "accept any SSH host" option.

Passwords use iOS Keychain (device-only and accessible when unlocked).
The pinned *public* key, server name, hostname, user, port and root
directory are stored in app preferences. Removing a server erases its
stored password.

## Browsing and downloading

Open the SFTP connection from the Network tab, navigate directories,
and select Download or Download and Play. For every listing or file
transfer, the adapter creates an authenticated SSH connection and
closes it when the task completes.

Directory names are checked against relative traversal and separators.
The adapter resolves server-side canonical paths with SFTP realpath and
rejects paths outside the configured canonical root, including symlink
escapes. Directory entries identified as symlinks are excluded.

Downloads read 32 KiB SFTP chunks into an app-owned temporary file;
they do not load an entire media file into RAM. On completion the file
is imported into the managed media library, optionally opened with
the regular Vidrane decoder-selection policy.

## Not yet available

- Streaming SFTP media directly to AVFoundation/libmpv.
- SFTP remote rename, copy, recursive delete and advanced batch operations.
- Upload uses SSH_FXF_EXCL: compliant servers refuse to overwrite existing
  paths. Failed uploads may leave a partial file on the server.
- Remote removal of a directory is non-recursive (empty folders only),
  and the UI requires confirmation before any remote delete.
- Private-key user authentication and passwordless login.
- Progress, cancellation controls and durable resume in the shared
  download queue. The current browser shows a busy spinner.
- SMB/CIFS and the other network provider implementations.
- Interoperability tests against real SSH servers and iPhone validation.

## Reproducible build and licensing

The iOS XcodeGen project pins Citadel 0.11.0 and Joannis/swift-nio-ssh
0.3.2 as Swift packages. These have independent third-party licenses
and transitive dependencies. Audit them alongside libmpv/FFmpeg before
public redistribution.

Passing GitHub Actions establishes source compilation and packaging,
not host-key interoperability or physical-device playback.
