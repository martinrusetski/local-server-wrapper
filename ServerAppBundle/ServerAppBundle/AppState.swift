//
//  AppState.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import Foundation
import Combine
import os.log

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
    
    /// Whether to show the close confirmation dialog
    @Published var showCloseConfirmation: Bool = false
    
    /// Error message to display to the user
    @Published var errorMessage: String?
    
    /// Whether to show the error alert
    @Published var showErrorAlert: Bool = false
    
    /// Whether to show the timeout alert
    @Published var showTimeoutAlert: Bool = false
    
    /// Combine cancellables for managing subscriptions
    private var cancellables = Set<AnyCancellable>()
    
    /// Timer for ready signal timeout detection
    private var timeoutTimer: Timer?
    
    /// Timeout duration in seconds (default: 30)
    private let timeoutDuration: TimeInterval = 30
    
    /// Initialize app state with a configuration
    /// - Parameter configuration: The server configuration to use
    init(configuration: ServerConfiguration) {
        os_log(.info, log: logger, "Initializing app state for configuration: %{public}@", configuration.name)
        
        self.configuration = configuration
        
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
        
        // Set up Combine subscriptions to connect components
        setupSubscriptions()
        
        os_log(.debug, log: logger, "App state initialized successfully")
    }
    
    /// Set up Combine subscriptions to connect process output to readiness detector
    /// and trigger browser loading when ready
    private func setupSubscriptions() {
        // Connect process output to readiness detector
        // This monitors terminal output and detects ready signals and port numbers
        processManager.$output
            .sink { [weak self] output in
                self?.readinessDetector.monitor(output: output)
            }
            .store(in: &cancellables)
        
        // Observe readiness changes and trigger browser loading
        // When the server becomes ready and we have a detected URL, load it in the browser
        readinessDetector.$isReady
            .combineLatest(readinessDetector.$detectedURL)
            .sink { [weak self] isReady, detectedURL in
                print("📡 Readiness changed - isReady: \(isReady), URL: \(detectedURL?.absoluteString ?? "nil")")
                
                // When server becomes ready and we have a URL, load it in the browser
                if isReady, let url = detectedURL {
                    print("🚀 Loading URL in browser: \(url.absoluteString)")
                    self?.webViewModel.load(url: url)
                    // Cancel timeout timer since server is ready
                    self?.cancelTimeoutTimer()
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
    }
    
    /// Start the server process
    /// This should be called when the app launches (typically from ContentView.onAppear)
    func startServer() {
        os_log(.info, log: logger, "Starting server")
        
        do {
            try processManager.start(
                command: configuration.command,
                arguments: configuration.arguments
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
    
    /// Restart the server process
    func restartServer() {
        os_log(.info, log: logger, "Restarting server")
        
        // Stop the current process if running
        if processManager.isRunning {
            processManager.terminate()
            // Wait a moment for cleanup
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                self?.startServer()
            }
        } else {
            // Reset readiness detector
            readinessDetector.reset()
            // Start immediately
            startServer()
        }
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
    
    /// Check if the process is running (for close confirmation)
    var isProcessRunning: Bool {
        processManager.isRunning
    }
}
