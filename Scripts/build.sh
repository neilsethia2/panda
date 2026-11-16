#!/bin/bash
# Builds Panda.app and Panda.dmg from source.
#
#   ./Scripts/build.sh
#
# Needs Xcode or the Xcode Command Line Tools (for swiftc, codesign, iconutil, hdiutil).
# Output lands in ./build.
#
# Optional environment variables:
#   PANDA_ARCHS="arm64 x86_64"     architectures to build (default: both, as one universal app)
#   PANDA_VERSION=1.0.0            version string written into the app
#   PANDA_SIGN_IDENTITY="Developer ID Application: Your Name (TEAMID)"
#                                  sign with a real certificate instead of an ad-hoc signature
#   PANDA_NOTARY_PROFILE=name      notarytool keychain profile; notarises and staples the DMG
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

VERSION="${PANDA_VERSION:-1.0.0}"
BUILD_NUMBER="${PANDA_BUILD:-$(date +%Y%m%d%H%M)}"
ARCHS="${PANDA_ARCHS:-arm64 x86_64}"
MIN_OS="13.0"
BUILD="$ROOT/build"
OBJ="$BUILD/obj"
APP="$BUILD/Panda.app"

echo "==> Cleaning"
rm -rf "$BUILD"
mkdir -p "$OBJ"

SDK="$(xcrun --sdk macosx --show-sdk-path)"
echo "==> SDK: $SDK"
xcrun swiftc --version 2>&1 | head -2

compile() {
  local arch="$1" module="$2" out="$3"
  shift 3
  echo "==> Compiling $module ($arch)"
  xcrun swiftc \
    -O -whole-module-optimization \
    -swift-version 5 \
    -sdk "$SDK" \
    -target "${arch}-apple-macos${MIN_OS}" \
    -module-name "$module" \
    -o "$out" \
    "$@"
}

APP_BINARIES=()
HOST_BINARIES=()
for arch in $ARCHS; do
  compile "$arch" Panda "$OBJ/Panda-$arch" -parse-as-library Sources/Shared/*.swift Sources/Panda/*.swift
  compile "$arch" PandaHost "$OBJ/panda-host-$arch" Sources/Shared/*.swift Sources/Host/*.swift
  APP_BINARIES+=("$OBJ/Panda-$arch")
  HOST_BINARIES+=("$OBJ/panda-host-$arch")
done

echo "==> Assembling Panda.app"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"
lipo -create "${APP_BINARIES[@]}" -output "$APP/Contents/MacOS/Panda"
lipo -create "${HOST_BINARIES[@]}" -output "$APP/Contents/MacOS/panda-host"
chmod 755 "$APP/Contents/MacOS/Panda" "$APP/Contents/MacOS/panda-host"

sed -e "s/__VERSION__/$VERSION/" -e "s/__BUILD__/$BUILD_NUMBER/" Resources/Info.plist > "$APP/Contents/Info.plist"
printf 'APPL????' > "$APP/Contents/PkgInfo"

echo "==> Icon"
ICONSET="$OBJ/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
  double=$((size * 2))
  sips -z "$size" "$size" Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
  sips -z "$double" "$double" Resources/AppIcon-1024.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"

echo "==> Browser extension"
cp -R Extension/chrome "$APP/Contents/Resources/ChromeExtension"

echo "==> Signing"
if [ -n "${PANDA_SIGN_IDENTITY:-}" ]; then
  codesign --force --options runtime --timestamp --sign "$PANDA_SIGN_IDENTITY" "$APP/Contents/MacOS/panda-host"
  codesign --force --options runtime --timestamp --entitlements Resources/Panda.entitlements \
    --sign "$PANDA_SIGN_IDENTITY" "$APP"
else
  # Ad-hoc signature: enough for macOS to run it and remember its permissions.
  codesign --force --sign - "$APP/Contents/MacOS/panda-host"
  codesign --force --sign - "$APP"
fi
codesign --verify --deep --strict "$APP"
echo "    signature OK"

echo "==> Disk image"
STAGE="$OBJ/dmg"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/Panda.app"
ln -s /Applications "$STAGE/Applications"
cp Resources/READ-ME-FIRST.txt "$STAGE/Read me first.txt"
hdiutil create -volname "Panda" -srcfolder "$STAGE" -ov -format UDZO "$BUILD/Panda.dmg" >/dev/null

if [ -n "${PANDA_SIGN_IDENTITY:-}" ]; then
  codesign --force --timestamp --sign "$PANDA_SIGN_IDENTITY" "$BUILD/Panda.dmg"
  if [ -n "${PANDA_NOTARY_PROFILE:-}" ]; then
    echo "==> Notarising"
    xcrun notarytool submit "$BUILD/Panda.dmg" --keychain-profile "$PANDA_NOTARY_PROFILE" --wait
    xcrun stapler staple "$BUILD/Panda.dmg"
  fi
fi

echo
echo "Done."
echo "  App:        $APP"
echo "  Disk image: $BUILD/Panda.dmg"
lipo -info "$APP/Contents/MacOS/Panda"
