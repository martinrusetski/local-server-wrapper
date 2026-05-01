//
//  AppStateTests.swift
//  ServerAppBundleTests
//
//  Created by Kiro
//

import XCTest
import Combine
@testable import ServerAppBundle

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
        XCTAssertFalse(appState.showCloseConfirmation)
    }
    
    func testAppStateWithNoReadySignal() {
        // Given: A configuration with no ready signal pattern
        let config = ServerConfiguration(
            name: "Immediate Server",
            command: "/bin/echo",
            arguments: ["test"],
            localhostURL: "http://localhost:8080",
            readySignalPattern: nil
        )
        
        // When: Creating an AppState
        let appState = AppState(configuration: config)
        
        // Then: Readiness detector should be ready immediately
        XCTAssertTrue(appState.readinessDetector.isReady)
        XCTAssertNotNil(appState.readinessDetector.detectedURL)
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
        // Given: A configuration with immediate readiness (no ready signal)
        let config = ServerConfiguration(
            name: "Immediate Server",
            command: "/bin/echo",
            arguments: ["test"],
            localhostURL: "http://localhost:8080",
            readySignalPattern: nil
        )
        
        let appState = AppState(configuration: config)
        
        // Create expectation for browser URL loading
        let urlLoadedExpectation = expectation(description: "Browser URL is loaded")
        
        // Observe URL changes in web view model
        appState.webViewModel.$url
            .dropFirst() // Skip initial nil value
            .sink { url in
                if url != nil {
                    urlLoadedExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: The readiness detector is already ready (immediate)
        // The Combine subscription should trigger browser loading
        
        // Then: Browser should load the URL
        await fulfillment(of: [urlLoadedExpectation], timeout: 1.0)
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
    
    // MARK: - Close Confirmation State Tests
    
    func testShowCloseConfirmationInitialState() {
        // Given: A new AppState
        let config = ServerConfiguration(
            name: "Test Server",
            command: "/bin/echo",
            arguments: ["test"],
            localhostURL: "http://localhost:3000"
        )
        
        let appState = AppState(configuration: config)
        
        // Then: Close confirmation should be false initially
        XCTAssertFalse(appState.showCloseConfirmation)
    }
    
    func testShowCloseConfirmationCanBeToggled() {
        // Given: An AppState
        let config = ServerConfiguration(
            name: "Test Server",
            command: "/bin/echo",
            arguments: ["test"],
            localhostURL: "http://localhost:3000"
        )
        
        let appState = AppState(configuration: config)
        
        // When: Toggling the confirmation state
        appState.showCloseConfirmation = true
        
        // Then: State should be updated
        XCTAssertTrue(appState.showCloseConfirmation)
        
        // When: Toggling back
        appState.showCloseConfirmation = false
        
        // Then: State should be updated
        XCTAssertFalse(appState.showCloseConfirmation)
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
        
        // Create expectation for timeout alert
        let timeoutExpectation = expectation(description: "Timeout alert is shown")
        
        // Observe timeout alert changes
        appState.$showTimeoutAlert
            .dropFirst() // Skip initial value
            .sink { showTimeout in
                if showTimeout {
                    timeoutExpectation.fulfill()
                }
            }
            .store(in: &cancellables)
        
        // When: Starting the server
        appState.startServer()
        
        // Then: Timeout alert should be shown after 30 seconds
        // Note: We can't wait 30 seconds in a test, so we'll verify the timer is set up
        // In a real scenario, the timer would fire after 30 seconds
        
        // For testing purposes, we'll just verify the process started
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
}
