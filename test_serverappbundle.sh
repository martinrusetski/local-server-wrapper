#!/bin/bash

# Script to test ServerAppBundle directly from Xcode build

set -e

echo "🔨 Building ServerAppBundle..."
cd ServerAppBundle
xcodebuild -scheme ServerAppBundle -configuration Debug -derivedDataPath build build

echo ""
echo "📝 Creating test configuration..."
BUILD_DIR="build/Build/Products/Debug/ServerAppBundle.app/Contents/Resources"
mkdir -p "$BUILD_DIR"

cat > "$BUILD_DIR/configuration.json" << 'EOF'
{
  "name": "Test Server",
  "command": "python3",
  "arguments": ["-m", "http.server", "8080"],
  "localhostURL": "http://localhost:8080",
  "readySignalPattern": "Serving HTTP",
  "portDetectionPattern": null,
  "customIconPath": null
}
EOF

echo "✅ Configuration created"
echo ""
echo "🚀 Launching ServerAppBundle..."
echo "   Check Console.app or Xcode console for debug output"
echo ""

open "build/Build/Products/Debug/ServerAppBundle.app"

echo ""
echo "💡 To see logs:"
echo "   1. Open Console.app"
echo "   2. Search for 'ServerAppBundle'"
echo "   3. Or run: log stream --predicate 'process == \"ServerAppBundle\"' --level debug"
