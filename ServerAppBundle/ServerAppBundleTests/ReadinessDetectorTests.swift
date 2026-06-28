//
//  ReadinessDetectorTests.swift
//  ServerAppBundleTests
//
//  Created by Kiro
//

import XCTest
@testable import ServerAppBundle

@MainActor
class ReadinessDetectorTests: XCTestCase {
    
    // MARK: - Graceful Degradation Tests
    
    func testFallbackToBaseURLWhenPortDetectionFails() async {
        // Given: A detector with port detection pattern that won't match
        let detector = ReadinessDetector(
            readySignalPattern: "Server listening",
            portDetectionPattern: "port (\\d+)",
            baseURL: "http://localhost:3000"
        )
        
        // When: We monitor output with ready signal but no port
        detector.monitor(output: "Server listening on unknown port")
        
        // Then: Should be ready and use base URL
        XCTAssertTrue(detector.isReady, "Detector should be ready even without port detection")
        XCTAssertNotNil(detector.detectedURL, "Should have a detected URL")
        XCTAssertEqual(detector.detectedURL?.absoluteString, "http://localhost:3000", "Should fall back to base URL")
    }
    
    func testFallbackToBaseURLWhenPortDetectionPatternInvalid() async {
        // Given: A detector with invalid port detection pattern
        let detector = ReadinessDetector(
            readySignalPattern: "Server listening",
            portDetectionPattern: "[invalid(regex",  // Invalid regex
            baseURL: "http://localhost:8080"
        )
        
        // When: We monitor output with ready signal
        detector.monitor(output: "Server listening on port 3000")
        
        // Then: Should be ready and use base URL (since regex compilation failed)
        XCTAssertTrue(detector.isReady, "Detector should be ready even with invalid port pattern")
        XCTAssertNotNil(detector.detectedURL, "Should have a detected URL")
        XCTAssertEqual(detector.detectedURL?.absoluteString, "http://localhost:8080", "Should fall back to base URL")
    }
    
    func testSuccessfulPortDetection() async {
        // Given: A detector with valid port detection pattern
        let detector = ReadinessDetector(
            readySignalPattern: "Server listening",
            portDetectionPattern: "port (\\d+)",
            baseURL: "http://localhost:3000"
        )
        
        // When: We monitor output with ready signal and port
        detector.monitor(output: "Server listening on port 8080")
        
        // Then: Should be ready and use detected port
        XCTAssertTrue(detector.isReady, "Detector should be ready")
        XCTAssertNotNil(detector.detectedURL, "Should have a detected URL")
        XCTAssertEqual(detector.detectedURL?.absoluteString, "http://localhost:8080", "Should use detected port")
    }
    
    func testNoReadySignalPatternMarksReadyImmediately() async {
        // Given: A detector with no ready signal pattern
        let detector = ReadinessDetector(
            readySignalPattern: nil,
            portDetectionPattern: nil,
            baseURL: "http://localhost:5000"
        )
        
        // Then: Should be ready immediately
        XCTAssertTrue(detector.isReady, "Detector should be ready immediately when no pattern configured")
        XCTAssertNotNil(detector.detectedURL, "Should have a detected URL")
        XCTAssertEqual(detector.detectedURL?.absoluteString, "http://localhost:5000", "Should use base URL")
    }
    
    func testEmptyReadySignalPatternMarksReadyImmediately() async {
        // Given: A detector with empty ready signal pattern
        let detector = ReadinessDetector(
            readySignalPattern: "",
            portDetectionPattern: nil,
            baseURL: "http://localhost:4000"
        )
        
        // Then: Should be ready immediately
        XCTAssertTrue(detector.isReady, "Detector should be ready immediately when pattern is empty")
        XCTAssertNotNil(detector.detectedURL, "Should have a detected URL")
        XCTAssertEqual(detector.detectedURL?.absoluteString, "http://localhost:4000", "Should use base URL")
    }
    
