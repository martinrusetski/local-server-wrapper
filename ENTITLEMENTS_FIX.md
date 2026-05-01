# Entitlements File Not Found Fix

## Problem
When generating an app bundle, the process failed with the error:
```
Failed to sign app bundle: Entitlements file not found in bundle resources
```

## Root Cause
The `AppBundleGenerator.signBundle()` method was searching for the entitlements file in several locations, but none of them matched the actual location of the file in the workspace:

**Actual location**: `ServerAppBundle/ServerAppBundle/ServerAppBundle.entitlements`

**Previous search locations**:
1. Bundle resources (for deployed app)
2. Relative to executable: `../ServerAppBundle.entitlements`
3. Project root: `ServerAppBundle.entitlements`

None of these matched the actual nested path structure.

## Solution
Updated the entitlements file search logic to include the correct path:

```swift
// Try workspace root relative path
if entitlementsURL == nil {
    let currentDir = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    let candidatePath = currentDir.appendingPathComponent("ServerAppBundle/ServerAppBundle/ServerAppBundle.entitlements")
    if FileManager.default.fileExists(atPath: candidatePath.path) {
        entitlementsURL = candidatePath
    }
}
```

## Search Order (Updated)
The generator now searches for the entitlements file in this order:

1. **Bundle resources** - For deployed Configuration Manager app
   - `Bundle.main.url(forResource: "ServerAppBundle", withExtension: "entitlements")`

2. **Relative to executable** - For development builds
   - `<executable_dir>/../ServerAppBundle.entitlements`

3. **Project root (old path)** - Legacy location
   - `<current_dir>/ServerAppBundle.entitlements`

4. **Workspace nested path** - **NEW** - Actual location in workspace
   - `<current_dir>/ServerAppBundle/ServerAppBundle/ServerAppBundle.entitlements`

## Error Message Improvement
Also improved the error message to be more helpful:
```swift
throw GenerationError.signingFailed(
    "Entitlements file not found. Please ensure ServerAppBundle.entitlements exists in the project."
)
```

## Testing
To test the fix:
1. Open LocalServerWrapper app
2. Select a configuration (e.g., your SillyTavern configuration)
3. Click "Generate App Bundle"
4. Choose an output location
5. The bundle should now generate and sign successfully

## Build Status
✅ LocalServerWrapper builds successfully
✅ Entitlements file search logic updated
✅ Error message improved

## Next Steps
When you generate a bundle now, it should find the entitlements file and complete the signing process. If you still encounter issues, check:
- The entitlements file exists at `ServerAppBundle/ServerAppBundle/ServerAppBundle.entitlements`
- You have permission to read the file
- The current working directory is the workspace root when running the app
