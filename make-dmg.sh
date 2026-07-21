#!/bin/bash
# Builds a distributable, ad-hoc-signed LocalServerWrapper.dmg locally — the same
# sequence the release workflow runs in CI, so you can test the artifact before
# tagging. Does NOT touch /Applications, ~/Library/Frameworks, or the appcast.
#
# Steps: build the runtime products → build the manager → inject Sparkle feed
# keys → embed the runtime products into the app → ad-hoc re-sign → package DMG.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_NAME="LocalServerWrapper"
APP_BUNDLE="${APP_NAME}.app"
VOL_NAME="Local Server Wrapper"
DMG_FINAL="${APP_NAME}.dmg"
STAGING="$SCRIPT_DIR/dmg_staging"
ENTITLEMENTS="$SCRIPT_DIR/LocalServerWrapper/LocalServerWrapper/LocalServerWrapper/LocalServerWrapper.entitlements"

WRAPPER_PRODUCTS="$SCRIPT_DIR/LocalServerWrapper/build/Build/Products/Release"
SERVER_PRODUCTS="$SCRIPT_DIR/ServerAppBundle/build/Build/Products/Release"
APP="$WRAPPER_PRODUCTS/$APP_BUNDLE"

echo "==> Building ServerAppBundle (runtime framework + thin launcher template)..."
( cd "$SCRIPT_DIR/ServerAppBundle" && xcodebuild -scheme ServerAppBundle -configuration Release -derivedDataPath build clean build )

echo "==> Building LocalServerWrapper (manager)..."
( cd "$SCRIPT_DIR/LocalServerWrapper" && xcodebuild -scheme LocalServerWrapper -configuration Release -derivedDataPath build clean build )

echo "==> Injecting Sparkle feed keys into Info.plist..."
"$SCRIPT_DIR/inject-sparkle-keys.sh" "$APP"

echo "==> Embedding ServerRuntime.framework + ServerAppBundle.app into the manager..."
"$SCRIPT_DIR/embed-runtime.sh" "$APP" "$SERVER_PRODUCTS"

echo "==> Ad-hoc re-signing the app (seals injected plist + embedded products)..."
codesign --sign - --force --options runtime \
    --entitlements "$ENTITLEMENTS" \
    "$APP"
codesign --verify --verbose "$APP"

echo "==> Assembling DMG staging..."
rm -rf "$STAGING"
mkdir -p "$STAGING"
cp -R "$APP" "$STAGING/"
ln -s /Applications "$STAGING/Applications"

cat > "$STAGING/README.txt" << 'TXTEOF'
Local Server Wrapper — Installation

1. Drag LocalServerWrapper.app onto the Applications folder.

2. This app is not notarized, so macOS blocks it on first launch. To allow it,
   open Terminal and run:

     xattr -cr /Applications/LocalServerWrapper.app

   Then double-click the app to launch it.
   (Or use System Settings -> Privacy & Security -> Open Anyway.)

3. Future updates install automatically from within the app — you won't need to
   re-download this installer or repeat step 2.
TXTEOF

echo "==> Creating DMG..."
rm -f "$SCRIPT_DIR/$DMG_FINAL"
hdiutil create -srcfolder "$STAGING" -volname "$VOL_NAME" \
    -fs HFS+ -fsargs "-c c=64,a=16,e=16" \
    -format UDZO -imagekey zlib-level=9 \
    -ov "$SCRIPT_DIR/$DMG_FINAL"

rm -rf "$STAGING"

echo ""
echo "Done -> $DMG_FINAL"
echo "Open with: open '$DMG_FINAL'"
