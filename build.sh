#!/bin/bash
set -euo pipefail

IOS_PROJECT="iOS/Rule34Swift.xcodeproj"
IOS_SCHEME="Rule34Swift"
MAC_PROJECT="macOS/Rule34SwiftMac.xcodeproj"
MAC_SCHEME="Rule34SwiftMac"
TARGET_APP_NAME="Rule34Swift-Unsigned.app"
IPA_NAME="Rule34Swift.ipa"

ROOT_DIR="$(pwd)"
BUILD_ROOT="$(mktemp -d /tmp/r34swift-build.XXXXXX)"
SYMROOT="$BUILD_ROOT/build"
DERIVED_DATA="$BUILD_ROOT/DerivedData"

cleanup() {
  rm -rf "$BUILD_ROOT"
}
trap cleanup EXIT

# Remove AppleDouble files that sometimes appear in shared folders.
find "$ROOT_DIR" -name "._*" -delete || true

# Selection menu or argument check
BUILD_TARGET=""
if [ $# -ge 1 ]; then
  case "$1" in
    iphone|ios)
      BUILD_TARGET="iphone"
      ;;
    mac|macos)
      BUILD_TARGET="mac"
      ;;
    *)
      echo "Unknown target: $1. Valid targets: iphone, mac"
      exit 1
      ;;
  esac
else
  echo "=== Select Build Target ==="
  echo "1) iPhone (iOS .ipa)"
  echo "2) Mac (native macOS .app)"
  read -rp "Enter choice [1-2]: " CHOICE
  case "$CHOICE" in
    1)
      BUILD_TARGET="iphone"
      ;;
    2)
      BUILD_TARGET="mac"
      ;;
    *)
      echo "Invalid choice: $CHOICE"
      exit 1
      ;;
  esac
fi

echo "=== Start project build ($BUILD_TARGET) ==="
echo "Using local temp build root: $BUILD_ROOT"

if [ "$BUILD_TARGET" = "iphone" ]; then
  # Build to local temp directories to avoid VMware Shared Folders I/O issues.
  xcodebuild clean build \
    -project "$IOS_PROJECT" \
    -scheme "$IOS_SCHEME" \
    -configuration Release \
    -sdk iphoneos \
    -destination 'generic/platform=iOS' \
    -derivedDataPath "$DERIVED_DATA" \
    SYMROOT="$SYMROOT" \
    OBJROOT="$BUILD_ROOT/obj" \
    SHARED_PRECOMPS_DIR="$BUILD_ROOT/precomp" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""

  echo "=== Build finished. Packaging IPA ==="

  APP_DIR="$SYMROOT/Release-iphoneos"
  cd "$APP_DIR" || { echo "Build output folder not found: $APP_DIR"; exit 1; }

  if [ -d "$IOS_SCHEME.app" ]; then
    mv "$IOS_SCHEME.app" "$TARGET_APP_NAME"
  fi

  echo "=== Applying ad-hoc signature ==="
  codesign --force --deep --sign - "$TARGET_APP_NAME"

  echo "=== Creating .ipa ==="
  mkdir -p Payload
  cp -r "$TARGET_APP_NAME" Payload/
  zip -vr "$IPA_NAME" Payload/
  rm -rf Payload

  mv "$IPA_NAME" "$ROOT_DIR/"

  echo "=== Done: $ROOT_DIR/$IPA_NAME ==="

elif [ "$BUILD_TARGET" = "mac" ]; then
  # Build the independent native macOS application.
  xcodebuild clean build \
    -project "$MAC_PROJECT" \
    -scheme "$MAC_SCHEME" \
    -configuration Release \
    -destination 'platform=macOS' \
    -derivedDataPath "$DERIVED_DATA" \
    SYMROOT="$SYMROOT" \
    OBJROOT="$BUILD_ROOT/obj" \
    SHARED_PRECOMPS_DIR="$BUILD_ROOT/precomp" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY=""

  echo "=== Build finished. Packaging macOS App ==="

  APP_DIR="$SYMROOT/Release"
  cd "$APP_DIR" || { echo "Build output folder not found: $APP_DIR"; exit 1; }

  TARGET_MAC_APP="$MAC_SCHEME.app"

  echo "=== Applying ad-hoc signature ==="
  codesign --force --deep --sign - "$TARGET_MAC_APP"

  # Keep native macOS build products alongside the macOS project.
  echo "=== Copying app to macOS/build ==="
  mkdir -p "$ROOT_DIR/macOS/build"
  rm -rf "$ROOT_DIR/macOS/build/$TARGET_MAC_APP"
  cp -R "$TARGET_MAC_APP" "$ROOT_DIR/macOS/build/"

  echo "=== Done: $ROOT_DIR/macOS/build/$TARGET_MAC_APP ==="
fi
