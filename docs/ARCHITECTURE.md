# Vidrane architecture

One free and open-source application, with no subscription and no
Free/Lite/Plus functional tiers.

## Core and platform boundaries

- Rust: media types, playlist and download state rules, playback resume
  and decoder policy, subtitle parsing and DAV multistatus XML parsing.
  Exposed to iOS over a C ABI.
- iOS SwiftUI: app navigation, local Documents/Media tree, Keychain,
  URLSession/WebDAV, WebKit, AVKit, AVFoundation and MPVKit.
- Local media: nested folders with relative path identifiers. Moving
  or renaming also rewrites playlist and watch-history references.
- Network: HTTPS WebDAV with guarded read/write operations and protected
  HTTP Range playback through AVAssetResourceLoader for native-supported
  media. Rust validates Content-Range. SMB/SFTP and streaming via libmpv
  are planned.
- Playback: Vidrane default UI plus optional Apple system controls for
  AVPlayer/AVFoundation; a separate libmpv engine with its own rendering
  lifecycle and custom Vidrane controls. Both engines are linked in the
  standard iOS Personal and Developer builds.
- Main iOS CI prepares a pinned libmpv XCFramework with SHA-256 checking,
  then builds the same app code for both signing configurations.

## Restrictions and validation

Apple-specific entitlements and signing are not bypassed. Native PiP
availability depends on device/session; libmpv PiP is not implemented.
No physical-device playback or compatibility testing has been performed.
The nPlayer reference is design inspiration, not copied proprietary code.

MIT licensing for Vidrane sources does not override upstream library,
codec or patent obligations. See [MPV iOS](MPV_IOS.md).
