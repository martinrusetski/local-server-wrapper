//
//  ServerConfiguration.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation

/// How the server launch command is sourced
enum ScriptSource: String, Codable {
    case command   // manual command + arguments
    case file      // picked .sh / .command file
    case inline    // typed inline script
}

/// Represents a server configuration with all required settings for generating an app bundle
struct ServerConfiguration: Codable, Identifiable, Equatable, Hashable {
    /// Unique identifier for the configuration
    let id: UUID
    
    /// User-friendly name for the configuration
    var name: String
    
    /// The command to execute (e.g., "npm", "python3", "/usr/local/bin/node", or path to script)
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
    
    /// Working directory where the server process will run
    /// If nil, the process runs from its default directory
    var workingDirectory: String?
    
    /// How the launch command is sourced
    var scriptSource: ScriptSource
    
    /// Inline script content (only used when scriptSource == .inline)
    var inlineScriptContent: String?
    
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
    ///   - workingDirectory: Directory where the server process runs (optional)
    ///   - scriptSource: How the launch command is sourced (defaults to .command)
    ///   - inlineScriptContent: Inline script content (optional, for .inline mode)
    init(
        id: UUID = UUID(),
        name: String,
        command: String,
        arguments: [String] = [],
        localhostURL: String? = nil,
        readySignalPattern: String? = nil,
        portDetectionPattern: String? = nil,
        customIconPath: String? = nil,
        workingDirectory: String? = nil,
        scriptSource: ScriptSource = .command,
        inlineScriptContent: String? = nil
    ) {
        self.id = id
        self.name = name
        self.command = command
        self.arguments = arguments
        self.localhostURL = localhostURL
        self.readySignalPattern = readySignalPattern
        self.portDetectionPattern = portDetectionPattern
        self.customIconPath = customIconPath
        self.workingDirectory = workingDirectory
        self.scriptSource = scriptSource
        self.inlineScriptContent = inlineScriptContent
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
        case workingDirectory
        case scriptSource
        case inlineScriptContent
        case createdAt
        case updatedAt
    }
    
    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        command = try container.decode(String.self, forKey: .command)
        arguments = try container.decodeIfPresent([String].self, forKey: .arguments) ?? []
        localhostURL = try container.decodeIfPresent(String.self, forKey: .localhostURL)
        readySignalPattern = try container.decodeIfPresent(String.self, forKey: .readySignalPattern)
        portDetectionPattern = try container.decodeIfPresent(String.self, forKey: .portDetectionPattern)
        customIconPath = try container.decodeIfPresent(String.self, forKey: .customIconPath)
        workingDirectory = try container.decodeIfPresent(String.self, forKey: .workingDirectory)
        scriptSource = try container.decodeIfPresent(ScriptSource.self, forKey: .scriptSource) ?? .command
        inlineScriptContent = try container.decodeIfPresent(String.self, forKey: .inlineScriptContent)
        createdAt = try container.decode(Date.self, forKey: .createdAt)
        updatedAt = try container.decode(Date.self, forKey: .updatedAt)
    }
}
