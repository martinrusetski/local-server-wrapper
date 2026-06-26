//
//  ReadinessDetector.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import Foundation
import Combine
import os.log

/// Logger for readiness detection operations
private let logger = OSLog(subsystem: "com.localserverwrapper.serverappbundle", category: "readiness")

/// Protocol defining the interface for detecting server readiness
@MainActor
protocol ReadinessDetectorProtocol: ObservableObject {
    /// Whether the server is ready to accept connections
    var isReady: Bool { get }
    
    /// The detected URL (may include dynamically detected port)
    var detectedURL: URL? { get }
    
    /// Monitor output for ready signal and port detection
    /// - Parameter output: The terminal output to monitor
    func monitor(output: String)
    
    /// Reset the detector state
    func reset()
}

/// Monitors terminal output to detect when a server is ready and extract port information
@MainActor
class ReadinessDetector: ReadinessDetectorProtocol {
    // MARK: - Published Properties
    
    @Published private(set) var isReady: Bool = false
    @Published private(set) var detectedURL: URL?
    
    // MARK: - Private Properties
    
    private let readySignalPattern: String?
    private let portDetectionPattern: String?
    private let baseURL: String
    
    private var readySignalRegex: NSRegularExpression?
    private var portDetectionRegex: NSRegularExpression?

    /// Rolling window of recently-seen output. `monitor` is fed incremental chunks (not the whole
    /// buffer), so we keep a small tail here to catch a ready signal/port split across two chunks.
    /// Bounded so scanning is O(window), not O(total output) — fixes the O(n²) re-scan (TASK-3).
    private var scanBuffer: String = ""
    private let maxScanBuffer = 8192

    // MARK: - Initialization
    
    /// Initialize a readiness detector
    /// - Parameters:
    ///   - readySignalPattern: Optional regex pattern to detect server readiness (e.g., "Server listening on")
    ///   - portDetectionPattern: Optional regex pattern to extract port number (e.g., "port (\\d+)")
    ///   - baseURL: The base URL to use (e.g., "http://localhost:3000")
    init(
        readySignalPattern: String?,
        portDetectionPattern: String?,
        baseURL: String
    ) {
        self.readySignalPattern = readySignalPattern
        self.portDetectionPattern = portDetectionPattern
        self.baseURL = baseURL
        
        os_log(.info, log: logger, "Initializing readiness detector with base URL: %{public}@", baseURL)
        
        // Compile regex patterns if provided
        if let pattern = readySignalPattern {
            self.readySignalRegex = try? NSRegularExpression(
                pattern: pattern,
                options: [.caseInsensitive]
            )
            if readySignalRegex != nil {
                os_log(.debug, log: logger, "Ready signal pattern compiled: %{public}@", pattern)
            } else {
                os_log(.error, log: logger, "Failed to compile ready signal pattern: %{public}@", pattern)
            }
        }
        
        if let pattern = portDetectionPattern {
            self.portDetectionRegex = try? NSRegularExpression(
                pattern: pattern,
                options: []
            )
            if portDetectionRegex != nil {
                os_log(.debug, log: logger, "Port detection pattern compiled: %{public}@", pattern)
            } else {
                os_log(.error, log: logger, "Failed to compile port detection pattern: %{public}@", pattern)
            }
        }
        
        // If no ready signal pattern is configured, mark as ready immediately
        if readySignalPattern == nil || readySignalPattern?.isEmpty == true {
            os_log(.info, log: logger, "No ready signal pattern configured, marking as ready immediately")
            self.isReady = true
            self.detectedURL = URL(string: baseURL)
        }
    }
    
    // MARK: - Public Methods
    
