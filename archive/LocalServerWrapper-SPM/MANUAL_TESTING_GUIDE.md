# Manual Testing Guide for Configuration Manager

## Running the Application

Since this is a SwiftUI macOS application built with Swift Package Manager, you have two options to run it:

### Option 1: Open in Xcode (Recommended)

1. **Open the project in Xcode:**
   ```bash
   cd LocalServerWrapper
   open Package.swift
   ```

2. **Select the target:**
   - In Xcode, select "LocalServerWrapper" as the scheme (top toolbar)
   - Make sure "My Mac" is selected as the destination

3. **Run the app:**
   - Press `Cmd + R` or click the Play button
   - The Configuration Manager window should appear

### Option 2: Build and Run from Terminal

```bash
cd LocalServerWrapper
swift build
open .build/debug/LocalServerWrapper.app
```

Note: The app may not launch properly from terminal due to macOS security restrictions. Xcode is the recommended approach.

## Manual Testing Checklist

### 1. Create a Configuration

**Test Case:** Create a new server configuration

**Steps:**
1. Click the "+" button in the toolbar (or use the "New Configuration" button if list is empty)
2. Fill in the form:
   - **Name:** "Test Node Server"
   - **Command:** "npm"
   - **Arguments:** "run dev"
   - **Localhost URL:** "http://localhost:3000"
   - **Ready Signal Pattern:** "ready" (optional)
   - **Port Detection Pattern:** ":(\\d+)" (optional)
3. Click "Save"

**Expected Result:**
- Configuration appears in the list
- Success message is displayed
- Configuration is persisted (survives app restart)

### 2. Edit a Configuration

**Test Case:** Modify an existing configuration

**Steps:**
1. Right-click on a configuration in the list
2. Select "Edit" from the context menu
3. Change the name to "Updated Test Server"
4. Change the command to "python3"
5. Click "Save"

**Expected Result:**
- Configuration is updated in the list
- Changes are persisted
- Updated timestamp is newer

### 3. Delete a Configuration

**Test Case:** Delete a configuration with confirmation

**Steps:**
1. Right-click on a configuration
2. Select "Delete" from the context menu
3. Confirm deletion in the alert dialog

**Expected Result:**
- Confirmation dialog appears with configuration name
- After confirming, configuration is removed from list
- Success message is displayed

### 4. Search/Filter Configurations

**Test Case:** Filter configurations by name or command

**Steps:**
1. Create multiple configurations with different names
2. Type in the search field at the top
3. Try searching by:
   - Configuration name
   - Command name

**Expected Result:**
- List filters in real-time as you type
- Only matching configurations are shown
- Search is case-insensitive

### 5. Generate App Bundle

**Test Case:** Generate a standalone .app bundle

**Steps:**
1. Right-click on a configuration
2. Select "Generate App Bundle"
3. Choose a save location (e.g., Desktop)
4. Wait for generation to complete

**Expected Result:**
- File picker appears with pre-filled name
- Progress indicator shows during generation
- Success alert displays with bundle path
- Finder opens showing the generated .app bundle
- Bundle has proper icon and Info.plist

**Note:** The generated bundle currently contains a placeholder executable. Full Server App Bundle implementation is in tasks 13-29.

### 6. Validation Testing

**Test Case:** Test inline validation in the editor

**Steps:**
1. Create a new configuration
2. Try to save without entering a name
3. Try to save without entering a command
4. Enter an invalid regex pattern in "Ready Signal Pattern"
5. Try to create a configuration with a duplicate name

**Expected Result:**
- Save button is disabled when required fields are empty
- Red error messages appear below invalid fields
- Duplicate name error is shown
- Invalid regex pattern error is shown

### 7. Persistence Testing

**Test Case:** Verify configurations persist between sessions

**Steps:**
1. Create 2-3 configurations
2. Quit the application (Cmd + Q)
3. Relaunch the application

**Expected Result:**
- All configurations are still present
- Configuration data is intact (names, commands, etc.)

### 8. Icon Handling

**Test Case:** Test custom icon selection

**Steps:**
1. Create a new configuration
2. Click "Choose..." button in the Appearance section
3. Select an image file (PNG, JPG, or ICNS)
4. Save the configuration
5. Generate an app bundle

**Expected Result:**
- Selected icon path is displayed
- Generated bundle uses the custom icon
- If no icon is selected, default icon is used

### 9. Error Handling

**Test Case:** Test error scenarios

**Steps:**
1. Try to generate a bundle to a read-only location
2. Try to generate a bundle with an invalid configuration
3. Try to delete a configuration that doesn't exist (edge case)

**Expected Result:**
- Appropriate error messages are displayed
- Application doesn't crash
- User can recover from errors

### 10. UI Responsiveness

**Test Case:** Test UI interactions

**Steps:**
1. Test context menu (right-click on configuration)
2. Test swipe actions (swipe left/right on configuration)
3. Test toolbar buttons
4. Test keyboard navigation (Tab, Enter, Escape)

**Expected Result:**
- All interactions work smoothly
- Context menu shows Edit, Generate, Delete options
- Swipe actions work on trackpad
- Keyboard shortcuts work as expected

## Known Limitations

1. **Generated bundles contain placeholder executables** - The Server App Bundle implementation (tasks 13-29) is not yet complete, so generated bundles won't actually run servers yet.

2. **Code signing uses ad-hoc signing** - Bundles are signed with ad-hoc signatures (no developer certificate). This is fine for testing but not for distribution.

3. **No undo/redo** - Configuration changes are immediate and cannot be undone (except by manually editing).

## Configuration File Location

Configurations are stored at:
```
~/Library/Application Support/LocalServerWrapper/configurations.json
```

You can inspect this file to verify persistence is working correctly.

## Troubleshooting

### App won't launch from Xcode
- Make sure you selected "LocalServerWrapper" scheme (not "LocalServerWrapperTests")
- Make sure "My Mac" is selected as the destination
- Try cleaning the build folder: Product → Clean Build Folder (Cmd + Shift + K)

### Configurations not persisting
- Check file permissions in `~/Library/Application Support/LocalServerWrapper/`
- Check Console.app for any error messages from LocalServerWrapper

### Bundle generation fails
- Check that you have write permissions to the output directory
- Check that the entitlements file exists at `LocalServerWrapper/ServerAppBundle.entitlements`
- Check Console.app for codesign errors

### UI not updating
- Try clicking the Refresh button in the toolbar
- Check that the configuration was actually saved (check the JSON file)

## Next Steps

After testing the Configuration Manager, the next phase would be to implement the Server App Bundle (tasks 13-29), which includes:
- Terminal component for displaying server output
- Browser component for viewing localhost
- Process management for running server commands
- Readiness detection for automatic browser opening
- Window lifecycle management

The Configuration Manager is fully functional and ready to generate bundles once the Server App Bundle executable is implemented.
