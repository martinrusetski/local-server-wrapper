# Implementation Plan: Local Server Wrapper

## Overview

This implementation plan breaks down the Local Server Wrapper system into discrete coding tasks. The system consists of two main components: a Configuration Manager application for creating and managing server configurations, and a Generator that produces standalone .app bundles. The implementation follows a phased approach, building core functionality first, then adding the bundle generation capability, and finally implementing the runtime behavior of generated app bundles.

## Tasks

- [x] 1. Set up project structure and core data models
  - Create Xcode project with SwiftUI macOS app template (minimum macOS 13.0)
  - Define `ServerConfiguration` struct with all required fields (id, name, command, arguments, localhostURL, readySignalPattern, portDetectionPattern, customIconPath, createdAt, updatedAt)
  - Implement `Codable` conformance for JSON serialization
  - Create error types: `ValidationError`, `GenerationError`, `PersistenceError`
  - Set up project directory structure (Models/, Views/, Services/, Utilities/)
  - _Requirements: 1.1, 1.2, 1.3, 2.1, 2.2, 2.3, 2.4, 2.5_

- [ ]* 1.1 Write property test for configuration persistence round-trip
  - **Property 1: Configuration Persistence Round-Trip**
  - **Validates: Requirements 1.5, 11.1, 11.6**
  - Install SwiftCheck or swift-check framework
  - Create arbitrary generator for `ServerConfiguration`
  - Test that save then load preserves all configuration data
  - Test with empty arrays, single configs, and multiple configs

- [ ] 2. Implement configuration validation
  - [x] 2.1 Create `ConfigurationValidator` class with validation methods
    - Implement `validate(_ config: ServerConfiguration) throws`
    - Implement `validateRegexPattern(_ pattern: String) throws`
    - Implement `validateCommand(_ command: String) throws`
    - Implement `validateURL(_ url: String) throws`
    - Check for missing required fields (name, command)
    - _Requirements: 2.6_
  
  - [ ]* 2.2 Write property test for unique name validation
    - **Property 2: Unique Name Validation**
    - **Validates: Requirements 1.6**
    - Test that validator correctly identifies duplicate names
    - Test case sensitivity, whitespace, and special characters
  
  - [ ]* 2.3 Write property test for required field validation
    - **Property 3: Required Field Validation**
    - **Validates: Requirements 2.6**
    - Test with various combinations of missing required fields
    - Verify all missing fields are identified

- [ ] 3. Implement persistence layer
  - [x] 3.1 Create `PersistenceManager` class
    - Implement `save(_ configurations: [ServerConfiguration]) throws`
    - Implement `load() throws -> [ServerConfiguration]`
    - Implement `backup() throws`
    - Implement `restore(from backupURL: URL) throws`
    - Use atomic writes to prevent corruption
    - Store at `~/Library/Application Support/LocalServerWrapper/configurations.json`
    - _Requirements: 1.5, 11.1, 11.6_
  
  - [ ]* 3.2 Write unit tests for persistence manager
    - Test save and load operations
    - Test backup and restore functionality
    - Test error handling for file system errors
    - Test atomic write behavior

- [ ] 4. Implement Configuration Manager core logic
  - [x] 4.1 Create `ConfigurationManager` class implementing `ConfigurationManagerProtocol`
    - Implement `createConfiguration(_ config: ServerConfiguration) throws`
    - Implement `updateConfiguration(_ config: ServerConfiguration) throws`
    - Implement `deleteConfiguration(id: UUID) throws`
    - Implement `listConfigurations() -> [ServerConfiguration]`
    - Implement `getConfiguration(id: UUID) -> ServerConfiguration?`
    - Integrate with `ConfigurationValidator` and `PersistenceManager`
    - _Requirements: 1.1, 1.2, 1.3, 1.4, 11.2_
  
  - [ ]* 4.2 Write property test for configuration update persistence
    - **Property 10: Configuration Update Persistence**
    - **Validates: Requirements 11.2**
    - Test that modifications are preserved after save and load
    - Test multiple updates and all fields changed

