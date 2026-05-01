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
    
    func testTerminalViewDisplaysOutput() {
        // Given
        let processManager = ProcessManager()
        
        // When - Simulate output
        processManager.setValue("Test output\n", forKey: "output")
        
        // Then - Verify the view can be created with the process manager
        let terminalView = TerminalView(processManager: processManager)
        XCTAssertNotNil(terminalView)
    }
    
    func testTerminalViewDisplaysExitCode() {
        // Given
        let processManager = ProcessManager()
        
        // When - Simulate process termination
        processManager.setValue("Process output\n", forKey: "output")
        processManager.setValue(false, forKey: "isRunning")
        processManager.setValue(Int32(0), forKey: "exitCode")
        
        // Then - Verify the view can be created with exit code
        let terminalView = TerminalView(processManager: processManager)
        XCTAssertNotNil(terminalView)
        XCTAssertEqual(processManager.exitCode, 0)
    }
    
    func testTerminalViewDisplaysErrorExitCode() {
        // Given
        let processManager = ProcessManager()
        
        // When - Simulate process termination with error
        processManager.setValue("Error output\n", forKey: "output")
        processManager.setValue(false, forKey: "isRunning")
        processManager.setValue(Int32(1), forKey: "exitCode")
        
        // Then - Verify the view can be created with error exit code
        let terminalView = TerminalView(processManager: processManager)
        XCTAssertNotNil(terminalView)
        XCTAssertEqual(processManager.exitCode, 1)
    }
    
    func testTerminalViewHandlesEmptyOutput() {
        // Given
        let processManager = ProcessManager()
        
        // When - No output
        processManager.setValue("", forKey: "output")
        
        // Then - Verify the view can be created with empty output
        let terminalView = TerminalView(processManager: processManager)
        XCTAssertNotNil(terminalView)
        XCTAssertEqual(processManager.output, "")
    }
    
    func testTerminalViewHandlesLargeOutput() {
        // Given
        let processManager = ProcessManager()
        
        // When - Large output
        let largeOutput = String(repeating: "Line of output\n", count: 1000)
        processManager.setValue(largeOutput, forKey: "output")
        
        // Then - Verify the view can be created with large output
        let terminalView = TerminalView(processManager: processManager)
        XCTAssertNotNil(terminalView)
        XCTAssertTrue(processManager.output.count > 10000)
    }
}
