# ServerAppBundle Sandbox Configuration

## Overview

The ServerAppBundle is configured as a sandboxed macOS application to meet the requirements specified in Requirement 12 of the Local Server Wrapper specification.

## Sandbox Configuration

### Build Settings

The following build settings have been configured in the Xcode project (`ServerAppBundle.xcodeproj/project.pbxproj`):

- **ENABLE_APP_SANDBOX**: `YES` - Enables App Sandbox for the application
- **ENABLE_HARDENED_RUNTIME**: `YES` - Enables Hardened Runtime for additional security
- **CODE_SIGN_ENTITLEMENTS**: `ServerAppBundle/ServerAppBundle.entitlements` - Points to the entitlements file

These settings are configured for both Debug and Release build configurations.

### Entitlements

The entitlements file (`ServerAppBundle/ServerAppBundle.entitlements`) contains the following permissions:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>com.apple.security.app-sandbox</key>
	<true/>
	<key>com.apple.security.network.client</key>
	<true/>
	<key>com.apple.security.network.server</key>
	<true/>
	<key>com.apple.security.files.user-selected.read-write</key>
	<true/>
</dict>
</plist>
```

#### Entitlement Descriptions

1. **com.apple.security.app-sandbox** (`true`)
   - Enables App Sandbox for the application
   - Creates an isolated container in `~/Library/Containers/com.localserverwrapper.serverappbundle`
   - Restricts file system access to the container and user-selected files

2. **com.apple.security.network.client** (`true`)
   - Allows the app to make outgoing network connections
   - Required for the Browser Component to load localhost URLs

3. **com.apple.security.network.server** (`true`)
   - Allows the app to accept incoming network connections
   - Required for the Terminal Component to run local development servers

4. **com.apple.security.files.user-selected.read-write** (`true`)
   - Allows read/write access to files explicitly selected by the user
   - Enables users to select project directories for server execution

## Requirements Satisfied

This configuration satisfies the following acceptance criteria from Requirement 12:

- ✅ **12.1**: Create each Server_App_Bundle as a sandboxed macOS application
  - Achieved through `ENABLE_APP_SANDBOX = YES` and `com.apple.security.app-sandbox` entitlement

- ✅ **12.2**: Create an isolated container in the macOS Containers directory when launched
  - Automatically created by macOS when a sandboxed app launches
  - Location: `~/Library/Containers/com.localserverwrapper.serverappbundle`

- ✅ **12.3**: Include proper entitlements for sandboxed execution
  - All required entitlements are configured in the entitlements file

- ✅ **12.4**: Store application data within its designated container
  - Sandboxed apps automatically store data in their container
  - Access via `FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)`

- ✅ **12.5**: NOT access files or resources outside its sandbox without explicit user permission
  - Enforced by App Sandbox
  - User-selected files can be accessed via `com.apple.security.files.user-selected.read-write`

- ✅ **12.6**: When multiple Server_App_Bundles are running, the macOS system SHALL maintain separate containers for each bundle
  - Each app bundle has a unique bundle identifier, ensuring separate containers
  - Current bundle ID: `com.localserverwrapper.serverappbundle`

## Testing

### Automated Testing

Two test scripts are provided to verify the sandbox configuration:

#### 1. Entitlements Verification Test

```bash
./test_sandbox_entitlements.sh
```

This script verifies:
- Build succeeds with sandbox enabled
- Entitlements file exists and contains all required entitlements
- Build settings (`ENABLE_APP_SANDBOX`, `ENABLE_HARDENED_RUNTIME`, `CODE_SIGN_ENTITLEMENTS`) are correctly configured
- Info.plist is generated with correct bundle identifier

#### 2. Container Creation Test

```bash
./test_container_creation.sh
```

This script verifies:
- App launches successfully
- Container is created in `~/Library/Containers/`
- Container has correct directory structure
- App can write to container (file access within sandbox)

### Manual Testing

1. Build and run the ServerAppBundle:
   ```bash
   xcodebuild -project ServerAppBundle/ServerAppBundle.xcodeproj \
       -scheme ServerAppBundle \
       -configuration Debug \
       build
   ```

2. Launch the built app:
   ```bash
   open ~/Library/Developer/Xcode/DerivedData/ServerAppBundle-*/Build/Products/Debug/ServerAppBundle.app
   ```

3. Verify container creation:
   ```bash
   ls -la ~/Library/Containers/ | grep serverappbundle
   ```

4. Check container contents:
   ```bash
   ls -la ~/Library/Containers/com.localserverwrapper.serverappbundle/
   ```

### Verification Documentation

The entitlements are verified by building the project and checking the embedded provisioning profile with `codesign -d --entitlements - ServerAppBundle.app`.

## Comparison with Configuration Manager

The ServerAppBundle sandbox configuration matches the Configuration Manager (LocalServerWrapper) configuration:

| Setting | Configuration Manager | ServerAppBundle |
|---------|----------------------|-----------------|
| App Sandbox | ✅ Enabled | ✅ Enabled |
| Hardened Runtime | ✅ Enabled | ✅ Enabled |
| Network Client | ✅ Enabled | ✅ Enabled |
| Network Server | ✅ Enabled | ✅ Enabled |
| User Selected Files | ✅ Read/Write | ✅ Read/Write |

## Notes

- The sandbox is enforced by macOS and cannot be bypassed by the application
- Container creation happens automatically on first launch
- Each generated Server_App_Bundle will have its own unique bundle identifier and container
- The Configuration Manager uses build settings directly, while ServerAppBundle uses an entitlements file (both approaches are valid)
