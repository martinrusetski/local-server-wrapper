//
//  AppState.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import Foundation
import Combine
import os.log
import AppKit

/// Logger for app state operations
private let logger = OSLog(subsystem: "com.localserverwrapper.serverappbundle", category: "appstate")

/// Central state management for the Server App Bundle
@MainActor
class AppState: ObservableObject {
    /// The embedded server configuration
    let configuration: ServerConfiguration
    
    /// Process manager for controlling the server process
    let processManager: ProcessManager
    
    /// Readiness detector for monitoring server readiness
    let readinessDetector: ReadinessDetector
    
    /// Web view model for browser control
    let webViewModel: WebViewModel
    
    /// Whether the toolbar is hidden (showing minimal window chrome)
    /// Persisted to UserDefaults so preference survives app restarts
    @Published var isToolbarHidden: Bool
    
    /// Whether to show the close confirmation dialog
    @Published var showCloseConfirmation: Bool = false
    
    /// Error message to display to the user
    @Published var errorMessage: String?
    
    /// Whether to show the error alert
    @Published var showErrorAlert: Bool = false
    
    /// Whether to show the timeout alert
    @Published var showTimeoutAlert: Bool = false
    
    /// Whether the sidebar is visible
    @Published var isSidebarVisible: Bool = false
    
    /// Credential detector for watching login form submissions
    let credentialDetector: CredentialDetector
    
    /// Intercepts attempts by the server process to open the system browser,
    /// forwarding those URLs into this app's web view instead.
    let browserInterceptor: BrowserOpenInterceptor
    
    /// Saved credentials loaded from Keychain
    @Published var credentials: [Credential] = []
    
    /// Pending credential to offer saving
    @Published var pendingCredential: Credential?
    
    /// Whether to show the credential save prompt
    @Published var showCredentialSavePrompt: Bool = false

    /// Whether to show the saved-credentials management sheet
    @Published var showCredentialManager: Bool = false
    
    /// Combine cancellables for managing subscriptions
    private var cancellables = Set<AnyCancellable>()

    /// One-shot subscription used to start a fresh process only once the old one has actually
    /// terminated (TASK-4). Replaced on each restart so it can't pile up.
    private var restartCancellable: AnyCancellable?
    
    /// Timer for ready signal timeout detection
    private var timeoutTimer: Timer?
    
    /// Timeout duration in seconds (default: 30)
    private let timeoutDuration: TimeInterval = 30
    
    /// Initialize app state with a configuration
    /// - Parameter configuration: The server configuration to use
    init(configuration: ServerConfiguration) {
        os_log(.info, log: logger, "Initializing app state for configuration: %{public}@", configuration.name)
        
        self.configuration = configuration
        
        // Restore persisted preferences
        self.isToolbarHidden = UserDefaults.standard.bool(forKey: "isToolbarHidden")
        
        // Initialize ProcessManager
        self.processManager = ProcessManager()
        
        // Initialize ReadinessDetector with configuration settings
        self.readinessDetector = ReadinessDetector(
            readySignalPattern: configuration.readySignalPattern,
            portDetectionPattern: configuration.portDetectionPattern,
            baseURL: configuration.localhostURL ?? "http://localhost:3000"
        )
        
        // Initialize WebViewModel
        self.webViewModel = WebViewModel()
        
        // Initialize credential detector
        self.credentialDetector = CredentialDetector()
        
        // Initialize browser-open interceptor
        self.browserInterceptor = BrowserOpenInterceptor()
        
        // Connect detector to WebViewModel so WebView can configure it
        webViewModel.credentialDetector = credentialDetector
        
        // Load saved credentials from Keychain
        self.credentials = KeychainManager.load()

        // Migrate legacy credentials (saved before the origin field existed) by assigning this
        // bundle's own origin. Safe because a generated bundle only ever serves one origin, and it
        // restores autofill for credentials saved before TASK-8 without weakening the origin check.
        migrateLegacyCredentialOrigins()

        // Set up credential detector callbacks
        setupCredentialDetection()
        
        // Set up auto-fill on page load
        setupAutoFill()
        
        // Set up Combine subscriptions to connect components
        setupSubscriptions()
        
        // Set up interception of system-browser launches
        setupBrowserOpenInterceptor()
        
        os_log(.debug, log: logger, "App state initialized successfully")
    }
    
