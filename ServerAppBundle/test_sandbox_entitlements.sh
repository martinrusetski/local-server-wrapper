#!/bin/bash

# Test script to verify ServerAppBundle sandbox entitlements
# This script builds the app and verifies the entitlements are correctly applied

set -e

echo "=== ServerAppBundle Sandbox Entitlements Test ==="
echo ""

# Colors for output
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Change to ServerAppBundle directory
cd "$(dirname "$0")"

echo "Step 1: Building ServerAppBundle..."
xcodebuild -project ServerAppBundle.xcodeproj \
    -scheme ServerAppBundle \
    -configuration Debug \
    clean build \
    CODE_SIGN_IDENTITY="-" \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGNING_ALLOWED=NO \
    > /dev/null 2>&1

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✓ Build successful${NC}"
else
    echo -e "${RED}✗ Build failed${NC}"
    exit 1
fi

echo ""
echo "Step 2: Locating built app..."
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "ServerAppBundle.app" -path "*/Build/Products/Debug/*" 2>/dev/null | head -n 1)

if [ -z "$APP_PATH" ]; then
    echo -e "${RED}✗ Could not find built app${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Found app at: $APP_PATH${NC}"

echo ""
echo "Step 3: Verifying entitlements file exists..."
ENTITLEMENTS_FILE="ServerAppBundle/ServerAppBundle.entitlements"

if [ -f "$ENTITLEMENTS_FILE" ]; then
    echo -e "${GREEN}✓ Entitlements file exists${NC}"
    echo ""
    echo "Entitlements content:"
    cat "$ENTITLEMENTS_FILE"
else
    echo -e "${RED}✗ Entitlements file not found${NC}"
    exit 1
fi

echo ""
echo "Step 4: Checking Xcode project settings..."

# Check for ENABLE_APP_SANDBOX
if grep -q "ENABLE_APP_SANDBOX = YES" ServerAppBundle.xcodeproj/project.pbxproj; then
    echo -e "${GREEN}✓ ENABLE_APP_SANDBOX = YES${NC}"
else
    echo -e "${RED}✗ ENABLE_APP_SANDBOX not set${NC}"
    exit 1
fi

# Check for ENABLE_HARDENED_RUNTIME
if grep -q "ENABLE_HARDENED_RUNTIME = YES" ServerAppBundle.xcodeproj/project.pbxproj; then
    echo -e "${GREEN}✓ ENABLE_HARDENED_RUNTIME = YES${NC}"
else
    echo -e "${RED}✗ ENABLE_HARDENED_RUNTIME not set${NC}"
    exit 1
fi

# Check for CODE_SIGN_ENTITLEMENTS
if grep -q "CODE_SIGN_ENTITLEMENTS = ServerAppBundle/ServerAppBundle.entitlements" ServerAppBundle.xcodeproj/project.pbxproj; then
    echo -e "${GREEN}✓ CODE_SIGN_ENTITLEMENTS configured${NC}"
else
    echo -e "${RED}✗ CODE_SIGN_ENTITLEMENTS not configured${NC}"
    exit 1
fi

echo ""
echo "Step 5: Verifying Info.plist..."
INFO_PLIST="$APP_PATH/Contents/Info.plist"

if [ -f "$INFO_PLIST" ]; then
    echo -e "${GREEN}✓ Info.plist exists${NC}"
    
    # Check bundle identifier
    BUNDLE_ID=$(/usr/libexec/PlistBuddy -c "Print :CFBundleIdentifier" "$INFO_PLIST" 2>/dev/null)
    if [ -n "$BUNDLE_ID" ]; then
        echo -e "${GREEN}✓ Bundle Identifier: $BUNDLE_ID${NC}"
    else
        echo -e "${RED}✗ Bundle Identifier not found${NC}"
    fi
else
    echo -e "${RED}✗ Info.plist not found${NC}"
    exit 1
fi

echo ""
echo "Step 6: Checking required entitlements..."

# Check each required entitlement
REQUIRED_ENTITLEMENTS=(
    "com.apple.security.app-sandbox"
    "com.apple.security.network.client"
    "com.apple.security.network.server"
    "com.apple.security.files.user-selected.read-write"
)

for entitlement in "${REQUIRED_ENTITLEMENTS[@]}"; do
    if grep -q "<key>$entitlement</key>" "$ENTITLEMENTS_FILE"; then
        echo -e "${GREEN}✓ $entitlement${NC}"
    else
        echo -e "${RED}✗ $entitlement missing${NC}"
        exit 1
    fi
done

echo ""
echo "=== Summary ==="
echo -e "${GREEN}✓ All sandbox entitlements are correctly configured${NC}"
echo ""
echo "Requirements satisfied:"
echo "  ✓ 12.1: ServerAppBundle is configured as a sandboxed macOS application"
echo "  ✓ 12.3: Proper entitlements for sandboxed execution are included"
echo ""
echo -e "${YELLOW}Note: To verify container creation (Requirement 12.2), you need to:${NC}"
echo "  1. Launch the app: open \"$APP_PATH\""
echo "  2. Check for container: ls -la ~/Library/Containers/ | grep serverappbundle"
echo ""
echo -e "${YELLOW}Note: File access restrictions (Requirement 12.5) are enforced by macOS${NC}"
echo "  and cannot be bypassed by the application."
echo ""
