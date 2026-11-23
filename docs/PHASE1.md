# Vidrane: development status

Vidrane is fully free and open source, with no paid feature tiers.
Personal and Developer are Apple signing profiles, not app editions.

## Implemented in source

- Rust media, subtitle and WebDAV XML parsing; transfer, playlist,
  resume and decoder-selection policies.
- Six SwiftUI tabs, user settings and an integrated browser.
- Default Vidrane Player UI, optional native Apple system controls.
- AVFoundation playback with seek, speed, scaling, media selection and
  system PiP when supported.
- **libmpv + FFmpeg in both regular iOS builds**, not an optional IPA.
  Uses MPVKit and a verified, pinned XCFramework. Controls for pause,
  seek, double-tap, scaling, speed, track and subtitle selection, subtitle
  delay, and VideoToolbox or software decoding.
- SRT/WebVTT sidecar loading, in-app text captions and delay adjustments
  for AVFoundation. Libmpv supplies additional subtitle format handling.
- Nested local file manager: create/import/copy/move/rename/delete,
  share/search/sort/filter, path-stable playlists and watch history.
- SFTP: SSH pinned host keys, Keychain credentials, nested directory
  browsing, chunked file downloads/uploads, mkdir and guarded deletion.
  Direct AVFoundation playback of native-compatible SFTP media uses
  bounded reads without importing the full file.
- WebDAV browser: HTTPS Basic/Keychain, PROPFIND directory listing,
  MKCOL/MOVE/COPY/DELETE/PUT, authenticated downloads and native
  AVFoundation on-demand byte-range streaming for supported media.
- Unified foreground HTTPS/WebDAV/SFTP download queue with progress,
  cancellation and retry; SFTP uploads have not yet joined this queue.
- Main GitHub Actions generates unsigned Personal and Developer IPAs with
  identical libmpv and AVFoundation support.

## Still required before iPhone testing or parity claims

- Hardware validation of native/libmpv playback, codecs, battery, audio,
  VideoToolbox, PiP, subtitles and all local file operations.
- Real WebDAV integration tests (especially mutation/upload semantics).
- SMB/CIFS, FTP, NFS and DLNA/UPnP providers. SFTP still needs direct
  media streaming, public-key login, resumable transfers and rename/copy.
- Authenticated streaming for libmpv and broader media types such as MKV;
  native AVFoundation byte-range WebDAV streaming is implemented in source
  but still requires tests with real WebDAV servers.
- Persistent background and resumable downloads, richer upload reporting.
- libmpv PiP, video HDR/color/audio DSP features and source/license audit.
- Batch file management, trash/undo, archive extraction, bookmarks.
- Additional UI workflows, localization/accessibility and platform support.

## CI meaning

Rust tests and release builds run separately. Main macOS CI compiles and
packages the two libmpv-enabled unsigned IPA variants. Passing CI confirms
compilation and packaging, **not physical-device performance or licensed
public redistribution**. The user requested that installation and real
iPhone testing wait until the basic nPlayer Plus feature set is broader.
