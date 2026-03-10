#!/bin/bash
set -euo pipefail

# MahisoftGALSync — Build, Sign, Notarize, Package
# Usage: ./build.sh [--skip-notarize]

SCHEME="MahisoftGALSync"
PROJECT="MahisoftGALSync.xcodeproj"
CONFIG="Release"
TEAM_ID="38V22VWG47"
BUNDLE_ID="com.mahisoft.MahisoftGALSync"
APP_NAME="MahisoftGALSync"

BUILD_DIR="build"
ARCHIVE_PATH="$BUILD_DIR/$APP_NAME.xcarchive"
EXPORT_PATH="$BUILD_DIR/export"
DMG_PATH="$BUILD_DIR/$APP_NAME.dmg"

SKIP_NOTARIZE=false
if [[ "${1:-}" == "--skip-notarize" ]]; then
    SKIP_NOTARIZE=true
fi

echo "=== Mahisoft GAL Sync Release Build ==="
echo ""

# Clean previous build
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# Step 0: Regenerate app icon from SF Symbols
echo "→ Generating app icon..."
swift Scripts/generate_icon.swift
echo "  Icons generated"

# Regenerate Xcode project so it picks up any structural changes
echo "→ Regenerating Xcode project..."
xcodegen generate --quiet
echo "  Project regenerated"

# Clear asset catalog cache so icons are always recompiled fresh
DERIVED_DATA_PATH="$BUILD_DIR/DerivedData"

# Step 1: Archive
echo "→ Archiving..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    -derivedDataPath "$DERIVED_DATA_PATH" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Manual \
    CODE_SIGN_IDENTITY="Developer ID Application" \
    ONLY_ACTIVE_ARCH=NO \
    | tail -3

echo "  Archive created at $ARCHIVE_PATH"

# Step 2: Export the .app from the archive
echo "→ Exporting .app..."

cat > "$BUILD_DIR/ExportOptions.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>developer-id</string>
    <key>teamID</key>
    <string>$TEAM_ID</string>
    <key>signingStyle</key>
    <string>automatic</string>
    <key>destination</key>
    <string>export</string>
</dict>
</plist>
PLIST

xcodebuild -exportArchive \
    -archivePath "$ARCHIVE_PATH" \
    -exportPath "$EXPORT_PATH" \
    -exportOptionsPlist "$BUILD_DIR/ExportOptions.plist" \
    | tail -3

APP_PATH="$EXPORT_PATH/$APP_NAME.app"
echo "  Exported to $APP_PATH"

# Verify signing
echo "→ Verifying code signature..."
codesign --verify --deep --strict "$APP_PATH"
echo "  Signature OK"

# Step 3: Notarize
if [ "$SKIP_NOTARIZE" = false ]; then
    echo "→ Creating ZIP for notarization..."
    ZIP_PATH="$BUILD_DIR/$APP_NAME.zip"
    ditto -c -k --keepParent "$APP_PATH" "$ZIP_PATH"

    echo "→ Submitting for notarization..."
    echo "  (This may take a few minutes)"
    xcrun notarytool submit "$ZIP_PATH" \
        --keychain-profile "notarytool" \
        --wait

    echo "→ Stapling notarization ticket..."
    xcrun stapler staple "$APP_PATH"
    echo "  Notarization complete"

    rm -f "$ZIP_PATH"
else
    echo "→ Skipping notarization (--skip-notarize)"
fi

# Step 4: Create DMG with a styled drag-to-Applications window
echo "→ Creating DMG..."
DMG_TEMP="$BUILD_DIR/dmg_staging"
DMG_RW="$BUILD_DIR/${APP_NAME}_rw.dmg"   # writable intermediate

mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

# Generate medium-grey background image for the DMG window
mkdir -p "$DMG_TEMP/.background"
swift Scripts/generate_dmg_bg.swift "$DMG_TEMP/.background/background.png"

# Create a writable DMG first so we can style the Finder window
hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDRW \
    "$DMG_RW" > /dev/null

# Mount it and style the window via AppleScript
# Use -mountpoint to get a predictable path (avoids " 2"/" 3" suffix conflicts)
MOUNT_POINT="$BUILD_DIR/dmg_mount"
mkdir -p "$MOUNT_POINT"
hdiutil attach "$DMG_RW" -readwrite -noverify -noautoopen -mountpoint "$MOUNT_POINT" > /dev/null

sleep 2  # give Finder time to register the volume

osascript - "$MOUNT_POINT" <<'APPLESCRIPT'
on run argv
    set mountPath to item 1 of argv
    tell application "Finder"
        set theVolume to disk (POSIX file mountPath as alias)
        tell theVolume
            open
            set current view of container window to icon view
            set toolbar visible of container window to false
            set statusbar visible of container window to false
            set the bounds of container window to {200, 120, 760, 420}
            set theViewOptions to the icon view options of container window
            set arrangement of theViewOptions to not arranged
            set icon size of theViewOptions to 128
            -- HFS-style path relative to the disk root (colon = path separator)
            set background picture of theViewOptions to file ".background:background.png" of theVolume
            set position of item "MahisoftGALSync.app" of container window to {155, 145}
            set position of item "Applications" of container window to {405, 145}
            close
            open
            update without registering applications
            delay 2
            close
        end tell
    end tell
end run
APPLESCRIPT

hdiutil detach "$MOUNT_POINT" > /dev/null
rmdir "$MOUNT_POINT" 2>/dev/null || true
sleep 1

# Convert to compressed read-only DMG
hdiutil convert "$DMG_RW" -format UDZO -o "$DMG_PATH" > /dev/null
rm -f "$DMG_RW"
rm -rf "$DMG_TEMP"

# Codesign the DMG
codesign --sign "Developer ID Application: Rick Little (38V22VWG47)" "$DMG_PATH" 2>/dev/null || true

echo ""
echo "=== Build Complete ==="
echo "  App:  $APP_PATH"
echo "  DMG:  $DMG_PATH"
echo ""
VERSION=$(defaults read "$(pwd)/$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
echo "  Version: $VERSION"
echo "  Ready for distribution!"
