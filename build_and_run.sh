#!/bin/bash
set -e

echo "🔨 Building ServerAppBundle (Release)..."
cd "$(dirname "$0")/ServerAppBundle"
xcodebuild -scheme ServerAppBundle -configuration Release -derivedDataPath build clean build

echo ""
echo "🔨 Building LocalServerWrapper (Release)..."
cd "$(dirname "$0")/LocalServerWrapper"
xcodebuild -scheme LocalServerWrapper -configuration Release -derivedDataPath build

echo ""
echo "🚀 Launching LocalServerWrapper..."
open build/Build/Products/Release/LocalServerWrapper.app

echo "✅ Done."
