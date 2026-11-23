#!/bin/bash
set -euo pipefail

IOS_PROJECT="iOS/Rule34Swift.xcodeproj"
IOS_SCHEME="Rule34Swift"
MAC_PROJECT="macOS/Rule34SwiftMac.xcodeproj"
MAC_SCHEME="Rule34SwiftMac"
TARGET_APP_NAME="Rule34Swift-Unsigned.app"
IPA_NAME="Rule34Swift.ipa"
DMG_NAME="Rule34SwiftMac.dmg"

ROOT_DIR="$(pwd)"
BUILD_ROOT="$(mktemp -d /tmp/r34swift-build.XXXXXX)"
SYMROOT="$BUILD_ROOT/build"
DERIVED_DATA="$BUILD_ROOT/DerivedData"

cleanup() {
  if [ -n "${DMG_MOUNT:-}" ]; then
    hdiutil detach -quiet "$DMG_MOUNT" >/dev/null 2>&1 || true
  fi
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
    github)
      BUILD_TARGET="github"
      ;;
    *)
      echo "Unknown target: $1. Valid targets: ios, mac, github"
      exit 1
      ;;
  esac
else
  echo "=== Select Build Target ==="
  echo "1) iPhone (iOS .ipa)"
  echo "2) Mac (native macOS .app)"
  echo "3) GitHub release files (iOS .ipa + macOS .dmg)"
  read -rp "Enter choice [1-3]: " CHOICE
  case "$CHOICE" in
    1)
      BUILD_TARGET="iphone"
      ;;
    2)
      BUILD_TARGET="mac"
      ;;
    3)
      BUILD_TARGET="github"
      ;;
    *)
      echo "Invalid choice: $CHOICE"
      exit 1
      ;;
  esac
fi

echo "=== Start project build ($BUILD_TARGET) ==="
echo "Using local temp build root: $BUILD_ROOT"

if [ "$BUILD_TARGET" = "iphone" ] || [ "$BUILD_TARGET" = "github" ]; then
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

fi

if [ "$BUILD_TARGET" = "mac" ] || [ "$BUILD_TARGET" = "github" ]; then
  # The iOS packaging step changes the working directory; resolve project paths from the repo root.
  cd "$ROOT_DIR"
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

  if [ "$BUILD_TARGET" = "github" ]; then
    echo "=== Creating macOS DMG ==="
    DMG_ROOT="$BUILD_ROOT/dmg-root"
    DMG_MOUNT="$BUILD_ROOT/dmg-mount"
    TEMP_DMG="$BUILD_ROOT/Rule34SwiftMac-rw.dmg"
    mkdir -p "$DMG_ROOT"
    ditto "$ROOT_DIR/macOS/build/$TARGET_MAC_APP" "$DMG_ROOT/$TARGET_MAC_APP"
    mkdir -p "$DMG_MOUNT"
    rm -f "$ROOT_DIR/$DMG_NAME"

    hdiutil create \
      -volname "Rule34Swift" \
      -srcfolder "$DMG_ROOT" \
      -ov \
      -format UDRW \
      "$TEMP_DMG"

    hdiutil attach \
      -readwrite \
      -noverify \
      -noautoopen \
      -mountpoint "$DMG_MOUNT" \
      "$TEMP_DMG"

    osascript - "$DMG_MOUNT" <<'APPLESCRIPT'
on run argv
  set mountFolder to POSIX file (item 1 of argv) as alias
  set applicationsFolder to POSIX file "/Applications" as alias

  tell application "Finder"
    make new alias file at mountFolder to applicationsFolder with properties {name:"Applications"}
  end tell
end run
APPLESCRIPT

    swift "$ROOT_DIR/macOS/Scripts/SetDMGApplicationsIcon.swift" "$DMG_MOUNT/Applications"

    osascript - "$DMG_MOUNT" <<'APPLESCRIPT'
on run argv
  set mountFolder to POSIX file (item 1 of argv) as alias
  tell application "Finder"
    open mountFolder
    set current view of front Finder window to icon view
    set toolbar visible of front Finder window to false
    set statusbar visible of front Finder window to false
    set bounds of front Finder window to {120, 100, 1020, 660}

    tell icon view options of front Finder window
      set arrangement to not arranged
      set icon size to 112
      set text size to 14
      set label position to bottom
      set background color to {43690, 58853, 42148}
    end tell

    set position of item "Rule34SwiftMac.app" of mountFolder to {225, 225}
    set position of item "Applications" of mountFolder to {690, 225}
    close front Finder window
  end tell
end run
APPLESCRIPT

    sync
    hdiutil detach -quiet "$DMG_MOUNT"
    DMG_MOUNT=""

    hdiutil convert "$TEMP_DMG" \
      -ov \
      -format UDZO \
      -o "$ROOT_DIR/$DMG_NAME"

    echo "=== GitHub release files ready ==="
    echo "iOS: $ROOT_DIR/$IPA_NAME"
    echo "macOS: $ROOT_DIR/$DMG_NAME"
  fi
fi
