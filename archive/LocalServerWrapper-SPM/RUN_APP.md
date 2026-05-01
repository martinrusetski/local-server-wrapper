# How to Run the Configuration Manager

## The Problem

Swift Package Manager doesn't fully support SwiftUI macOS apps. The app compiles but won't show windows when run with `swift run`.

## Solution: Create an Xcode Project

You need to create a proper Xcode macOS app project. Here's how:

### Option 1: Create New Xcode Project and Copy Files

1. **Open Xcode**
2. **File → New → Project**
3. Select **macOS → App**
4. Fill in:
   - Product Name: `LocalServerWrapper`
   - Interface: **SwiftUI**
   - Language: **Swift**
   - Minimum Deployment: **macOS 13.0**
5. Save it in a new directory (e.g., `LocalServerWrapperXcode`)

6. **Copy all source files** from the SPM project:
   ```bash
   # From the LocalServerWrapper directory
   cp -r LocalServerWrapper/Models LocalServerWrapperXcode/LocalServerWrapper/
   cp -r LocalServerWrapper/Views LocalServerWrapperXcode/LocalServerWrapper/
   cp -r LocalServerWrapper/ViewModels LocalServerWrapperXcode/LocalServerWrapper/
   cp -r LocalServerWrapper/Services LocalServerWrapperXcode/LocalServerWrapper/
   cp -r LocalServerWrapper/Utilities LocalServerWrapperXcode/LocalServerWrapper/
   cp LocalServerWrapper/LocalServerWrapperApp.swift LocalServerWrapperXcode/LocalServerWrapper/
   cp ../ServerAppBundle.entitlements LocalServerWrapperXcode/LocalServerWrapper/
   ```

7. **Add files to Xcode project:**
   - In Xcode, right-click on the project folder
   - Select "Add Files to LocalServerWrapper"
   - Select all the copied folders
   - Make sure "Copy items if needed" is checked
   - Click "Add"

8. **Configure entitlements:**
   - Select the project in the navigator
   - Select the target
   - Go to "Signing & Capabilities"
   - Click "+ Capability" and add "App Sandbox"
   - Enable:
     - Outgoing Connections (Client)
     - Incoming Connections (Server)
     - User Selected File (Read/Write)

9. **Run the app:**
   - Press `Cmd + R`
   - The Configuration Manager window should appear

### Option 2: Use Xcode to Open Package.swift (Simpler)

Actually, let me try a different approach. The issue might be that the app is running but the window isn't activating.

Try this:

1. **Open Package.swift in Xcode:**
   ```bash
   cd LocalServerWrapper
   open Package.swift
   ```

2. **Wait for Xcode to index the project**

3. **In Xcode:**
   - Select "LocalServerWrapper" scheme (top left, next to the play button)
   - Make sure "My Mac" is selected as the destination
   - Press `Cmd + R` to run

4. **If the window doesn't appear:**
   - Check if the app is running in the Dock
   - Try clicking on the app icon in the Dock
   - Or press `Cmd + Tab` to switch to it

5. **If still no window:**
   - Stop the app (Cmd + .)
   - In Xcode, go to Product → Scheme → Edit Scheme
   - Under "Run" → "Options"
   - Make sure "Application" is selected (not "Automatic")
   - Try running again

### Option 3: Quick Fix - Add Window Activation

The issue might be that the window isn't being brought to front. Let me create a fix.
