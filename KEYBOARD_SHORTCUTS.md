# Keyboard Shortcuts

This document describes the keyboard shortcuts implemented in both applications.

## LocalServerWrapper (Configuration Manager)

### Configuration List View
- **⌘N** - New Configuration: Opens the configuration editor to create a new server configuration
- **⌘R** - Refresh: Reloads the configuration list from disk
- **⌘W** - Close Window: Standard macOS window close (system default)

### Configuration Editor View
- **⌘↩** (Command+Return) - Save: Saves the current configuration (only enabled when form is valid)
- **⎋** (Escape) - Cancel: Closes the editor without saving changes

### Additional Navigation
- **Tab** - Natural tab order follows the visual layout of form fields
- **Context Menu** - Right-click on configurations for Edit, Generate, and Delete options
- **Swipe Actions** - Swipe left/right on configurations for quick actions

## ServerAppBundle (Server App Bundle)

### Main Window
- **⌘R** - Restart Server: Restarts the server process (disabled while server is running)

### Browser Navigation
- **⌘[** - Go Back: Navigate to the previous page in browser history
- **⌘]** - Go Forward: Navigate to the next page in browser history
- **⇧⌘R** (Shift+Command+R) - Reload Page: Reloads the current page in the browser

### Alerts and Dialogs
- **⎋** (Escape) - Cancel: Cancels the close confirmation dialog
- **↩** (Return) - Confirm: Confirms the "Quit Anyway" action in close confirmation

## Design Principles

All keyboard shortcuts follow macOS conventions:
- Command (⌘) is used for primary actions
- Escape (⎋) cancels operations and dismisses sheets
- Return (↩) confirms actions in dialogs
- Shortcuts don't conflict with system-level shortcuts
- Disabled buttons don't respond to their shortcuts
- All shortcuts have corresponding accessibility labels and hints

## Accessibility

All keyboard shortcuts are fully accessible:
- Screen readers announce the availability of shortcuts
- Keyboard focus follows a logical tab order
- Visual feedback is provided for focused elements
- Shortcuts work consistently across the application