    /// Set up credential detection to watch for login form submissions
    private func setupCredentialDetection() {
        os_log(.info, log: logger, "Setting up credential detection")
        credentialDetector.onCredentialsSubmitted = { [weak self] credential in
            guard let self = self else { return }
            os_log(.info, log: logger, "Credential detected: %{public}@", credential.username)
            
            let isDuplicate = self.credentials.contains { $0.matchesFingerprint(of: credential) }
            if !isDuplicate {
                self.pendingCredential = credential
                self.showCredentialSavePrompt = true
            }
        }
    }
    
    /// Set up auto-fill dropdown to appear after page loads
    private func setupAutoFill() {
        webViewModel.onPageLoaded = { [weak self] webView in
            guard let self = self, !self.credentials.isEmpty else { return }
            // Inject immediately. The injected JS retries / observes the DOM until the credential
            // fields exist, so we no longer depend on a fixed delay for slow SPAs (TASK-12).
            CredentialAutoFill.injectCredentials(self.credentials, into: webView)
        }
    }
    
    /// Set up interception of attempts by the server process to open the system browser.
    /// Intercepted URLs are loaded in this app's web view and the window is brought to front.
    private func setupBrowserOpenInterceptor() {
        browserInterceptor.onOpenRequested = { [weak self] url in
            self?.handleForwardedOpen(url: url)
        }
        browserInterceptor.setUp()
    }

    /// Load a URL that the server process tried to open externally into our web view.
    private func handleForwardedOpen(url: URL) {
        os_log(.info, log: logger, "Loading forwarded browser-open URL: %{public}@", url.absoluteString)
        webViewModel.load(url: url)
        cancelTimeoutTimer()
        // Bring the wrapper window to the front so it behaves like opening a browser.
        NSApp.activate(ignoringOtherApps: true)
        webViewModel.webView?.window?.makeKeyAndOrderFront(nil)
    }

    /// Backfill `origin` on credentials that predate the origin field, using this bundle's
    /// configured localhost origin (scheme + host + port). Re-saves only if something changed.
    private func migrateLegacyCredentialOrigins() {
        guard let origin = Self.origin(fromURLString: configuration.localhostURL) else { return }
        var changed = false
        for index in credentials.indices where credentials[index].origin == nil {
            credentials[index].origin = origin
            changed = true
        }
        if changed {
            os_log(.info, log: logger, "Migrated %d legacy credential(s) to origin %{public}@", credentials.count, origin)
            KeychainManager.save(credentials)
        }
    }

    /// Build a `window.location.origin`-style string ("scheme://host[:port]") from a URL string.
    static func origin(fromURLString urlString: String?) -> String? {
        guard let urlString = urlString,
              let comps = URLComponents(string: urlString),
              let scheme = comps.scheme,
              let host = comps.host else { return nil }
        if let port = comps.port {
            return "\(scheme)://\(host):\(port)"
        }
        return "\(scheme)://\(host)"
    }

    /// Save a detected credential to Keychain
    func saveCredential(_ credential: Credential) {
        credentials.append(credential)
        if KeychainManager.save(credentials) {
            os_log(.info, log: logger, "Credential saved for user: %{public}@", credential.username)
        } else {
            // Secure storage was unavailable — don't keep it in memory pretending it was saved (TASK-7).
            credentials.removeLast()
            os_log(.error, log: logger, "Could not store credential securely")
            errorMessage = "Couldn't store your credentials securely, so they were not saved."
            showErrorAlert = true
        }
    }
    
