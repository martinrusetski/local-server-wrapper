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
    private let mode: URLDetectionMode

    private var readySignalRegex: NSRegularExpression?
    private var portDetectionRegex: NSRegularExpression?

    /// Built-in matcher for a loopback URL printed by the server (e.g. "Local: http://localhost:5173/").
    /// This is what lets automatic mode work without the user authoring a port-detection regex.
    private static let genericURLRegex = try? NSRegularExpression(
        pattern: #"(https?)://(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]):(\d+)"#,
        options: [.caseInsensitive]
    )

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
    ///   - mode: How the URL is resolved. `.fixed` (default) preserves the legacy behaviour of
    ///     becoming ready immediately when no ready-signal pattern is set. `.automatic` instead
    ///     waits for a real signal — an observed listening port (see `noteListeningPort`), a URL in
    ///     the output, or the ready pattern — so the browser only loads once the server is actually up.
    init(
        readySignalPattern: String?,
        portDetectionPattern: String?,
        baseURL: String,
        mode: URLDetectionMode = .fixed
    ) {
        self.readySignalPattern = readySignalPattern
        self.portDetectionPattern = portDetectionPattern
        self.baseURL = baseURL
        self.mode = mode

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
        
        // In fixed mode, with no ready-signal pattern, become ready immediately (legacy behaviour).
        // In automatic mode we deliberately wait for a real signal so we don't load the browser at a
        // dead port before the server is listening.
        if mode == .fixed, readySignalPattern == nil || readySignalPattern?.isEmpty == true {
            os_log(.info, log: logger, "No ready signal pattern configured (fixed mode), marking as ready immediately")
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

        if readySignalRegex != nil {
            // An explicit ready-signal pattern gates readiness in both modes.
            guard checkReadySignal(in: output) else { return }
            os_log(.info, log: logger, "Ready signal detected in output")
            markReady(resolveURL(from: output))
            return
        }

        // No explicit ready-signal pattern.
        switch mode {
        case .fixed:
            // Fixed mode with no pattern became ready in init; nothing to do here.
            return
        case .automatic:
            // Wait for a loopback URL to appear in the output. (OS port observation, via
            // noteListeningPort, is the primary signal in this mode and runs in parallel.)
            guard let url = extractGenericURL(from: output) else { return }
            os_log(.info, log: logger, "Detected server URL in output: %{public}@", url.absoluteString)
            markReady(url)
        }
    }

    /// Record that the server's process tree was observed listening on `port` (OS-level detection,
    /// automatic mode). First signal wins, matching output-based readiness.
    func noteListeningPort(_ port: Int) {
        guard !isReady else { return }
        os_log(.info, log: logger, "Observed listening port from OS: %d", port)
        markReady(constructURL(baseURL: baseURL, port: port))
    }

    /// Mark ready, defaulting to the base URL if no better URL was resolved.
    private func markReady(_ url: URL?) {
        let finalURL = url ?? URL(string: baseURL)
        if let finalURL {
            os_log(.info, log: logger, "Server ready at URL: %{public}@", finalURL.absoluteString)
        }
        self.detectedURL = finalURL
        self.isReady = true
    }

    /// Resolve the URL from output when an explicit ready signal has fired: prefer an explicit
    /// port-detection pattern, then a generic URL scan (only if no explicit pattern), else the base URL.
    private func resolveURL(from output: String) -> URL? {
        if let port = extractPort(from: output) {
            os_log(.info, log: logger, "Detected port: %d", port)
            return constructURL(baseURL: baseURL, port: port)
        }
        if portDetectionRegex == nil, let url = extractGenericURL(from: output) {
            return url
        }
        if portDetectionPattern != nil && !portDetectionPattern!.isEmpty {
            os_log(.error, log: logger, "Port detection pattern configured but no port found, falling back to base URL")
        }
        return URL(string: baseURL)
    }
    
    func reset() {
        os_log(.info, log: logger, "Resetting readiness detector")
        self.isReady = false
        self.detectedURL = nil
        self.scanBuffer = ""

        // Mirror init: only fixed mode becomes ready immediately when no ready pattern is configured.
        if mode == .fixed, readySignalPattern == nil || readySignalPattern?.isEmpty == true {
            os_log(.info, log: logger, "No ready signal pattern configured (fixed mode), marking as ready immediately")
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

    /// Extract a loopback URL printed in the output using the built-in generic matcher. The host is
    /// normalized to `localhost` (so the web view connects over loopback even if the server reported
    /// `0.0.0.0`), while the scheme and port come from what was printed.
    private func extractGenericURL(from output: String) -> URL? {
        guard let regex = Self.genericURLRegex else { return nil }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range),
              match.numberOfRanges > 2,
              let schemeRange = Range(match.range(at: 1), in: output),
              let portRange = Range(match.range(at: 2), in: output),
              let port = Int(output[portRange]) else {
            return nil
        }
        let scheme = output[schemeRange].lowercased()
        return URL(string: "\(scheme)://localhost:\(port)")
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
