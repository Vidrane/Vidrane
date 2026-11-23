# Durable download queue

Vidrane saves the foreground download queue to
Application Support/transfer-queue-v2.json. Partially received data is
stored in application-private TransferParts/*.part files.

When the application is restarted, any interrupted running records are
marked as waiting. The transfer center is reattached to the MediaLibrary
at launch and resumes waiting records, with at most two active downloads
at once. Failed and cancelled items retain a manual Retry option.
The Downloads tab shows HTTPS, WebDAV, SFTP or SMB as the source.

## Continuation rules

- HTTPS/WebDAV: GET with HTTP Range, strong ETag and If-Range where
  provided. HTTP Content-Range is checked by the shared Rust code.
  A server rejecting ranges, or returning a changed object, restarts
  at byte zero. When there is no strong ETag, a partial HTTP file is
  deliberately discarded instead of blindly appended.
- SFTP/SMB: establish a new authenticated connection and read the
  remote file length. Before continuing from the existing part length,
  compare the final 4 KiB of the local part with that remote offset.
  A mismatch discards the local part and begins again. This is only a
  limited comparison, NOT a cryptographic integrity guarantee against
  a remote file that changes elsewhere without changing its tail.
- Every provider writes chunks to disk rather than holding the whole
  file in memory. On completion Vidrane imports the file into its
  managed local media tree.
- Cancel retains partial data for retry; removing a record deletes
  its partial file and any associated stored URL.
- An interrupted automatic "download and play" action does not
  unexpectedly open the player on relaunch.

## Credentials and security

The queue JSON does not include SSH, SMB or WebDAV passwords or signed
HTTPS URLs. Provider credentials remain in the existing Keychain stores.
Full HTTPS URL strings, including private query tokens when present,
are saved under per-transfer keys in iOS Keychain and deleted when the
transfer finishes or is removed. HTTPS redirects are not followed and
the client requests identity encoding for byte-accurate ranges.

## Scope and limitations

This is reliable on-disk state restoration when the app is reopened,
NOT a background transfer service that continues after iOS kills the
application. Uploads are not yet integrated into this unified queue.
The compatibility of ETag/Range servers, SMB/SFTP version changes and
iOS data-protection behavior require physical-device tests.
