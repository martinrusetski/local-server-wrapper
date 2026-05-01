# Simple Solution: Embed ServerAppBundle as a Resource

## The Problem
The current approach tries to find ServerAppBundle builds on disk, which is fragile and complicated. Debug builds have dylib dependencies that don't work in generated bundles.

## The Solution
Embed the ServerAppBundle executable directly into LocalServerWrapper.app as a resource. This is the standard approach used by professional apps.

## Implementation Steps

### 1. Build ServerAppBundle in Release Mode (One Time)
```bash
cd ServerAppBundle
xcodebuild -project ServerAppBundle.xcodeproj -scheme ServerAppBundle -configuration Release -derivedDataPath build clean build
```

This creates: `ServerAppBundle/build/Build/Products/Release/ServerAppBundle.app`

### 2. Add ServerAppBundle.app as a Resource to LocalServerWrapper

In Xcode:
1. Open `LocalServerWrapper.xcodeproj`
2. Select the **LocalServerWrapper** target
3. Go to **Build Phases** tab
4. Expand **Copy Bundle Resources**
5. Click the **+** button
6. Click **Add Other...** → **Add Files...**
7. Navigate to `ServerAppBundle/build/Build/Products/Release/ServerAppBundle.app`
8. Select it and click **Add**
9. Make sure "Copy items if needed" is **unchecked** (we want a reference)
10. Make sure it's added to the **LocalServerWrapper** target

### 3. Update the Code

The code will be simplified to just:
```swift
// Get the embedded ServerAppBundle.app from resources
guard let templateAppURL = Bundle.main.url(forResource: "ServerAppBundle", withExtension: "app") else {
    throw GenerationError.resourceCopyFailed("ServerAppBundle.app not found in bundle resources")
}

// Copy the executable from the embedded app
let sourceExecutableURL = templateAppURL.appendingPathComponent("Contents/MacOS/ServerAppBundle")
```

No searching, no path resolution, no Debug vs Release issues. Just copy from the embedded resource.

## Benefits
- ✅ **Simple**: No complex path searching
- ✅ **Reliable**: Always finds the executable
- ✅ **Self-contained**: LocalServerWrapper.app has everything it needs
- ✅ **No Xcode needed**: Users just run the app
- ✅ **No Debug build issues**: We control which build is embedded

## Distribution
When you distribute LocalServerWrapper.app, it will contain ServerAppBundle.app as a resource, so it works anywhere without needing Xcode or builds.
