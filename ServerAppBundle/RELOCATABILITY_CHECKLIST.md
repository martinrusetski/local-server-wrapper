# Bundle Relocatability Checklist

This checklist ensures that the ServerAppBundle remains relocatable as new features are added.

## For Developers: Adding New Features

When adding new code to ServerAppBundle, verify the following:

### ✅ Resource Access
- [ ] Use `Bundle.main` for all resource access
- [ ] Never hardcode absolute paths (e.g., `/Users/...`, `/Applications/...`)
- [ ] Use bundle APIs: `Bundle.main.url(forResource:withExtension:)`
- [ ] Use bundle APIs: `Bundle.main.path(forResource:ofType:)`
- [ ] Use bundle APIs: `Bundle.main.resourceURL` or `Bundle.main.resourcePath`

### ✅ File System Operations
- [ ] No assumptions about bundle location
- [ ] No assumptions about parent directory structure
- [ ] No hardcoded paths to system directories
- [ ] No hardcoded paths to user directories
- [ ] Use `FileManager.default.urls(for:in:)` for standard directories if needed

### ✅ Configuration and Data
- [ ] Configuration loaded from bundle Resources
- [ ] No external configuration file dependencies
- [ ] User data stored in sandbox container (if needed)
- [ ] No assumptions about working directory

### ✅ Environment
- [ ] No dependencies on environment variables for paths
- [ ] No assumptions about `$HOME` or `$USER`
- [ ] No assumptions about current working directory
- [ ] Process commands come from configuration, not hardcoded

### ✅ Testing
- [ ] Test bundle works after moving to different location
- [ ] Test bundle works from Desktop
- [ ] Test bundle works from Applications folder
- [ ] Test bundle works from custom directory
- [ ] Test bundle works after renaming

## Code Review Checklist

Use this checklist when reviewing pull requests:

- [ ] No new hardcoded absolute paths introduced
- [ ] All new resource access uses `Bundle.main`
- [ ] No new assumptions about bundle location
- [ ] No new dependencies on external files
- [ ] Sandbox compatibility maintained
- [ ] Documentation updated if needed

## Common Patterns

### ✅ CORRECT: Loading Resources

```swift
// Load configuration from bundle
let bundle = Bundle.main
guard let configURL = bundle.url(forResource: "configuration", withExtension: "json") else {
    throw ConfigurationLoadError.configurationFileNotFound
}
let data = try Data(contentsOf: configURL)
```

### ❌ INCORRECT: Hardcoded Paths

```swift
// DON'T DO THIS - hardcoded path
let configPath = "/Applications/MyApp.app/Contents/Resources/configuration.json"
let data = try Data(contentsOf: URL(fileURLWithPath: configPath))
```

### ✅ CORRECT: Assets

```swift
// SwiftUI automatically resolves assets from bundle
Image("AppIcon")
Image(systemName: "gear")
```

### ❌ INCORRECT: External Asset Paths

```swift
// DON'T DO THIS - external path
Image(nsImage: NSImage(contentsOfFile: "/Users/me/Desktop/icon.png")!)
```

### ✅ CORRECT: Command Execution

```swift
// Command path comes from configuration
let command = configuration.command // e.g., "/usr/local/bin/npm"
let process = Process()
process.executableURL = URL(fileURLWithPath: command)
```

### ❌ INCORRECT: Hardcoded Commands

```swift
// DON'T DO THIS - hardcoded system path
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/local/bin/npm")
```

## Verification Commands

### Search for Hardcoded Paths

```bash
# Search for common hardcoded path patterns
grep -r "/Users/" ServerAppBundle/ServerAppBundle/*.swift
grep -r "/Applications/" ServerAppBundle/ServerAppBundle/*.swift
grep -r "/Library/" ServerAppBundle/ServerAppBundle/*.swift
grep -r "/tmp/" ServerAppBundle/ServerAppBundle/*.swift
grep -r "/var/" ServerAppBundle/ServerAppBundle/*.swift

# Should return no results
```

### Verify Bundle.main Usage

```bash
# Find all resource access
grep -r "Bundle.main" ServerAppBundle/ServerAppBundle/*.swift

# Should show proper usage in ConfigurationLoader
```

### Check for FileManager Usage

```bash
# Review FileManager usage
grep -r "FileManager" ServerAppBundle/ServerAppBundle/*.swift

# Verify no hardcoded paths in FileManager calls
```

## Manual Testing Procedure

1. **Build the bundle**
   ```bash
   xcodebuild -project ServerAppBundle.xcodeproj \
              -scheme ServerAppBundle \
              -configuration Release \
              build
   ```

2. **Locate the built bundle**
   ```bash
   open Build/Products/Release/
   ```

3. **Test from different locations**
   ```bash
   # Copy to Desktop
   cp -R Build/Products/Release/ServerAppBundle.app ~/Desktop/
   open ~/Desktop/ServerAppBundle.app
   
   # Copy to Documents
   cp -R Build/Products/Release/ServerAppBundle.app ~/Documents/
   open ~/Documents/ServerAppBundle.app
   
   # Copy to custom directory
   mkdir -p ~/TestLocation/Servers/
   cp -R Build/Products/Release/ServerAppBundle.app ~/TestLocation/Servers/
   open ~/TestLocation/Servers/ServerAppBundle.app
   ```

4. **Verify functionality**
   - Configuration loads correctly
   - Server process starts
   - Terminal displays output
   - Browser loads correctly
   - All UI elements function

## Troubleshooting

### Issue: "Configuration file not found"
**Cause**: Configuration not embedded in bundle
**Solution**: Ensure configuration.json is in Resources directory

### Issue: "Command not found"
**Cause**: Command path in configuration is incorrect
**Solution**: This is a configuration issue, not a relocatability issue

### Issue: Bundle won't launch after moving
**Cause**: Possible code signing issue or hardcoded path
**Solution**: 
1. Check code signature: `codesign -vv bundle.app`
2. Search for hardcoded paths in code
3. Verify Bundle.main usage

## References

- [Apple Bundle Programming Guide](https://developer.apple.com/library/archive/documentation/CoreFoundation/Conceptual/CFBundles/Introduction/Introduction.html)
- [App Sandbox Design Guide](https://developer.apple.com/library/archive/documentation/Security/Conceptual/AppSandboxDesignGuide/AboutAppSandbox/AboutAppSandbox.html)
- [RELOCATABILITY.md](RELOCATABILITY.md) - Full verification document

## Maintenance

This checklist should be reviewed:
- Before each release
- When adding new features
- When modifying resource access
- When changing file system operations
- During code reviews

**Last Updated**: 2024
**Last Verified**: Task 23 - Implement bundle relocatability
