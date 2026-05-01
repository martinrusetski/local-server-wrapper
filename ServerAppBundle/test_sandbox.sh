#!/bin/bash

# Test script to verify ServerAppBundle sandbox configuration
# This script checks if the app creates a container when launched

echo "=== ServerAppBundle Sandbox Configuration Test ==="
echo ""

# Build the app with proper code signing
echo "Building ServerAppBundle with code signing..."
xcodebuild -project ServerAppBundle/ServerAppBundle.xcodeproj \
    -scheme ServerAppBundle \
    -configuration Debug \
    clean build \
    CODE_SIGN_STYLE=Automatic \
    > /tmp/build.log 2>&1

if [ $? -ne 0 ]; then
    echo "❌ Build failed. Check /tmp/build.log for details"
    exit 1
fi

echo "✅ Build succeeded"
echo ""

# Find the built app
APP_PATH=$(find ~/Library/Developer/Xcode/DerivedData -name "ServerAppBundle.app" -type d | grep "Debug" | head -1)

if [ -z "$APP_PATH" ]; then
    echo "❌ Could not find built app"
    exit 1
fi

echo "Found app at: $APP_PATH"
echo ""

# Check entitlements in the built app
echo "Checking entitlements..."
codesign -d --entitlements /tmp/entitlements.xml "$APP_PATH" 2>&1
if [ -f /tmp/entitlements.xml ]; then
    echo "Entitlements file:"
    cat /tmp/entitlements.xml
    echo ""
    
    # Check for required entitlements
    if grep -q "com.apple.security.app-sandbox" /tmp/entitlements.xml; then
        echo "✅ App Sandbox entitlement found"
    else
        echo "❌ App Sandbox entitlement NOT found"
    fi
    
    if grep -q "com.apple.security.network.client" /tmp/entitlements.xml; then
        echo "✅ Network Client entitlement found"
    else
        echo "❌ Network Client entitlement NOT found"
    fi
    
    if grep -q "com.apple.security.network.server" /tmp/entitlements.xml; then
        echo "✅ Network Server entitlement found"
    else
        echo "❌ Network Server entitlement NOT found"
    fi
    
    if grep -q "com.apple.security.files.user-selected.read-write" /tmp/entitlements.xml; then
        echo "✅ User Selected Files entitlement found"
    else
        echo "❌ User Selected Files entitlement NOT found"
    fi
else
    echo "⚠️  No entitlements found (app may not be code signed)"
fi

echo ""
echo "=== Test Complete ==="
echo ""
echo "To verify container creation:"
echo "1. Launch the app: open \"$APP_PATH\""
echo "2. Check for container at: ~/Library/Containers/com.localserverwrapper.serverappbundle"
echo "3. The container should be created when the app launches"