- [ ] 5. Build Configuration Manager UI
  - [x] 5.1 Create main window with configuration list view
    - Build SwiftUI list displaying all configurations
    - Add toolbar with "New Configuration" button
    - Implement row actions (edit, delete, generate)
    - Add search/filter functionality
    - _Requirements: 1.4_
  
  - [x] 5.2 Create configuration editor form view
    - Build form with fields for all configuration properties
    - Add text fields for name, command, URL, patterns
    - Add file picker for custom icon
    - Implement inline validation with error messages
    - Add save and cancel buttons
    - _Requirements: 1.1, 1.2, 2.1, 2.2, 2.3, 2.4, 2.5_
  
  - [x] 5.3 Implement delete confirmation dialog
    - Show alert when user attempts to delete configuration
    - Display configuration name in confirmation message
    - _Requirements: 1.3_
  
  - [ ]* 5.4 Write UI tests for configuration management flows
    - Test creating new configuration
    - Test editing existing configuration
    - Test deleting configuration with confirmation
    - Test validation error display

- [x] 6. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [ ] 7. Implement App Bundle Generator core
  - [x] 7.1 Create `AppBundleGenerator` class implementing `AppBundleGeneratorProtocol`
    - Implement `generate(configuration:outputPath:progressHandler:) async throws -> URL`
    - Create bundle directory structure (Contents/, MacOS/, Resources/)
    - Copy executable template to MacOS/
    - Embed configuration JSON in Resources/
    - _Requirements: 3.1, 3.2, 3.4_
  
  - [ ]* 7.2 Write property test for bundle structure validity
    - **Property 4: Bundle Structure Validity**
    - **Validates: Requirements 3.1**
    - Test that generated bundles have required directories and files
    - Test with special characters and long names
  
  - [ ]* 7.3 Write property test for configuration embedding round-trip
    - **Property 5: Configuration Embedding Round-Trip**
    - **Validates: Requirements 3.2**
    - Test that embedded config can be extracted with all settings preserved
    - Test with special characters and large configs

- [ ] 8. Implement Info.plist generation
  - [x] 8.1 Create `InfoPlistGenerator` utility
    - Generate Info.plist with proper bundle identifier
    - Set CFBundleName from configuration name
    - Set CFBundleExecutable to "ServerAppBundle"
    - Set CFBundleIconFile if custom icon provided
    - Set minimum system version to 13.0
    - _Requirements: 3.1_
  
  - [ ]* 8.2 Write unit tests for Info.plist generation
    - Test with various configuration names
    - Test with and without custom icons
    - Verify all required keys are present

- [ ] 9. Implement bundle signing and entitlements
  - [x] 9.1 Create entitlements file
    - Add com.apple.security.app-sandbox
    - Add com.apple.security.network.client
    - Add com.apple.security.network.server
    - Add com.apple.security.files.user-selected.read-write
    - _Requirements: 12.1, 12.3_
  
  - [x] 9.2 Implement code signing in generator
    - Sign bundle with entitlements using codesign
    - Handle signing errors gracefully
    - Verify signature after signing
    - _Requirements: 3.1_
  
  - [ ]* 9.3 Write integration tests for bundle signing
    - Test that generated bundles are properly signed
    - Verify entitlements are embedded correctly
    - Test signature verification

- [ ] 10. Implement icon handling
  - [x] 10.1 Create icon processing utility
    - Convert custom icon to .icns format if needed
    - Copy icon to Resources/ directory
    - Use default icon if no custom icon provided
    - _Requirements: 2.5, 10.5_
  
  - [ ]* 10.2 Write unit tests for icon handling
    - Test with various image formats
    - Test with missing icon file
    - Test default icon fallback

