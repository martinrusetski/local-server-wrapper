//
//  ServerConfiguration.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation

/// Represents a server configuration with all required settings for generating an app bundle
struct ServerConfiguration: Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier for the configuration
    let id: UUID
    
    /// User-friendly name for the configuration
    var name: String
    
    /// The command to execute (e.g., "npm", "python3", "/usr/local/bin/node")
    var command: String
    
    /// Arguments to pass to the command (e.g., ["run", "dev"])
    var arguments: [String]
    
    /// The localhost URL pattern (e.g., "http://localhost:3000")
    /// If nil, port detection must be configured
    var localhostURL: String?
    
    /// Regular expression pattern to detect when the server is ready
    /// (e.g., "Server listening on", "Ready on")
    var readySignalPattern: String?
    
    /// Regular expression pattern to extract port number from terminal output
    /// (e.g., "port (\\d+)", "localhost:(\\d+)")
    /// The first capture group should contain the port number
    var portDetectionPattern: String?
    
    /// Path to a custom icon file for the generated app bundle
    /// If nil, a default icon will be used
    var customIconPath: String?
    
    /// Timestamp when the configuration was created
    var createdAt: Date
    
    /// Timestamp when the configuration was last updated
    var updatedAt: Date
    
    /// Initialize a new server configuration
    /// - Parameters:
    ///   - id: Unique identifier (defaults to a new UUID)
    ///   - name: User-friendly name for the configuration
    ///   - command: The command to execute
    ///   - arguments: Arguments to pass to the command (defaults to empty array)
    ///   - localhostURL: The localhost URL pattern (optional)
    ///   - readySignalPattern: Pattern to detect server readiness (optional)
    ///   - portDetectionPattern: Pattern to extract port number (optional)
    ///   - customIconPath: Path to custom icon file (optional)
    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        arguments: [String] = [],
        localhostURL: String? = nil,
        readySignalPattern: String? = nil,
        portDetectionPattern: String? = nil,
        customIconPath: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.localhostURL = localhostURL
        self.readySignalPattern = readySignalPattern
        self.portDetectionPattern = portDetectionPattern
        self.customIconPath = customIconPath
        self.createdAt = Date()
        self.updatedAt = Date()
    }
    
    /// Update the updatedAt timestamp to the current date
    mutating func touch() {
        self.updatedAt = Date()
    }
}

// MARK: - Codable Implementation
extension ServerConfiguration {
    enum CodingKeys: String, CodingKey {
        case id
        case name
        case command
        case arguments
        case localhostURL
        case readySignalPattern
        case portDetectionPattern
        case customIconPath
        case createdAt
        case updatedAt
    }
}