    /// Delete a credential by ID
    func deleteCredential(id: UUID) {
        credentials.removeAll { $0.id == id }
        KeychainManager.save(credentials)
    }
    
    /// Set up Combine subscriptions to connect process output to readiness detector
    /// and trigger browser loading when ready
    private func setupSubscriptions() {
        // Connect process output to readiness detector.
        // Feed only newly-appended chunks (not the whole buffer) so detection stays incremental
        // and the readiness scan can't degrade to O(n²) on chatty servers (TASK-3).
        processManager.outputChunks
            .sink { [weak self] chunk in
                self?.readinessDetector.monitor(output: chunk)
            }
            .store(in: &cancellables)
        
        // Observe readiness changes and trigger browser loading
        // When the server becomes ready and we have a detected URL, load it in the browser
        readinessDetector.$isReady
            .combineLatest(readinessDetector.$detectedURL)
            .sink { [weak self] isReady, detectedURL in
                // When server becomes ready and we have a URL, load it in the browser
                if isReady, let url = detectedURL {
                    self?.webViewModel.load(url: url)
                    // Cancel timeout timer since server is ready
                    self?.cancelTimeoutTimer()
                    // Hide sidebar when browser is ready
                    self?.isSidebarVisible = false
                }
            }
            .store(in: &cancellables)
        
        // Monitor process exit code for non-zero exits
        processManager.$exitCode
            .sink { [weak self] exitCode in
                guard let exitCode = exitCode, exitCode != 0 else { return }
                // Non-zero exit code is already highlighted in TerminalView
                // We could add additional handling here if needed
                self?.cancelTimeoutTimer()
            }
            .store(in: &cancellables)
        
        // Persist toolbar visibility preference to UserDefaults
        $isToolbarHidden
            .dropFirst()
            .removeDuplicates()
            .sink { UserDefaults.standard.set($0, forKey: "isToolbarHidden") }
            .store(in: &cancellables)
    }
    
    /// Start the server process
    /// This should be called when the app launches (typically from ContentView.onAppear)
    func startServer() {
        os_log(.info, log: logger, "Starting server")
        
        do {
            let resolved = ScriptResolver.resolve(configuration)
            
            // Route any system-browser launches from the server process back into this app.
            processManager.additionalPathDirectories = [browserInterceptor.shimBinDirectory.path]
            processManager.additionalEnvironment[BrowserOpenInterceptor.forwardDirEnvKey] = browserInterceptor.requestsDirectory.path
            
            try processManager.start(
                command: resolved.command,
                arguments: resolved.arguments,
                workingDirectory: configuration.workingDirectory
            )
            
            // Start timeout timer if ready signal pattern is configured
            if configuration.readySignalPattern != nil && !configuration.readySignalPattern!.isEmpty {
                startTimeoutTimer()
            }
        } catch let error as ProcessError {
            // Handle specific process errors with user-friendly messages
            os_log(.error, log: logger, "Process error starting server: %{public}@", error.localizedDescription)
            handleProcessError(error)
        } catch {
            // Handle unexpected errors
            os_log(.error, log: logger, "Unexpected error starting server: %{public}@", error.localizedDescription)
            errorMessage = "Failed to start server: \(error.localizedDescription)"
            showErrorAlert = true
            print("❌ Failed to start server: \(error.localizedDescription)")
        }
    }
    
    /// Restart the server process.
    /// Drives off the actual termination signal instead of a fixed delay, so `start()` never
    /// races a not-yet-dead process and throws `.alreadyRunning` (TASK-4).
    func restartServer() {
        os_log(.info, log: logger, "Restarting server")

        readinessDetector.reset()

        guard processManager.isRunning else {
            // Nothing running — start immediately.
            startServer()
            return
        }

        // Wait for isRunning to flip to false (driven by Process.didTerminateNotification),
        // then start the new process exactly once. The start is dispatched async so it runs AFTER
        // the `@Published isRunning` assignment that triggered us has fully completed — otherwise
        // start() would set isRunning=true re-entrantly inside the willSet and the outer assignment
        // would immediately clobber it back to false, leaving a running server marked "stopped".
        restartCancellable = processManager.$isRunning
            .filter { !$0 }
            .first()
            .sink { [weak self] _ in
                DispatchQueue.main.async { self?.startServer() }
            }

        processManager.terminate()
    }
    