- [ ] 11. Integrate generator with Configuration Manager UI
  - [x] 11.1 Add "Generate App Bundle" action to UI
    - Add button to configuration list rows
    - Show file picker for output location
    - Display progress indicator during generation
    - Show success notification with output path
    - Display error alert on failure
    - _Requirements: 3.4, 3.5, 3.6, 11.3_
  
  - [ ]* 11.2 Write property test for current settings usage in regeneration
    - **Property 11: Current Settings Usage in Regeneration**
    - **Validates: Requirements 11.4**
    - Test that regenerated bundles use current configuration state
    - Test with multiple regenerations and rapid changes

- [x] 12. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 13. Create Server App Bundle executable project
  - [x] 13.1 Create separate Xcode project for ServerAppBundle
    - Create SwiftUI macOS app template
    - Set up as standalone executable
    - Configure for embedding in generated bundles
    - _Requirements: 3.3, 10.1_
  
  - [x] 13.2 Create configuration loader
    - Implement `ConfigurationLoader.loadEmbeddedConfiguration()`
    - Read configuration.json from Resources/
    - Parse JSON into ServerConfiguration
    - Handle missing or invalid configuration gracefully
    - _Requirements: 3.2, 3.3_
  
  - [ ]* 13.3 Write unit tests for configuration loader
    - Test loading valid configuration
    - Test handling of missing configuration file
    - Test handling of malformed JSON

- [x] 14. Implement Process Manager
  - [x] 14.1 Create `ProcessManager` class conforming to `ProcessManagerProtocol`
    - Implement `start(command:arguments:) throws`
    - Implement `terminate()`
    - Implement `forceKill()`
    - Set up `Process` with pipes for stdout/stderr
    - Capture output incrementally using `Pipe`
    - Observe process termination with `NotificationCenter`
    - Publish `isRunning`, `exitCode`, and `output` properties
    - _Requirements: 4.1, 4.2, 4.4_
  
  - [ ]* 14.2 Write unit tests for Process Manager
    - Test starting and stopping processes
    - Test output capture
    - Test exit code handling
    - Test process termination notification

- [x] 15. Implement Readiness Detector
  - [x] 15.1 Create `ReadinessDetector` class conforming to `ReadinessDetectorProtocol`
    - Implement `monitor(output: String)`
    - Implement `reset()`
    - Use `NSRegularExpression` for pattern matching
    - Detect ready signal pattern in output
    - Extract port number using port detection pattern
    - Construct final URL from base URL and detected port
    - Publish `isReady` and `detectedURL` properties
    - _Requirements: 5.1, 5.2, 5.3, 5.4, 9.1, 9.2, 9.3_
  
  - [ ]* 15.2 Write property test for ready signal pattern matching
    - **Property 6: Ready Signal Pattern Matching**
    - **Validates: Requirements 5.1**
    - Test with various output strings and regex patterns
    - Test empty strings, multiline, and special regex characters
  
  - [ ]* 15.3 Write property test for port extraction
    - **Property 7: Port Extraction from Output**
    - **Validates: Requirements 9.1**
    - Test extracting ports from terminal output
    - Test with multiple ports, invalid ports, and edge port numbers
  
  - [ ]* 15.4 Write property test for URL construction
    - **Property 8: URL Construction from Port**
    - **Validates: Requirements 9.2**
    - Test constructing URLs from base URL and port numbers (1-65535)
    - Test with various protocols and edge cases

- [x] 16. Implement Terminal Component
  - [x] 16.1 Create `TerminalView` SwiftUI view
    - Display process output in scrollable text view
    - Use monospaced font
    - Enable text selection
    - Auto-scroll to bottom on new output
    - Use dark background with light text
    - Display exit code when process terminates
    - _Requirements: 4.2, 4.3, 4.4_
  
  - [ ]* 16.2 Write UI tests for Terminal Component
    - Test output display
    - Test auto-scrolling
    - Test text selection
    - Test exit code display

