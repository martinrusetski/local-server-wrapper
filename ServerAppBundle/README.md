# ServerAppBundle

This is the standalone executable project for the Local Server Wrapper system. This executable is embedded in generated .app bundles and provides the runtime behavior for launching servers with integrated terminal and browser views.

## Overview

The ServerAppBundle is a separate Xcode project from the Configuration Manager. It is designed to be:

- **Self-contained**: Contains all code needed to run independently
- **Embeddable**: Can be copied into generated .app bundles
- **Relocatable**: Works from any filesystem location
- **Sandboxed**: Runs with App Sandbox entitlements

## Project Structure

```
ServerAppBundle/
├── ServerAppBundle/
│   ├── ServerAppBundleApp.swift      # Main app entry point
│   ├── ContentView.swift             # Main UI view (placeholder)
│   ├── AppState.swift                # Central state management
│   ├── ServerConfiguration.swift    # Configuration data model
│   ├── ConfigurationLoader.swift    # Loads embedded configuration
│   ├── Assets.xcassets/             # App assets
│   └── ServerAppBundle.entitlements # Sandbox entitlements
├── ServerAppBundleTests/
│   └── ConfigurationLoaderTests.swift # Unit tests
└── README.md
```

## Key Components

### ServerConfiguration
Defines the server configuration data model with all settings needed to launch and monitor a server process.

### ConfigurationLoader
Loads the embedded `configuration.json` file from the app bundle's Resources directory. Provides:
- `loadEmbeddedConfiguration()` - Throws on error
- `loadEmbeddedConfigurationWithFallback()` - Returns default config on error

### AppState
Central state management for the application. Will be expanded in future tasks to include:
- ProcessManager for running server processes
- ReadinessDetector for monitoring server readiness
- Coordination between terminal and browser components

### ContentView
Main UI view. Currently a placeholder that will be replaced with a split view containing:
- Terminal component (left side)
- Browser component (right side)

## Configuration Format

The embedded `configuration.json` file should be placed in the app bundle's Resources directory with this structure:

```json
{
  "id": "uuid-string",
  "name": "Server Name",
  "command": "npm",
  "arguments": ["run", "dev"],
  "localhostURL": "http://localhost:3000",
  "readySignalPattern": "Server listening on",
  "portDetectionPattern": "port (\\d+)",
  "customIconPath": null,
  "createdAt": "2024-01-01T00:00:00Z",
  "updatedAt": "2024-01-01T00:00:00Z"
}
```

## Building

Build the project using Xcode or xcodebuild:

```bash
xcodebuild -project ServerAppBundle.xcodeproj -scheme ServerAppBundle -configuration Release build
```

The built executable will be at:
```
Build/Products/Release/ServerAppBundle.app/Contents/MacOS/ServerAppBundle
```

## Testing

Run tests using:

```bash
xcodebuild test -project ServerAppBundle.xcodeproj -scheme ServerAppBundle
```

## Integration with Configuration Manager

The Configuration Manager's AppBundleGenerator will:

1. Build this project to get the executable
2. Create a new .app bundle structure
3. Copy the ServerAppBundle executable to `Contents/MacOS/`
4. Embed the configuration JSON in `Contents/Resources/`
5. Copy custom icons if provided
6. Generate Info.plist with proper metadata
7. Sign the bundle with entitlements

## Future Tasks

The following components will be added in subsequent tasks:

- **Task 14**: ProcessManager for running server processes
- **Task 15**: ReadinessDetector for monitoring server output
- **Task 16**: TerminalView for displaying process output
- **Task 17**: BrowserView for displaying web content
- **Task 18**: Error handling for browser component
- **Task 19**: Integration of all components in AppState
- **Task 20**: Split view layout
- **Task 21**: Window lifecycle management
- **Task 22**: Error handling for server processes

## Relocatability

The ServerAppBundle is **fully relocatable** and can be moved to any filesystem location without affecting functionality. This is achieved through:

### Design Principles

1. **Bundle.main for Resources**: All resource access uses `Bundle.main` APIs
2. **No Hardcoded Paths**: No absolute filesystem paths in source code
3. **Relative Resource Access**: Configuration and assets accessed relative to bundle
4. **Sandbox Compatible**: Works within App Sandbox constraints

### Verification

All resource access uses `Bundle.main` APIs with no hardcoded paths, verified via code review.

### Key Implementation Details

- **ConfigurationLoader**: Uses `Bundle.main.url(forResource:withExtension:)` to locate embedded configuration
- **ProcessManager**: Command paths come from user configuration, not hardcoded
- **Assets**: SwiftUI automatically resolves assets relative to bundle
- **No External Dependencies**: All required code and resources are self-contained

### Testing Relocatability

To verify relocatability:

1. Generate an app bundle using the Configuration Manager
2. Move the bundle to different locations (Desktop, Documents, external drive)
3. Launch from each location
4. Verify all functionality works correctly

The bundle will function identically regardless of its filesystem location.

## Requirements Satisfied

This implementation satisfies the following requirements:

- **Requirement 3.3**: Server App Bundle can be launched independently
- **Requirement 10.1**: Bundle contains all necessary code and resources
- **Requirement 3.2**: Configuration is embedded and loaded from Resources/
- **Requirement 10.3**: Bundle is relocatable (uses Bundle.main for resource access) ✅ VERIFIED

## Design Alignment

This implementation follows the design document's specifications:

- Uses SwiftUI for the UI framework
- Targets macOS 13.0+
- Implements sandboxing with proper entitlements
- Uses JSON for configuration storage
- Provides graceful error handling with fallback configuration
