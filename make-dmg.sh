#!/bin/bash
# Build and package exactly the same app locally and in CI. Does not install it.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")" && pwd)"
VERSION="${1:-$(cat "$ROOT/VERSION")}"
BUILD_NUMBER="${2:-1}"
OUTPUT="${3:-$ROOT/dist/LocalServerWrapper-v${VERSION}.dmg}"
BUILD_ROOT="${LSW_BUILD_ROOT:-$ROOT/.build/distribution}"
[[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "Expected a version such as 0.1.0" >&2; exit 1; }
[[ "$BUILD_NUMBER" =~ ^[1-9][0-9]*$ ]] || { echo "Expected a positive build number" >&2; exit 1; }
SIGN_FLAGS=(CODE_SIGN_IDENTITY=- CODE_SIGN_STYLE=Manual CODE_SIGNING_REQUIRED=YES CODE_SIGNING_ALLOWED=YES DEVELOPMENT_TEAM=)
mkdir -p "$BUILD_ROOT" "$(dirname "$OUTPUT")"
xcodebuild -project "$ROOT/ServerAppBundle/ServerAppBundle.xcodeproj" -scheme ServerAppBundle \
    -configuration Release -derivedDataPath "$BUILD_ROOT/runtime" -destination 'generic/platform=macOS' \
    build "${SIGN_FLAGS[@]}" ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64'
xcodebuild -project "$ROOT/LocalServerWrapper/LocalServerWrapper.xcodeproj" -scheme LocalServerWrapper \
    -configuration Release -derivedDataPath "$BUILD_ROOT/manager" -destination 'generic/platform=macOS' \
    -disableAutomaticPackageResolution build "${SIGN_FLAGS[@]}" ONLY_ACTIVE_ARCH=NO ARCHS='arm64 x86_64' \
    MARKETING_VERSION="$VERSION" CURRENT_PROJECT_VERSION="$BUILD_NUMBER"
APP="$BUILD_ROOT/manager/Build/Products/Release/LocalServerWrapper.app"
"$ROOT/inject-sparkle-keys.sh" "$APP"
"$ROOT/embed-runtime.sh" "$APP" "$BUILD_ROOT/runtime/Build/Products/Release"
cp "$BUILD_ROOT/manager/SourcePackages/artifacts/sparkle/Sparkle/LICENSE" "$APP/Contents/Resources/Sparkle-LICENSE.txt"
cp "$ROOT/LICENSE" "$APP/Contents/Resources/LICENSE.txt"
cp "$ROOT/THIRD_PARTY_NOTICES.md" "$APP/Contents/Resources/THIRD_PARTY_NOTICES.md"
codesign --sign - --force --options runtime \
    --entitlements "$ROOT/LocalServerWrapper/LocalServerWrapper/LocalServerWrapper/LocalServerWrapper.entitlements" "$APP"
"$ROOT/scripts/verify-app.sh" "$APP" "$VERSION" "$BUILD_NUMBER"
STAGING="$(mktemp -d "$BUILD_ROOT/dmg.XXXXXX")"
trap 'rm -rf "$STAGING"' EXIT
ditto "$APP" "$STAGING/LocalServerWrapper.app"
ln -s /Applications "$STAGING/Applications"
cat > "$STAGING/README.txt" <<'TXT'
Local Server Wrapper - Installation

1. Drag LocalServerWrapper.app to Applications.
2. Open the app. If macOS blocks it, open System Settings > Privacy & Security
   and choose Open Anyway. Alternatively, run this command in Terminal:

   xattr -dr com.apple.quarantine /Applications/LocalServerWrapper.app

This app is ad-hoc signed and is not notarized by Apple.
Use Local Server Wrapper > Check for Updates to check for new versions.

Requires macOS 13.5 or later. Supports Apple Silicon and Intel Macs.
TXT
hdiutil create -srcfolder "$STAGING" -volname 'Local Server Wrapper' -fs HFS+ \
    -format UDZO -imagekey zlib-level=9 -ov "$OUTPUT"
hdiutil verify "$OUTPUT"
"$ROOT/scripts/verify-dmg.sh" "$OUTPUT" "$VERSION" "$BUILD_NUMBER"
echo "Created $OUTPUT"