- [x] 17. Implement Browser Component
  - [x] 17.1 Create `WebViewModel` class
    - Implement `load(url: URL)`
    - Implement `goBack()`, `goForward()`, `reload()`
    - Publish `url`, `canGoBack`, `canGoForward`, `isLoading`, `currentURL`
    - _Requirements: 6.2, 6.4_
  
  - [x] 17.2 Create `WebView` NSViewRepresentable wrapper
    - Wrap `WKWebView` for SwiftUI
    - Implement `WKNavigationDelegate` in Coordinator
    - Handle navigation events
    - Update view model on navigation changes
    - _Requirements: 6.1, 6.3_
  
  - [x] 17.3 Create `BrowserView` SwiftUI view
    - Build browser toolbar with back, forward, reload buttons
    - Display current URL
    - Embed WebView
    - Show loading indicator
    - _Requirements: 6.2, 6.4_
  
  - [ ]* 17.4 Write unit tests for WebViewModel
    - Test navigation methods
    - Test state updates
    - Test URL loading

- [x] 18. Implement error handling in Browser Component
  - [x] 18.1 Add error handling to WebView
    - Handle connection refused errors
    - Handle network errors
    - Display error messages in web view
    - Provide retry button
    - _Requirements: 8.4_
  
  - [ ]* 18.2 Write integration tests for browser error handling
    - Test connection refused scenario
    - Test invalid URL handling
    - Test retry functionality

- [x] 19. Implement AppState and component integration
  - [x] 19.1 Create `AppState` class
    - Initialize with embedded configuration
    - Create `ProcessManager` instance
    - Create `ReadinessDetector` instance
    - Connect process output to readiness detector using Combine
    - Manage `showCloseConfirmation` state
    - _Requirements: 4.1, 5.1, 6.1_
  
  - [x] 19.2 Implement readiness-triggered browser loading
    - Observe `readinessDetector.isReady` changes
    - Load `detectedURL` in browser when ready
    - Handle immediate browser open when no ready signal configured
    - _Requirements: 5.2, 5.4, 6.1_
  
  - [ ]* 19.3 Write integration tests for component coordination
    - Test process start triggers readiness detection
    - Test ready signal triggers browser load
    - Test immediate browser open without ready signal

- [x] 20. Implement split view layout
  - [x] 20.1 Create `ContentView` with HSplitView
    - Add TerminalView on left side
    - Add BrowserView on right side
    - Set minimum widths (terminal: 200, browser: 400)
    - Make split position adjustable
    - Start process on view appear
    - _Requirements: 7.3, 7.4_
  
  - [ ]* 20.2 Write UI tests for split view layout
    - Test split view rendering
    - Test resizing split
    - Test minimum width constraints

- [x] 21. Implement window lifecycle management
  - [x] 21.1 Add close confirmation dialog
    - Detect when user attempts to close window
    - Check if process is still running
    - Show confirmation alert if process running
    - Allow close if process terminated
    - _Requirements: 7.5_
  
  - [x] 21.2 Implement process termination on close
    - Terminate server process when window closes
    - Keep terminal visible after process exits
    - Clean up resources
    - _Requirements: 7.1, 7.2_
  
  - [ ]* 21.3 Write integration tests for window lifecycle
    - Test close confirmation when process running
    - Test process termination on close
    - Test terminal remains visible after exit

- [x] 22. Implement error handling in Server App Bundle
  - [x] 22.1 Add process error handling
    - Display command not found errors
    - Display permission denied errors
    - Highlight non-zero exit codes in terminal
    - Provide restart option
    - _Requirements: 8.1, 8.2_
  
  - [x] 22.2 Add ready signal timeout handling
    - Implement configurable timeout (default: 30 seconds)
    - Show notification when timeout occurs
    - Offer manual browser open option
    - _Requirements: 8.3_
  
  - [ ]* 22.3 Write integration tests for error scenarios
    - Test command not found error
    - Test non-zero exit code handling
    - Test ready signal timeout
    - Test manual browser open after timeout

