//
//  ProcessManagerTests.swift
//  ServerAppBundleTests
//
//  Created by Kiro
//

import XCTest
@testable import ServerRuntime

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

    // MARK: - Bare-command PATH resolution (TASK-1)

    func testResolveBareCommandFindsExecutableOnPath() throws {
        // `sh` lives in /bin, which is part of the default search directories.
        let dirs = ProcessManager.searchPathDirectories(additional: [])
        let resolved = try ProcessManager.resolveExecutable("sh", searchDirectories: dirs)
        XCTAssertEqual(resolved, "/bin/sh", "Bare 'sh' should resolve to /bin/sh via PATH lookup")
    }

    func testResolveAbsolutePathPassesThrough() throws {
        let resolved = try ProcessManager.resolveExecutable("/bin/echo", searchDirectories: [])
        XCTAssertEqual(resolved, "/bin/echo", "Absolute path should be used as-is")
    }

    func testResolveMissingBareCommandThrows() {
        let dirs = ProcessManager.searchPathDirectories(additional: [])
        XCTAssertThrowsError(try ProcessManager.resolveExecutable("definitely-not-a-real-command-xyz", searchDirectories: dirs)) { error in
            guard case ProcessError.commandNotFound = error else {
                return XCTFail("Expected commandNotFound, got \(error)")
            }
        }
    }

    func testStartBareCommandLaunches() throws {
        // A bare command name (no slash) must resolve via PATH and launch — previously this threw
        // commandNotFound because Process does no PATH lookup for executableURL.
        try processManager.start(command: "echo", arguments: ["bare-command-works"])
        XCTAssertTrue(processManager.isRunning, "Bare command should launch without commandNotFound")

        let expectation = XCTestExpectation(description: "Process completes")
        Task {
            while processManager.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        XCTAssertEqual(processManager.exitCode, 0)
        XCTAssertTrue(processManager.output.contains("bare-command-works"), "Output should contain echoed text")
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
    
    // MARK: - Pseudo-terminal Tests

    // We probe the tty via `test -t 1`'s exit status rather than echoing literal "TTY"/"PIPE"
    // markers: the startup message echoes the whole command line, so any literal marker in the
    // command would also appear in the output. The status digit ("tty_status=0/1") only appears in
    // the child's real output, never in the echoed `...=$?` command text.

    func testPseudoTerminalMakesChildSeeATTY() throws {
        // Under the default PTY launch, a script's `[ -t 1 ]` check must pass — this is what makes
        // terminal-gated servers (e.g. Lumiverse) actually start.
        try processManager.start(command: "/bin/sh", arguments: ["-c", "test -t 1; echo tty_status=$?"], usePseudoTerminal: true)

        let expectation = XCTestExpectation(description: "Process completes")
        Task {
            while processManager.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        XCTAssertTrue(processManager.output.contains("tty_status=0"), "Child should detect an interactive terminal (status 0) under PTY mode")
    }

    func testPipeModeChildSeesNoTTY() throws {
        // The escape-hatch (runWithoutTerminal) must still behave like a plain pipe.
        try processManager.start(command: "/bin/sh", arguments: ["-c", "test -t 1; echo tty_status=$?"], usePseudoTerminal: false)

        let expectation = XCTestExpectation(description: "Process completes")
        Task {
            while processManager.isRunning { try? await Task.sleep(nanoseconds: 100_000_000) }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)

        XCTAssertTrue(processManager.output.contains("tty_status=1"), "Child should see a pipe (status 1) when PTY is disabled")
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
