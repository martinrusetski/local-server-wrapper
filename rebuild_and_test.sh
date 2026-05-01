#!/bin/bash

# Script to rebuild ServerAppBundle and test it

set -e  # Exit on error

echo "🔨 Building ServerAppBundle in Release mode..."
cd ServerAppBundle
xcodebuild -scheme ServerAppBundle -configuration Release -derivedDataPath build clean build
echo "✅ ServerAppBundle built successfully"

echo ""
echo "📦 Now you can:"
echo "1. Open LocalServerWrapper.app"
echo "2. Create a new configuration or edit an existing one"
echo "3. Generate a bundle - it will use the newly built ServerAppBundle"
echo ""
echo "Or run LocalServerWrapper from Xcode to test immediately."
