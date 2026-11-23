#!/usr/bin/env bash
# Prepare a pinned, source-visible MPVKit + Libmpv XCFramework.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
MPV_ROOT="$ROOT/vendor/libmpv-ios"
RELEASE="v0.1.2"
SOURCE_SHA="747cd35525cb7466475d8534b25480c8fe21c5ac"
ZIP_SHA256="ea5ca804e19167072493a3e2fc4c003c2eaec84dc123bb62248932c71a891807"
ZIP_URL="https://github.com/libmpv-ios/mpv-ios/releases/download/${RELEASE}/Libmpv.xcframework.zip"

mkdir -p "$ROOT/vendor"
if [[ ! -d "$MPV_ROOT/.git" ]]; then
  git clone --depth 1 --branch "$RELEASE" --single-branch \
    https://github.com/libmpv-ios/mpv-ios.git "$MPV_ROOT"
fi
ACTUAL_SHA="$(git -C "$MPV_ROOT" rev-parse HEAD)"
if [[ "$ACTUAL_SHA" != "$SOURCE_SHA" ]]; then
  echo "MPVKit source revision mismatch: $ACTUAL_SHA" >&2
  exit 1
fi

FRAMEWORK="$MPV_ROOT/MPVKit/Frameworks/Libmpv.xcframework"
if [[ ! -f "$FRAMEWORK/Info.plist" ]]; then
  ARCHIVE="$(mktemp -t vidrane-libmpv-XXXXXX.zip)"
  trap 'rm -f "$ARCHIVE"' EXIT
  curl --fail --location --retry 4 --connect-timeout 30 \
    --max-time 1200 --output "$ARCHIVE" "$ZIP_URL"
  echo "$ZIP_SHA256  $ARCHIVE" | shasum -a 256 --check
  mkdir -p "$MPV_ROOT/MPVKit/Frameworks"
  unzip -q "$ARCHIVE" -d "$MPV_ROOT/MPVKit/Frameworks"
fi
if [[ ! -f "$FRAMEWORK/Info.plist" ]]; then
  echo "Missing framework: $FRAMEWORK/Info.plist" >&2
  exit 1
fi

echo "Prepared main build MPVKit ${RELEASE} from ${SOURCE_SHA}"
