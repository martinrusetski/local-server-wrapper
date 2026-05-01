//
//  ProcessManagerTests.swift
//  ServerAppBundleTests
//
//  Created by Kiro
//

import XCTest
@testable import ServerAppBundle

@MainActor
final class ProcessManagerTests: XCTestCase {
    
    var processManager: ProcessManager!
    
    override func setUp() async throws {
        processManager = ProcessManager()
    }
    
    override func tearDown() async throws {
        if processManager.isRunning {
            processManager.forceKill()
        }
        processManager = nil
    }
    
    // MARK: - Basic Functionality Tests
    
    func testProcessManagerInitialState() {
        XCTAssertFalse(processManager.isRunning, "Process should not be running initially")
        XCTAssertNil(processManager.exitCode, "Exit code should be nil initially")
        XCTAssertEqual(processManager.output, "", "Output should be empty initially")
    }
    
    func testStartSimpleCommand() throws {
        // Start a simple echo command
        try processManager.start(command: "/bin/echo", arguments: ["Hello, World!"])
        
        XCTAssertTrue(processManager.isRunning, "Process should be running after start")
        XCTAssertNil(processManager.exitCode, "Exit code should be nil while running")
        
        // Wait for process to complete
        let expectation = XCTestExpectation(description: "Process completes")
        
        Task {
            // Poll until process completes
            while processManager.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssertFalse(processManager.isRunning, "Process should not be running after completion")
        XCTAssertEqual(processManager.exitCode, 0, "Exit code should be 0 for successful command")
        XCTAssertTrue(processManager.output.contains("Hello, World!"), "Output should contain the echoed text")
    }
    
    func testStartCommandNotFound() {
        // Try to start a non-existent command
        XCTAssertThrowsError(try processManager.start(command: "/nonexistent/command", arguments: [])) { error in
            guard let processError = error as? ProcessError else {
                XCTFail("Expected ProcessError")
                return
            }
            
            if case .commandNotFound = processError {
                // Expected error
            } else {
                XCTFail("Expected commandNotFound error, got \(processError)")
            }
        }
    }
    
    func testStartAlreadyRunning() throws {
        // Start a long-running command
        try processManager.start(command: "/bin/sleep", arguments: ["10"])
        
        XCTAssertTrue(processManager.isRunning, "Process should be running")
        
        // Try to start another command while one is running
        XCTAssertThrowsError(try processManager.start(command: "/bin/echo", arguments: ["test"])) { error in
            guard let processError = error as? ProcessError else {
                XCTFail("Expected ProcessError")
                return
            }
            
            if case .alreadyRunning = processError {
                // Expected error
            } else {
                XCTFail("Expected alreadyRunning error, got \(processError)")
            }
        }
        
        // Clean up
        processManager.forceKill()
    }
    
    func testTerminateProcess() throws {
        // Start a long-running command
        try processManager.start(command: "/bin/sleep", arguments: ["10"])
        
        XCTAssertTrue(processManager.isRunning, "Process should be running")
        
        // Terminate the process
        processManager.terminate()
        
        // Wait for termination
        let expectation = XCTestExpectation(description: "Process terminates")
        
        Task {
            // Poll until process completes
            while processManager.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssertFalse(processManager.isRunning, "Process should not be running after termination")
        XCTAssertNotNil(processManager.exitCode, "Exit code should be set after termination")
    }
    
    func testForceKillProcess() throws {
        // Start a long-running command
        try processManager.start(command: "/bin/sleep", arguments: ["10"])
        
        XCTAssertTrue(processManager.isRunning, "Process should be running")
        
        // Force kill the process
        processManager.forceKill()
        
        // Force kill should be immediate
        XCTAssertFalse(processManager.isRunning, "Process should not be running after force kill")
    }
    
    func testOutputCapture() throws {
        // Start a command that produces output
        try processManager.start(command: "/bin/sh", arguments: ["-c", "echo 'Line 1'; echo 'Line 2'; echo 'Line 3'"])
        
        // Wait for process to complete
        let expectation = XCTestExpectation(description: "Process completes")
        
        Task {
            // Poll until process completes
            while processManager.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Check that all output was captured
        XCTAssertTrue(processManager.output.contains("Line 1"), "Output should contain Line 1")
        XCTAssertTrue(processManager.output.contains("Line 2"), "Output should contain Line 2")
        XCTAssertTrue(processManager.output.contains("Line 3"), "Output should contain Line 3")
    }
    
    func testStderrCapture() throws {
        // Start a command that produces stderr output
        try processManager.start(command: "/bin/sh", arguments: ["-c", "echo 'Error message' >&2"])
        
        // Wait for process to complete
        let expectation = XCTestExpectation(description: "Process completes")
        
        Task {
            // Poll until process completes
            while processManager.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        // Check that stderr was captured
        XCTAssertTrue(processManager.output.contains("Error message"), "Output should contain stderr message")
    }
    
    func testNonZeroExitCode() throws {
        // Start a command that exits with non-zero code
        try processManager.start(command: "/bin/sh", arguments: ["-c", "exit 42"])
        
        // Wait for process to complete
        let expectation = XCTestExpectation(description: "Process completes")
        
        Task {
            // Poll until process completes
            while processManager.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000) // 0.1 seconds
            }
            expectation.fulfill()
        }
        
        wait(for: [expectation], timeout: 5.0)
        
        XCTAssertEqual(processManager.exitCode, 42, "Exit code should be 42")
        XCTAssertTrue(processManager.output.contains("exited with code 42"), "Output should mention exit code")
    }
}
