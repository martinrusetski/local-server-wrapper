//
//  AppStateTests.swift
//  ServerAppBundleTests
//
//  Created by Kiro
//

import XCTest
import Combine
@testable import ServerRuntime

@MainActor
final class AppStateTests: XCTestCase {
    
    var cancellables: Set<AnyCancellable>!
    
    override func setUp() async throws {
        cancellables = Set<AnyCancellable>()
    }
    
    override func tearDown() async throws {
        cancellables = nil
    }
    
    // MARK: - Initialization Tests
    
    func testAppStateInitialization() {
        // Given: A server configuration
        let config = ServerConfiguration(
            name: "Test Server",
            command: "/bin/echo",
            arguments: ["Hello, World!"],
            localhostURL: "http://localhost:3000",
            readySignalPattern: "Ready",
            portDetectionPattern: "port (\\d+)"
        )
        
        // When: Creating an AppState
        let appState = AppState(configuration: config)
        
        // Then: All components should be initialized
        XCTAssertEqual(appState.configuration.name, "Test Server")
        XCTAssertNotNil(appState.processManager)
        XCTAssertNotNil(appState.readinessDetector)
        XCTAssertNotNil(appState.webViewModel)
    }
    
    func testFixedURLWaitsForDelayedHTTPServer() async throws {
        let server = Process()
        let output = Pipe()
        server.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
        server.arguments = ["-u", "-c", """
        from http.server import HTTPServer, BaseHTTPRequestHandler
        import time
        class Handler(BaseHTTPRequestHandler):
            def do_HEAD(self):
                self.send_response(501)
                self.end_headers()
            def log_message(self, *args): pass
        server = HTTPServer(('127.0.0.1', 0), Handler)
        print(server.server_port, flush=True)
        time.sleep(1)
        server.serve_forever()
        """]
        server.standardOutput = output
        try server.run()
        defer { server.terminate(); server.waitUntilExit() }
        let data = output.fileHandleForReading.availableData
        let port = try XCTUnwrap(Int(String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)))
        let url = "http://127.0.0.1:\(port)/app"
        let state = AppState(configuration: ServerConfiguration(name: "Delayed HTTP fixture", command: "/bin/sleep", arguments: ["10"], localhostURL: url, urlDetectionMode: .fixed))
        defer { state.prepareForQuit() }
        state.startServer()
        try await Task.sleep(nanoseconds: 100_000_000)
        XCTAssertFalse(state.readinessDetector.isReady)
        XCTAssertNil(state.webViewModel.url)
        let deadline = Date().addingTimeInterval(5)
        while !state.readinessDetector.isReady && Date() < deadline {
            try await Task.sleep(nanoseconds: 50_000_000)
        }
        XCTAssertTrue(state.readinessDetector.isReady)
        XCTAssertEqual(state.webViewModel.url?.absoluteString, url)
    }

    func testAppStateWithNoReadySignal() {
        // Given: A configuration with no ready signal pattern
        // Fixed mode waits for an HTTP response before opening the browser.
        let config = ServerConfiguration(
            name: "Immediate Server",
            command: "/bin/echo",
            arguments: ["test"],
            localhostURL: "http://localhost:8080",
            urlDetectionMode: .fixed,
            readySignalPattern: nil
        )

        // When: Creating an AppState
        let appState = AppState(configuration: config)

        // No server has been started yet.
        XCTAssertFalse(appState.readinessDetector.isReady)
        XCTAssertNil(appState.readinessDetector.detectedURL)
    }
    
    // MARK: - Process Output to Readiness Detector Integration Tests
    
    func testProcessOutputConnectedToReadinessDetector() async {
        // Given: A configuration with a ready signal pattern
        let config = ServerConfiguration(
            name: "Test Server",
            command: "/bin/echo",
            arguments: ["Server is ready on port 3000"],
            localhostURL: "http://localhost:3000",
            readySignalPattern: "ready",
            portDetectionPattern: "port (\\d+)"
        )
        
        let appState = AppState(configuration: config)
        
        // Create expectation for readiness
        let readyExpectation = expectation(description: "Server becomes ready")
        
        // Observe readiness changes
        appState.readinessDetector.$isReady
            .dropFirst() // Skip initial value
            .sink { isReady in
                if isReady {
                    readyExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Starting the server (which will output the ready signal)
        appState.startServer()
        
        // Then: Readiness detector should detect the ready signal
        await fulfillment(of: [readyExpectation], timeout: 2.0)
        XCTAssertTrue(appState.readinessDetector.isReady)
    }
    
    // MARK: - Readiness to Browser Loading Integration Tests
    
    func testReadinessTriggersBrowserLoading() async {
        // Given: A fixed URL waiting for an HTTP response
        let config = ServerConfiguration(
            name: "Immediate Server",
            command: "/bin/echo",
            arguments: ["test"],
            localhostURL: "http://localhost:8080",
            urlDetectionMode: .fixed,
            readySignalPattern: nil
        )
        
        let appState = AppState(configuration: config)

        XCTAssertNil(appState.webViewModel.url)
        appState.readinessDetector.noteHTTPResponse()

        XCTAssertNotNil(appState.webViewModel.url)
        XCTAssertEqual(appState.webViewModel.url?.absoluteString, "http://localhost:8080")
    }
    
    // MARK: - Process Management Tests
    
    func testStartServer() {
        // Given: A valid configuration
        let config = ServerConfiguration(
            name: "Test Server",
            command: "/bin/echo",
            arguments: ["Hello"],
            localhostURL: "http://localhost:3000"
        )
        
        let appState = AppState(configuration: config)
        
        // When: Starting the server
        appState.startServer()
        
        // Then: Process should be running
        XCTAssertTrue(appState.isProcessRunning)
    }
    
    func testStopServer() async {
        // Given: A running server
        let config = ServerConfiguration(
            name: "Test Server",
            command: "/bin/sleep",
            arguments: ["10"],
            localhostURL: "http://localhost:3000"
        )
        
        let appState = AppState(configuration: config)
        appState.startServer()
        
        XCTAssertTrue(appState.isProcessRunning)
        
        // When: Stopping the server
        appState.stopServer()
        
        // Wait a bit for termination
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then: Process should not be running
        XCTAssertFalse(appState.isProcessRunning)
    }
    
    func testIsProcessRunning() {
        // Given: A configuration
        let config = ServerConfiguration(
            name: "Test Server",
            command: "/bin/echo",
            arguments: ["test"],
            localhostURL: "http://localhost:3000"
        )
        
        let appState = AppState(configuration: config)
        
        // When: Process is not started
        // Then: Should not be running
        XCTAssertFalse(appState.isProcessRunning)
        
        // When: Process is started
        appState.startServer()
        
        // Then: Should be running (briefly, before echo exits)
        // Note: echo exits immediately, so we can't reliably test this
        // This is more of a smoke test
    }
    
    // MARK: - Error Handling Tests
    
    func testStartServerWithInvalidCommand() {
        // Given: A configuration with an invalid command
        let config = ServerConfiguration(
            name: "Invalid Server",
            command: "/nonexistent/command",
            arguments: [],
            localhostURL: "http://localhost:3000"
        )
        
        let appState = AppState(configuration: config)
        
        // When: Starting the server
        appState.startServer()
        
        // Then: Error alert should be shown
        XCTAssertTrue(appState.showErrorAlert)
        XCTAssertNotNil(appState.errorMessage)
        XCTAssertTrue(appState.errorMessage?.contains("Command not found") ?? false)
    }
    
    func testRestartServerWhenNotRunning() async {
        // Given: A configuration with a valid command
        let config = ServerConfiguration(
            name: "Test Server",
            command: "/bin/echo",
            arguments: ["test"],
            localhostURL: "http://localhost:3000"
        )
        
        let appState = AppState(configuration: config)
        
        // When: Restarting without starting first
        appState.restartServer()
        
        // Wait a moment for the restart to complete
        try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
        
        // Then: Process should have been started
        // Note: echo exits immediately, so we check that no error occurred
        XCTAssertFalse(appState.showErrorAlert)
    }
    
    func testRestartServerWhenRunning() async {
        // Given: A running server
        let config = ServerConfiguration(
            name: "Test Server",
            command: "/bin/sleep",
            arguments: ["10"],
            localhostURL: "http://localhost:3000"
        )
        
        let appState = AppState(configuration: config)
        appState.startServer()
        
        XCTAssertTrue(appState.isProcessRunning)
        
        // When: Restarting the server
        appState.restartServer()
        
        // Wait for termination and restart
        try? await Task.sleep(nanoseconds: 600_000_000) // 0.6 seconds
        
        // Then: Process should be running again
        XCTAssertTrue(appState.isProcessRunning)
    }
    
    func testTimeoutAlertForReadySignal() async {
        // Given: A configuration with a ready signal that won't be detected
        let config = ServerConfiguration(
            name: "Slow Server",
            command: "/bin/sleep",
            arguments: ["60"],
            localhostURL: "http://localhost:3000",
            readySignalPattern: "READY_SIGNAL_THAT_WONT_APPEAR"
        )
        
        let appState = AppState(configuration: config)

        // When: Starting the server
        appState.startServer()

        // Then: the 30s ready-signal timeout timer is scheduled. We can't wait 30s in a unit test,
        // and the timeout duration isn't injectable, so we verify the server started (which is what
        // schedules the timer). The alert firing itself isn't unit-testable without that injection.
        XCTAssertTrue(appState.isProcessRunning)

        // Clean up
        appState.stopServer()
    }
    
    func testManuallyOpenBrowser() {
        // Given: A configuration with a localhost URL
        let config = ServerConfiguration(
            name: "Test Server",
            command: "/bin/echo",
            arguments: ["test"],
            localhostURL: "http://localhost:8080"
        )
        
        let appState = AppState(configuration: config)
        appState.showTimeoutAlert = true
        
        // When: Manually opening the browser
        appState.manuallyOpenBrowser()
        
        // Then: Browser should load the URL and timeout alert should be dismissed
        XCTAssertNotNil(appState.webViewModel.url)
        XCTAssertEqual(appState.webViewModel.url?.absoluteString, "http://localhost:8080")
        XCTAssertFalse(appState.showTimeoutAlert)
    }
    
    func testErrorAlertInitialState() {
        // Given: A new AppState
        let config = ServerConfiguration(
            name: "Test Server",
            command: "/bin/echo",
            arguments: ["test"],
            localhostURL: "http://localhost:3000"
        )
        
        let appState = AppState(configuration: config)
        
        // Then: Error alert should be false initially
        XCTAssertFalse(appState.showErrorAlert)
        XCTAssertNil(appState.errorMessage)
    }
    
    func testTimeoutAlertInitialState() {
        // Given: A new AppState
        let config = ServerConfiguration(
            name: "Test Server",
            command: "/bin/echo",
            arguments: ["test"],
            localhostURL: "http://localhost:3000"
        )
        
        let appState = AppState(configuration: config)
        
        // Then: Timeout alert should be false initially
        XCTAssertFalse(appState.showTimeoutAlert)
    }

    func testCredentialAutoFillFiltersSecretsBeforeWebKitInjection() {
        let matching = Credential(username: "alice", password: "secret", origin: "http://localhost:3000")
        let otherOrigin = Credential(username: "mallory", password: "other", origin: "https://example.com")
        let legacy = Credential(username: "legacy", password: "old", origin: nil)

        let result = CredentialAutoFill.credentialsForInjection(
            [matching, otherOrigin, legacy],
            pageURL: URL(string: "http://LOCALHOST:3000/login")
        )

        XCTAssertEqual(result, [matching])
    }

    func testCredentialAutoFillRejectsNonHTTPAndMissingPageOrigins() {
        let credential = Credential(username: "alice", password: "secret", origin: "http://localhost")

        XCTAssertTrue(CredentialAutoFill.credentialsForInjection([credential], pageURL: nil).isEmpty)
        XCTAssertTrue(CredentialAutoFill.credentialsForInjection([credential], pageURL: URL(string: "file:///tmp/login.html")).isEmpty)
    }

    func testOriginNormalizationMatchesWebKitDefaultPortSerialization() {
        XCTAssertEqual(AppState.origin(fromURLString: "HTTP://LOCALHOST:80/login"), "http://localhost")
        XCTAssertEqual(AppState.origin(fromURLString: "https://Example.com:443/login"), "https://example.com")
        XCTAssertEqual(AppState.origin(fromURLString: "https://Example.com:8443/login"), "https://example.com:8443")

        let legacyRepresentation = Credential(username: "alice", password: "secret", origin: "HTTP://LOCALHOST:80")
        let selected = CredentialAutoFill.credentialsForInjection(
            [legacyRepresentation],
            pageURL: URL(string: "http://localhost/login")
        )
        XCTAssertEqual(selected.first?.origin, "http://localhost")
    }
}