    func testResetResetsState() async {
        // Given: A ready detector
        let detector = ReadinessDetector(
            readySignalPattern: "Ready",
            portDetectionPattern: nil,
            baseURL: "http://localhost:3000"
        )
        detector.monitor(output: "Ready")
        XCTAssertTrue(detector.isReady)
        
        // When: We reset
        detector.reset()
        
        // Then: Should not be ready anymore
        XCTAssertFalse(detector.isReady, "Detector should not be ready after reset")
        XCTAssertNil(detector.detectedURL, "Detected URL should be nil after reset")
    }
    
    // MARK: - Automatic Mode Tests

    func testAutomaticModeDoesNotMarkReadyImmediately() async {
        // Given: Automatic mode with no ready-signal pattern
        let detector = ReadinessDetector(
            readySignalPattern: nil,
            portDetectionPattern: nil,
            baseURL: "http://localhost:3000",
            mode: .automatic
        )

        // Then: Should NOT be ready until a real signal arrives (unlike fixed mode)
        XCTAssertFalse(detector.isReady, "Automatic mode must wait for a real readiness signal")
        XCTAssertNil(detector.detectedURL)
    }

    func testAutomaticModeBecomesReadyOnGenericURLInOutput() async {
        // Given: Automatic mode, no patterns
        let detector = ReadinessDetector(
            readySignalPattern: nil,
            portDetectionPattern: nil,
            baseURL: "http://localhost:3000",
            mode: .automatic
        )

        // When: The server prints a loopback URL (as Vite/Next/etc. do)
        detector.monitor(output: "  ➜  Local:   http://localhost:5173/\n")

        // Then: Becomes ready at the printed port, host normalized to localhost
        XCTAssertTrue(detector.isReady)
        XCTAssertEqual(detector.detectedURL?.absoluteString, "http://localhost:5173")
    }

    func testAutomaticModeIgnoresNonURLOutput() async {
        // Given: Automatic mode, no patterns
        let detector = ReadinessDetector(
            readySignalPattern: nil,
            portDetectionPattern: nil,
            baseURL: "http://localhost:3000",
            mode: .automatic
        )

        // When: The server prints chatter without a URL
        detector.monitor(output: "Compiling modules...\nwarning: something\n")

        // Then: Still waiting (the OS port observation, not output, will resolve this)
        XCTAssertFalse(detector.isReady)
    }

    func testNoteListeningPortMarksReady() async {
        // Given: Automatic mode waiting
        let detector = ReadinessDetector(
            readySignalPattern: nil,
            portDetectionPattern: nil,
            baseURL: "https://localhost:3000",
            mode: .automatic
        )
        XCTAssertFalse(detector.isReady)

        // When: The OS reports the server is listening on a port
        detector.noteListeningPort(8123)

        // Then: Ready, with the observed port spliced into the base URL's scheme/host
        XCTAssertTrue(detector.isReady)
        XCTAssertEqual(detector.detectedURL?.absoluteString, "https://localhost:8123")
    }

    func testNoteListeningPortIgnoredOnceReady() async {
        // Given: A detector already made ready by output
        let detector = ReadinessDetector(
            readySignalPattern: nil,
            portDetectionPattern: nil,
            baseURL: "http://localhost:3000",
            mode: .automatic
        )
        detector.monitor(output: "http://localhost:5173/\n")
        XCTAssertEqual(detector.detectedURL?.absoluteString, "http://localhost:5173")

        // When: A later OS observation arrives
        detector.noteListeningPort(9999)

        // Then: First signal wins; the URL doesn't change
        XCTAssertEqual(detector.detectedURL?.absoluteString, "http://localhost:5173")
    }

    func testResetWithNoPatternMarksReadyImmediately() async {
        // Given: A detector with no pattern
        let detector = ReadinessDetector(
            readySignalPattern: nil,
            portDetectionPattern: nil,
            baseURL: "http://localhost:3000"
        )
        XCTAssertTrue(detector.isReady)
        
        // When: We reset
        detector.reset()
        
        // Then: Should be ready immediately again
        XCTAssertTrue(detector.isReady, "Detector should be ready immediately after reset when no pattern configured")
        XCTAssertNotNil(detector.detectedURL, "Should have a detected URL")
    }
}
