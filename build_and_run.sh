#!/bin/bash
set -e

ROOT="$(cd "$(dirname "$0")" && pwd)"

echo "🔨 Building ServerAppBundle (Release)..."
cd "$(dirname "$0")/ServerAppBundle"
xcodebuild -scheme ServerAppBundle -configuration Release -derivedDataPath build clean build

echo ""
echo "🔨 Building LocalServerWrapper (Release)..."
cd "$(dirname "$0")/LocalServerWrapper"
xcodebuild -scheme LocalServerWrapper -configuration Release -derivedDataPath build

echo ""
echo "📦 Installing shared ServerRuntime.framework to ~/Library/Frameworks..."
mkdir -p "$HOME/Library/Frameworks"
rm -rf "$HOME/Library/Frameworks/ServerRuntime.framework"
cp -R "$ROOT/ServerAppBundle/build/Build/Products/Release/ServerRuntime.framework" "$HOME/Library/Frameworks/"

echo ""
echo "🚀 Launching LocalServerWrapper..."
open build/Build/Products/Release/LocalServerWrapper.app

echo "✅ Done."
