# Local Server Wrapper

A macOS app that turns local web servers — the kind you start in a terminal and use in a browser tab — into standalone Mac apps with their own icon, window, and lifecycle.

## Why this exists

A lot of useful software today runs as a local web server: AI tools like Open WebUI or ComfyUI, Jupyter notebooks, development servers, self-hosted utilities. Using them usually means the same routine — open a terminal, run a command, keep that terminal window alive, then find the right `localhost` tab among all your other browser tabs. Two things make this worse over time:

- **Tab and terminal clutter.** Each tool needs a running terminal plus a browser tab. Neither looks or behaves like an app: no dock icon, no Cmd+Tab entry, easy to close by accident, easy to forget the server is still running.
- **The localhost password pile.** Browser password managers group credentials by hostname, so every local tool's login lands under one "localhost" entry. Autofill offers you the wrong credentials, and saving new ones adds to the pile.

Some tools ship their own desktop app to solve this, but only for themselves. Browser features like Safari's "Add to Dock" give a local tool its own window, but the server still has to be started and stopped by hand in a terminal.

Local Server Wrapper handles both halves for any tool: each configured server becomes a real `.app` in your Applications folder. Opening it starts the server, waits until it's ready, and shows its web UI in its own window. Quitting the app shuts the server down. Credentials are stored per app in the macOS Keychain, so each tool keeps its own logins.

## Features

### Generated apps

- **One double-click to launch**: the app starts your server command, watches its output until the server is ready (including detecting the actual port if it differs from the configured one), then loads the web UI.
- **Clean shutdown**: quitting the app terminates the whole server process tree — no orphaned processes, no forgotten terminal windows.
- **Built-in terminal sidebar** (⌘⇧T): the server runs in a real pseudo-terminal, so you can watch its live output and interact with it when needed.
- **Per-app credentials**: logins are saved to the macOS Keychain under each app's own identity and matched by exact origin, so different tools never share or mix credentials.
- **Per-app browsing data**: each generated app is a separate macOS app, so cookies, sessions, and local storage are isolated from your browser and from other wrapped tools.
- **Browser-open interception**: when the server tries to open your default browser (many tools do this on startup), the URL is redirected into the app's own window instead.
- **Server restart** (⌘R), page reload (⌘⇧R), and back/forward navigation without leaving the app.

### Manager app

- Create, edit, search, and delete server configurations: name, command, arguments, URL, and a custom icon.
- Generate a standalone `.app` bundle from any configuration.
- Generated apps read their configuration live from a shared store, so editing a configuration in the manager takes effect the next time the generated app launches — no need to regenerate the bundle.
- Newly generated bundles are self-contained and carry a signed `ServerRuntime.framework` under `Contents/Frameworks`. This prevents launchers from resolving executable code from a user-home search path. Regenerate an existing launcher to move it to the self-contained format; the manager keeps updating the old shared runtime temporarily so legacy launchers continue to work during that transition.
- Configurations are persisted as JSON with automatic backups.

## Project Structure

```
LocalServerWrapper/                        # Manager app (Xcode project)
├── LocalServerWrapper/                   # Source: Models, Services, ViewModels, Views, Utilities
├── LocalServerWrapperTests/              # Unit tests
├── LocalServerWrapperUITests/            # UI tests
└── HOW_TO_RUN.md                         # Running instructions

ServerAppBundle/                           # Generated-app runtime (Xcode project)
├── ServerAppBundle/                      # Runtime source: process, terminal, web view, credentials
├── ServerRuntime/                        # Shared framework target wrapping the runtime
├── ServerLauncher/                       # Thin launcher stub embedded in generated bundles
└── ServerAppBundleTests/                 # Unit tests

docs/specs/local-server-wrapper/           # Requirements, design, and task documents
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

## Technical Details

- **Platform**: macOS 13.0+
- **Language**: Swift 5.9+
- **UI Framework**: SwiftUI (WKWebView for the embedded browser)
- **Architecture**: MVVM; generated bundles are thin launchers loading a shared runtime framework
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

The shared runtime framework is installed to:
```
~/Library/Frameworks/ServerRuntime.framework  # compatibility runtime for legacy thin launchers
```

## Testing

Run tests in Xcode:
```bash
# Manager app
xcodebuild test -project LocalServerWrapper/LocalServerWrapper.xcodeproj -scheme LocalServerWrapper

# Or press Cmd+U in Xcode
```

## Keyboard Shortcuts

### Manager: Configuration List
| Shortcut | Action |
|----------|--------|
| ⌘N | New Configuration |

### Manager: Configuration Editor
| Shortcut | Action |
|----------|--------|
| ⌘↩ | Save configuration |
| ⎋ | Cancel / Dismiss |

### Generated App
| Shortcut | Action |
|----------|--------|
| ⌘R | Restart server |
| ⌘⇧R | Reload page |
| ⌘[ | Back |
| ⌘] | Forward |
| ⌘⇧T | Toggle terminal sidebar |
| ⌥⌘T | Hide/show toolbar |

## Building

### Manager (Configuration Manager)
```bash
open LocalServerWrapper/LocalServerWrapper.xcodeproj
# Then press ⌘B or ⌘R
```

### ServerAppBundle (runtime for generated bundles)
The generated app bundles need a **Release** build of ServerAppBundle:
```bash
cd ServerAppBundle
xcodebuild -project ServerAppBundle.xcodeproj -scheme ServerAppBundle -configuration Release -derivedDataPath build clean build
```
This creates the Release build used when generating app bundles from the Configuration Manager.

## Documentation

- [How to Run](LocalServerWrapper/HOW_TO_RUN.md) - Detailed running and testing guide
- [Requirements](docs/specs/local-server-wrapper/requirements.md) - Project requirements
- [Design](docs/specs/local-server-wrapper/design.md) - Architecture and design
- [Tasks](docs/specs/local-server-wrapper/tasks.md) - Implementation task list
