# Local Server Wrapper

A macOS application for managing and launching local development servers with custom app bundles.

## Overview

Local Server Wrapper allows you to:
- Create and manage server configurations (command, arguments, ports)
- Generate standalone macOS app bundles for your servers
- Launch servers with a single click
- Monitor server status and output

## Project Structure

```
LocalServerWrapper/
├── LocalServerWrapper.xcodeproj/          # Xcode project
├── LocalServerWrapper/                    # Main app source code
│   ├── Models/                           # Data models
│   ├── Services/                         # Business logic
│   ├── ViewModels/                       # View models
│   ├── Views/                            # SwiftUI views
│   └── Utilities/                        # Helper utilities
├── LocalServerWrapperTests/              # Unit tests
├── LocalServerWrapperUITests/            # UI tests
└── HOW_TO_RUN.md                         # Running instructions
```

## Quick Start

### Running the App

1. Open the project in Xcode:
   ```bash
   open LocalServerWrapper/LocalServerWrapper.xcodeproj
   ```

2. Press `Cmd+R` to build and run

### Creating a Configuration

1. Click the "+" button in the toolbar
2. Fill in your server details:
   - **Name**: Display name for your server
   - **Command**: The executable (e.g., `npm`, `python3`)
   - **Arguments**: Command arguments (e.g., `run dev`)
   - **Localhost URL**: Where your server runs (e.g., `http://localhost:3000`)
   - **Icon** (optional): Custom icon for the app bundle
3. Click "Save"

### Managing Configurations

- **Edit**: Right-click → Edit, or swipe left
- **Delete**: Right-click → Delete, or swipe right
- **Generate App Bundle**: Right-click → Generate App Bundle
- **Search**: Use the search bar to filter configurations

## Development Status

### ✅ Completed (Tasks 1-12)
- Configuration CRUD operations
- Data validation and persistence
- SwiftUI user interface
- Icon processing
- Info.plist generation
- 76 unit tests passing

### ⏳ In Progress (Tasks 13-29)
- Server App Bundle executable implementation
- Server process management
- Status monitoring and logging

## Technical Details

- **Platform**: macOS 13.0+
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI
- **Architecture**: MVVM
- **Testing**: XCTest

## Configuration Storage

Configurations are saved to:
```
~/Library/Application Support/LocalServerWrapper/configurations.json
```

Automatic backups are created at:
```
~/Library/Application Support/LocalServerWrapper/configurations.json.backup
```

## Testing

Run tests in Xcode:
```bash
# All tests
xcodebuild test -project LocalServerWrapper/LocalServerWrapper.xcodeproj -scheme LocalServerWrapper

# Or press Cmd+U in Xcode
```

## Archived Files

The original Swift Package Manager project (which couldn't run GUI apps) has been archived to:
```
archive/LocalServerWrapper-SPM/
```

## Documentation

- [How to Run](LocalServerWrapper/HOW_TO_RUN.md) - Detailed running and testing guide
- [Requirements](.kiro/specs/local-server-wrapper/requirements.md) - Project requirements
- [Tasks](.kiro/specs/local-server-wrapper/tasks.md) - Implementation task list

## License

[Add your license here]

## Contributing

[Add contribution guidelines here]