    /// Handle process errors with user-friendly messages
    private func handleProcessError(_ error: ProcessError) {
        switch error {
        case .commandNotFound(let command):
            errorMessage = """
            Command not found: \(command)
            
            The server command could not be found on your system. Please verify:
            • The command is installed
            • The full path is correct
            • You have permission to execute it
            """
        case .permissionDenied(let command):
            errorMessage = """
            Permission denied: \(command)
            
            You don't have permission to execute this command. Please verify:
            • The file has execute permissions
            • You have access to the directory
            • The command is not restricted by system security
            """
        case .alreadyRunning:
            errorMessage = "The server process is already running."
        case .notRunning:
            errorMessage = "The server process is not running."
        case .startFailed(let reason):
            errorMessage = "Failed to start server: \(reason)"
        }
        
        showErrorAlert = true
    }
    
    /// Start the timeout timer for ready signal detection
    private func startTimeoutTimer() {
        os_log(.debug, log: logger, "Starting timeout timer (%d seconds)", Int(timeoutDuration))
        
        // Cancel any existing timer
        timeoutTimer?.invalidate()
        
        // Create a new timer
        timeoutTimer = Timer.scheduledTimer(withTimeInterval: timeoutDuration, repeats: false) { [weak self] _ in
            guard let self = self else { return }
            
            // Check if server is still not ready
            if !self.readinessDetector.isReady && self.processManager.isRunning {
                os_log(.error, log: logger, "Server ready signal timeout after %d seconds", Int(self.timeoutDuration))
                self.showTimeoutAlert = true
            }
        }
    }
    
    /// Cancel the timeout timer
    private func cancelTimeoutTimer() {
        os_log(.debug, log: logger, "Cancelling timeout timer")
        timeoutTimer?.invalidate()
        timeoutTimer = nil
    }
    
    /// Manually open the browser with the configured URL
    func manuallyOpenBrowser() {
        os_log(.info, log: logger, "User manually opening browser")
        
        if let urlString = configuration.localhostURL,
           let url = URL(string: urlString) {
            os_log(.debug, log: logger, "Loading URL: %{public}@", url.absoluteString)
            webViewModel.load(url: url)
            showTimeoutAlert = false
        } else {
            os_log(.error, log: logger, "Invalid localhost URL configuration")
        }
    }
    
    /// Terminate the server process gracefully
    func stopServer() {
        os_log(.info, log: logger, "Stopping server")
        processManager.terminate()
    }

    /// Set once the user has confirmed quitting, so `applicationShouldTerminate` stops re-prompting.
    private(set) var isQuitting = false

    /// Synchronously kill the whole server process tree (so no orphaned grandchild keeps holding
    /// the port) and mark that we're quitting. Safe to call more than once (idempotent). This is
    /// the single cleanup used by every quit path — the confirmation button, a closed window, and
    /// the app's `applicationWillTerminate` safety net — so the port is always freed (TASK-2).
    func prepareForQuit() {
        isQuitting = true
        showCloseConfirmation = false
        processManager.terminateSynchronously()
    }

    /// Confirmed-quit path (the "Quit Anyway" button): kill synchronously, then terminate the app.
    func confirmQuitAndTerminate() {
        os_log(.info, log: logger, "User confirmed quit; killing server tree synchronously")
        prepareForQuit()
        NSApplication.shared.terminate(nil)
    }

    /// Check if the process is running (for close confirmation)
    var isProcessRunning: Bool {
        processManager.isRunning
    }
    
    /// Toggle sidebar visibility
    func toggleSidebar() {
        isSidebarVisible.toggle()
    }
}
