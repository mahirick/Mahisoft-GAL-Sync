#!/bin/bash
set -euo pipefail

# MahisoftGALSync — Build, Sign, Notarize, Package
# Usage: ./build.sh [--skip-notarize]

SCHEME="MahisoftGALSync"
PROJECT="MahisoftGALSync.xcodeproj"
CONFIG="Release"
TEAM_ID="92KJ98262N"
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

# Step 1: Archive
echo "→ Archiving..."
xcodebuild archive \
    -project "$PROJECT" \
    -scheme "$SCHEME" \
    -configuration "$CONFIG" \
    -archivePath "$ARCHIVE_PATH" \
    -destination "generic/platform=macOS" \
    DEVELOPMENT_TEAM="$TEAM_ID" \
    CODE_SIGN_STYLE=Automatic \
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

# Step 4: Create DMG
echo "→ Creating DMG..."
DMG_TEMP="$BUILD_DIR/dmg_staging"
mkdir -p "$DMG_TEMP"
cp -R "$APP_PATH" "$DMG_TEMP/"
ln -s /Applications "$DMG_TEMP/Applications"

hdiutil create -volname "$APP_NAME" \
    -srcfolder "$DMG_TEMP" \
    -ov -format UDZO \
    "$DMG_PATH" \
    > /dev/null

rm -rf "$DMG_TEMP"

# Codesign the DMG too
codesign --sign "Developer ID Application: Rick Little ($TEAM_ID)" "$DMG_PATH" 2>/dev/null || true

echo ""
echo "=== Build Complete ==="
echo "  App:  $APP_PATH"
echo "  DMG:  $DMG_PATH"
echo ""
VERSION=$(defaults read "$(pwd)/$APP_PATH/Contents/Info.plist" CFBundleShortVersionString)
echo "  Version: $VERSION"
echo "  Ready for distribution!"
