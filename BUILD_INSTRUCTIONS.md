# Build Instructions

## Building ServerAppBundle for Distribution

The generated app bundles need the **Release** build of ServerAppBundle to work properly. Debug builds have dependencies on Swift debug libraries that won't be included in the generated bundles.

### Option 1: Build from Xcode (Recommended)

1. Open `ServerAppBundle/ServerAppBundle.xcodeproj` in Xcode
2. Select **Product > Scheme > Edit Scheme...**
3. In the "Run" section, change **Build Configuration** from "Debug" to "Release"
4. Click **Close**
5. Build the project: **Product > Build** (⌘B)

Now when you run LocalServerWrapper from Xcode, it will find and use the Release build.

### Option 2: Build from Command Line

```bash
cd ServerAppBundle
xcodebuild -project ServerAppBundle.xcodeproj -scheme ServerAppBundle -configuration Release -derivedDataPath build clean build
```

This creates a Release build in `ServerAppBundle/build/Build/Products/Release/`

## Verifying the Build

To check if you have a Release build:

```bash
# Check workspace build folder
ls -la ServerAppBundle/build/Build/Products/Release/ServerAppBundle.app/Contents/MacOS/ServerAppBundle

# Check DerivedData
ls -la ~/Library/Developer/Xcode/DerivedData/ServerAppBundle-*/Build/Products/Release/ServerAppBundle.app/Contents/MacOS/ServerAppBundle
```

## Why Release Build?

- **Debug builds** depend on `@rpath/ServerAppBundle.debug.dylib` which isn't included in generated bundles
- **Release builds** only depend on system frameworks that are always available on macOS
- Release builds are also smaller and faster

## Current Status

✅ LocalServerWrapper: Sandbox disabled  
✅ ServerAppBundle: Sandbox disabled  
✅ Code updated to prefer Release builds  
⚠️ Need to build ServerAppBundle in Release mode