- [x] 23. Implement bundle relocatability
  - [x] 23.1 Ensure no hardcoded paths in bundle
    - Use `Bundle.main` for resource access
    - Use relative paths for all resources
    - Test bundle works after moving to different location
    - _Requirements: 10.3_
  
  - [ ]* 23.2 Write property test for bundle relocatability
    - **Property 9: Bundle Relocatability**
    - **Validates: Requirements 10.3**
    - Test moving bundle to various filesystem paths
    - Verify bundle launches and executes correctly after relocation

- [x] 24. Implement sandboxing and container isolation
  - [x] 24.1 Configure sandbox entitlements for Server App Bundle
    - Add same entitlements as Configuration Manager
    - Verify container creation on launch
    - Test file access restrictions
    - _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5_
  
  - [ ]* 24.2 Write integration tests for sandboxing
    - Test container creation
    - Test file access restrictions
    - Test multiple bundles have separate containers
    - _Requirements: 12.6_

- [x] 25. Checkpoint - Ensure all tests pass
  - Ensure all tests pass, ask the user if questions arise.

- [x] 26. Implement accessibility features
  - [x] 26.1 Add accessibility labels to all UI elements
    - Add labels to buttons, text fields, and lists
    - Implement proper focus management
    - Add state change announcements
    - _Requirements: Not explicitly required, but good practice_
  
  - [x] 26.2 Implement keyboard navigation
    - Add keyboard shortcuts for common actions
    - Ensure logical tab order
    - Support escape key to cancel operations
    - _Requirements: Not explicitly required, but good practice_
  
  - [ ]* 26.3 Write accessibility tests
    - Test VoiceOver support
    - Test keyboard navigation
    - Test with high contrast mode

- [x] 27. Implement logging and debugging
  - [x] 27.1 Add logging throughout the application
    - Use `os_log` for system logging
    - Log errors with context (config ID, operation, timestamp)
    - Use appropriate log levels (error, warning, info, debug)
    - Respect user privacy (no sensitive data)
    - _Requirements: Error handling strategy_
  
  - [ ]* 27.2 Write tests for logging behavior
    - Verify errors are logged
    - Verify log levels are correct
    - Verify no sensitive data in logs

- [x] 28. Polish and final integration
  - [x] 28.1 Add progress reporting to bundle generation
    - Show progress bar during generation
    - Report current step (creating structure, copying resources, signing)
    - Support cancellation
    - _Requirements: 3.5_
  
  - [x] 28.2 Implement graceful degradation
    - Use default icon if custom icon fails to load
    - Use static URL if port detection fails
    - Allow manual browser open if ready signal times out
    - Continue without history if tracking fails
    - _Requirements: Error handling strategy_
  
  - [x] 28.3 Add user notifications
    - Use native macOS alerts for critical errors
    - Use inline validation for form errors
    - Use status bar for informational messages
    - _Requirements: Error handling strategy_
  
  - [ ]* 28.4 Write end-to-end integration tests
    - Test complete workflow: create config → generate bundle → launch bundle → verify behavior
    - Test with various server types (npm, python, ruby)
    - Test error scenarios end-to-end

- [x] 29. Final checkpoint - Ensure all tests pass
  - Run all unit tests, property tests, and integration tests
  - Verify code coverage meets target (>80%)
  - Run static analysis (SwiftLint)
  - Perform manual smoke testing
  - Ensure all tests pass, ask the user if questions arise.

## Notes

- Tasks marked with `*` are optional and can be skipped for faster MVP
- Each task references specific requirements for traceability
- Property tests validate universal correctness properties from the design
- Unit tests validate specific examples and edge cases
- Integration tests verify component interactions
- Checkpoints ensure incremental validation throughout implementation
- The implementation follows a phased approach: Configuration Manager → Generator → Server App Bundle → Integration