    /// Feed an incremental chunk of output (not the full accumulated buffer). The detector keeps
    /// a bounded rolling window internally so matches spanning chunk boundaries are still found.
    func monitor(output chunk: String) {
        // Once ready, stay ready (don't flip back). Also stops scanning entirely after readiness.
        guard !isReady else { return }

        // Append to the rolling window and trim from the front to keep scanning bounded.
        scanBuffer += chunk
        if scanBuffer.count > maxScanBuffer {
            let overflow = scanBuffer.count - maxScanBuffer
            let start = scanBuffer.index(scanBuffer.startIndex, offsetBy: overflow)
            scanBuffer = String(scanBuffer[start...])
        }
        let output = scanBuffer

        // Check for ready signal
        let hasReadySignal = checkReadySignal(in: output)

        guard hasReadySignal else { return }
        
        os_log(.info, log: logger, "Ready signal detected in output")
        
        // Extract port if pattern is configured
        let detectedPort = extractPort(from: output)
        
        if let port = detectedPort {
            os_log(.info, log: logger, "Detected port: %d", port)
        } else if portDetectionPattern != nil && !portDetectionPattern!.isEmpty {
            // Port detection was configured but failed - log error and fall back to base URL
            os_log(.error, log: logger, "Port detection pattern configured but no port found, falling back to base URL")
        }
        
        // Construct final URL (falls back to base URL if port detection fails)
        let finalURL = constructURL(baseURL: baseURL, port: detectedPort)
        
        if let url = finalURL {
            os_log(.info, log: logger, "Server ready at URL: %{public}@", url.absoluteString)
            self.detectedURL = url
        } else {
            // If URL construction fails, fall back to base URL
            os_log(.error, log: logger, "URL construction failed, falling back to base URL")
            self.detectedURL = URL(string: baseURL)
        }
        
        // Update state - always mark as ready even if we had to fall back
        self.isReady = true
    }
    
    func reset() {
        os_log(.info, log: logger, "Resetting readiness detector")
        self.isReady = false
        self.detectedURL = nil
        self.scanBuffer = ""
        
        // If no ready signal pattern, mark as ready immediately
        if readySignalPattern == nil || readySignalPattern?.isEmpty == true {
            os_log(.info, log: logger, "No ready signal pattern configured, marking as ready immediately")
            self.isReady = true
            self.detectedURL = URL(string: baseURL)
        }
    }
    
    // MARK: - Private Methods
    
    /// Check if the ready signal pattern is present in the output
    /// - Parameter output: The terminal output to check
    /// - Returns: True if ready signal is detected or no pattern is configured
    private func checkReadySignal(in output: String) -> Bool {
        // If no pattern configured, consider ready immediately
        guard let regex = readySignalRegex else {
            return true
        }
        
        let range = NSRange(output.startIndex..., in: output)
        return regex.firstMatch(in: output, options: [], range: range) != nil
    }
    
    /// Extract port number from terminal output
    /// - Parameter output: The terminal output to search
    /// - Returns: The detected port number, or nil if not found
    private func extractPort(from output: String) -> Int? {
        guard let regex = portDetectionRegex else {
            return nil
        }
        
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range) else {
            return nil
        }
        
        // Extract the first capture group (port number)
        guard match.numberOfRanges > 1 else {
            return nil
        }
        
        let captureRange = match.range(at: 1)
        guard captureRange.location != NSNotFound,
              let swiftRange = Range(captureRange, in: output) else {
            return nil
        }
        
        let portString = String(output[swiftRange])
        return Int(portString)
    }
    
    /// Construct the final URL from base URL and optional port
    /// - Parameters:
    ///   - baseURL: The base URL string (e.g., "http://localhost:3000")
    ///   - port: Optional detected port number
    /// - Returns: The constructed URL, or nil if invalid
    private func constructURL(baseURL: String, port: Int?) -> URL? {
        // If no port detected, use base URL as-is
        guard let port = port else {
            return URL(string: baseURL)
        }
        
        // Parse base URL to extract protocol and host
        guard let url = URL(string: baseURL) else {
            return nil
        }
        
        // Construct new URL with detected port
        var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        components?.port = port
        
        return components?.url
    }
}
