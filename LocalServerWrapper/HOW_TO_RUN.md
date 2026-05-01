# How to Run the Configuration Manager App

## Build Status
✅ **Build Successful!** All import errors have been fixed.

## Running the App

### Option 1: Run from Xcode (Recommended)
1. Open the project in Xcode:
   ```bash
   open LocalServerWrapperApp/LocalServerWrapper/LocalServerWrapper.xcodeproj
   ```

2. Click the "Run" button (▶️) in Xcode, or press `Cmd+R`

3. The Configuration Manager window should appear

### Option 2: Run from Terminal
```bash
open LocalServerWrapperApp/LocalServerWrapper/DerivedData/LocalServerWrapper-*/Build/Products/Debug/LocalServerWrapper.app
```

Or build and run:
```bash
cd LocalServerWrapperApp/LocalServerWrapper
xcodebuild -project LocalServerWrapper.xcodeproj -scheme LocalServerWrapper -configuration Debug
open ~/Library/Developer/Xcode/DerivedData/LocalServerWrapper-*/Build/Products/Debug/LocalServerWrapper.app
```

## Testing the Configuration Manager

### 1. Create a Configuration
- Click the "+" button in the toolbar
- Fill in the configuration details:
  - **Name**: e.g., "My Local Server"
  - **Command**: e.g., "python3"
  - **Arguments**: e.g., "-m http.server"
  - **Port**: e.g., 8000
  - **Working Directory**: Select a directory
  - **Icon** (optional): Choose an image file
- Click "Save"

### 2. View Configurations
- Your saved configuration should appear in the list
- You can see the command, arguments, and localhost URL

### 3. Edit a Configuration
- Right-click on a configuration and select "Edit"
- Or swipe left and tap the orange "Edit" button
- Make your changes and click "Save"

### 4. Delete a Configuration
- Right-click on a configuration and select "Delete"
- Or swipe right and tap the red "Delete" button
- Confirm the deletion

### 5. Generate App Bundle (Not Yet Implemented)
- Right-click on a configuration and select "Generate App Bundle"
- Choose where to save the .app bundle
- The app will create a standalone macOS app for your server

## What's Working

✅ Configuration CRUD operations (Create, Read, Update, Delete)
✅ Configuration validation
✅ Persistence (saves to ~/Library/Application Support/LocalServerWrapper/)
✅ Search functionality
✅ SwiftUI interface with list and editor views
✅ Icon selection and processing
✅ All 76 unit tests passing

## What's Not Yet Implemented

⏳ Server App Bundle generation (Tasks 13-29)
⏳ Actual server launching and management
⏳ Server status monitoring

## Configuration Storage

Configurations are saved to:
```
~/Library/Application Support/LocalServerWrapper/configurations.json
```

Backups are created at:
```
~/Library/Application Support/LocalServerWrapper/configurations.json.backup
```

## Troubleshooting

### App doesn't launch
- Make sure you built the project successfully
- Check that you're opening the correct .app file
- Try cleaning the build: `xcodebuild clean` then rebuild

### Window doesn't appear
- The app should automatically bring the window to front
- Check if the window is hidden behind other windows
- Try clicking the app icon in the Dock

### Can't save configurations
- Check file permissions for ~/Library/Application Support/
- Look for error messages in the app's alert dialogs

## Next Steps

To continue with the remaining tasks (Server App Bundle generation):
1. Open `.kiro/specs/local-server-wrapper/tasks.md`
2. Tasks 13-29 cover the Server App Bundle executable implementation
3. Run: "execute task 13" to start implementing the server launcher
