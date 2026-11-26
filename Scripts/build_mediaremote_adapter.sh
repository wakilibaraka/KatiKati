#!/bin/bash
# Compile Vendor/mediaremote-adapter into MediaRemoteAdapter.framework and embed it along with
# bin/mediaremote-adapter.pl into the app bundle (Frameworks/ and Resources/).
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
V="$ROOT/Vendor/mediaremote-adapter"
OUT_FRAMEWORKS="${1:-}"
OUT_RESOURCES="${2:-}"

if [ -z "$OUT_FRAMEWORKS" ] || [ -z "$OUT_RESOURCES" ]; then
  echo "usage: $0 <frameworks-dir> <resources-dir>" >&2
  exit 2
fi

if [ ! -d "$V/src" ] || [ ! -f "$V/bin/mediaremote-adapter.pl" ]; then
  echo "Vendor/mediaremote-adapter is missing" >&2
  exit 1
fi

FW_DIR="$OUT_FRAMEWORKS/MediaRemoteAdapter.framework"
VER_DIR="$FW_DIR/Versions/A"
BIN_PATH="$VER_DIR/MediaRemoteAdapter"
RES_DIR="$VER_DIR/Resources"
HDR_DIR="$VER_DIR/Headers"

mkdir -p "$RES_DIR" "$HDR_DIR" "$OUT_RESOURCES"

# Rebuild only if the framework binary is missing or older than any vendored source/header.
needs_build=0
if [ ! -f "$BIN_PATH" ]; then
  needs_build=1
else
  for f in "$V/include/MediaRemoteAdapter.h" "$V/src/adapter/"*.h "$V/src/adapter/"*.m "$V/src/private/"*.h "$V/src/private/"*.m "$V/src/utility/"*.h "$V/src/utility/"*.m "$V/src/test/NowPlayingTest.h"; do
    if [ "$f" -nt "$BIN_PATH" ]; then
      needs_build=1
      break
    fi
  done
fi

if [ "$needs_build" = 1 ]; then
  ARCH_FLAGS=()
  for arch in ${ARCHS:-$(uname -m)}; do
    ARCH_FLAGS+=(-arch "$arch")
  done

  SDK_FLAGS=()
  if [ -n "${SDKROOT:-}" ]; then
    SDK_FLAGS+=(-isysroot "$SDKROOT")
  else
    SDK_FLAGS+=(-isysroot "$(xcrun --show-sdk-path --sdk macosx)")
  fi

  DEPLOY_TARGET="${MACOSX_DEPLOYMENT_TARGET:-15.0}"

  /usr/bin/clang \
    -dynamiclib \
    "${ARCH_FLAGS[@]}" \
    "${SDK_FLAGS[@]}" \
    "-mmacosx-version-min=${DEPLOY_TARGET}" \
    -fobjc-arc \
    -fvisibility=default \
    -O2 \
    -I"$V/include" \
    -I"$V/src" \
    -framework Foundation \
    -framework AppKit \
    -framework ImageIO \
    -framework UniformTypeIdentifiers \
    -install_name "@rpath/MediaRemoteAdapter.framework/Versions/A/MediaRemoteAdapter" \
    "$V/src/adapter/commands.m" \
    "$V/src/adapter/env.m" \
    "$V/src/adapter/get.m" \
    "$V/src/adapter/globals.m" \
    "$V/src/adapter/keys.m" \
    "$V/src/adapter/now_playing.m" \
    "$V/src/adapter/repeat.m" \
    "$V/src/adapter/seek.m" \
    "$V/src/adapter/send.m" \
    "$V/src/adapter/shuffle.m" \
    "$V/src/adapter/speed.m" \
    "$V/src/adapter/stream.m" \
    "$V/src/adapter/test.m" \
    "$V/src/private/MediaRemote.m" \
    "$V/src/utility/Debounce.m" \
    "$V/src/utility/helpers.m" \
    -o "$BIN_PATH"

  cp "$V/include/MediaRemoteAdapter.h" "$HDR_DIR/MediaRemoteAdapter.h"

  cat > "$RES_DIR/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDevelopmentRegion</key>
  <string>en</string>
  <key>CFBundleExecutable</key>
  <string>MediaRemoteAdapter</string>
  <key>CFBundleIdentifier</key>
  <string>com.vandenbe.MediaRemoteAdapter</string>
  <key>CFBundleInfoDictionaryVersion</key>
  <string>6.0</string>
  <key>CFBundleName</key>
  <string>MediaRemoteAdapter</string>
  <key>CFBundlePackageType</key>
  <string>FMWK</string>
  <key>CFBundleShortVersionString</key>
  <string>0.1</string>
  <key>CFBundleVersion</key>
  <string>0.1.0</string>
</dict>
</plist>
PLIST

  ln -sfn "A" "$FW_DIR/Versions/Current"
  ln -sfn "Versions/Current/MediaRemoteAdapter" "$FW_DIR/MediaRemoteAdapter"
  ln -sfn "Versions/Current/Resources" "$FW_DIR/Resources"
  ln -sfn "Versions/Current/Headers" "$FW_DIR/Headers"

  /usr/bin/codesign --force --deep --sign - "$FW_DIR"
fi

cp "$V/bin/mediaremote-adapter.pl" "$OUT_RESOURCES/mediaremote-adapter.pl"
chmod 755 "$OUT_RESOURCES/mediaremote-adapter.pl"
