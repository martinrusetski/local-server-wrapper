//
//  TerminalViewTests.swift
//  ServerAppBundleTests
//
//  Created by Kiro
//

import XCTest
import SwiftUI
@testable import ServerAppBundle

@MainActor
final class TerminalViewTests: XCTestCase {

    // Note: `output`, `isRunning`, and `exitCode` are `private(set)` on ProcessManager and it is
    // not an NSObject, so state can't be injected via KVC. These tests drive real state through a
    // real process and verify the view constructs against it. (Deep view-rendering assertions would
    // need a tool like ViewInspector, which the project doesn't depend on.)

    private func runToCompletion(_ pm: ProcessManager, command: String, arguments: [String]) throws {
        try pm.start(command: command, arguments: arguments)
        let expectation = XCTestExpectation(description: "Process completes")
        Task {
            while pm.isRunning {
                try? await Task.sleep(nanoseconds: 100_000_000)
            }
            expectation.fulfill()
        }
        wait(for: [expectation], timeout: 5.0)
    }

    func testTerminalViewConstructsWithFreshManager() {
        let processManager = ProcessManager()
        let terminalView = TerminalView(processManager: processManager)
        XCTAssertNotNil(terminalView)
        XCTAssertEqual(processManager.output, "", "Fresh manager should have empty output")
        XCTAssertNil(processManager.exitCode, "Fresh manager should have no exit code")
    }

    func testTerminalViewReflectsSuccessfulOutput() throws {
        let processManager = ProcessManager()
        try runToCompletion(processManager, command: "/bin/echo", arguments: ["Test output"])

        let terminalView = TerminalView(processManager: processManager)
        XCTAssertNotNil(terminalView)
        XCTAssertTrue(processManager.output.contains("Test output"))
        XCTAssertEqual(processManager.exitCode, 0)
    }

    func testTerminalViewReflectsErrorExitCode() throws {
        let processManager = ProcessManager()
        try runToCompletion(processManager, command: "/bin/sh", arguments: ["-c", "exit 1"])

        let terminalView = TerminalView(processManager: processManager)
        XCTAssertNotNil(terminalView)
        XCTAssertEqual(processManager.exitCode, 1)
    }

    func testTerminalViewBuffersLargeOutputWithoutGrowingUnbounded() throws {
        let processManager = ProcessManager()
        // Emit far more than the retained-buffer cap to confirm trimming keeps it bounded (TASK-3).
        try runToCompletion(processManager, command: "/bin/sh", arguments: ["-c", "yes 'Line of output' | head -n 50000"])

        let terminalView = TerminalView(processManager: processManager)
        XCTAssertNotNil(terminalView)
        // The buffer is capped (~200k chars), so it must not retain the full ~850k chars emitted.
        XCTAssertLessThan(processManager.output.count, 250_000, "Output buffer should be trimmed, not unbounded")
    }
}
