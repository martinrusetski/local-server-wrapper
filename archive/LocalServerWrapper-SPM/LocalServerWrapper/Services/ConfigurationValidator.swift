//
//  ConfigurationValidator.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation

/// Protocol defining configuration validation capabilities
protocol ConfigurationValidatorProtocol {
    /// Validates a complete server configuration
    /// - Parameter config: The configuration to validate
    /// - Throws: ValidationError if the configuration is invalid
    func validate(_ config: ServerConfiguration) throws
    
    /// Validates a regular expression pattern
    /// - Parameter pattern: The regex pattern to validate
    /// - Throws: ValidationError if the pattern is invalid
    func validateRegexPattern(_ pattern: String) throws
    
    /// Validates a command string
    /// - Parameter command: The command to validate
    /// - Throws: ValidationError if the command is invalid
    func validateCommand(_ command: String) throws
    
    /// Validates a URL string
    /// - Parameter url: The URL string to validate
    /// - Throws: ValidationError if the URL is invalid
    func validateURL(_ url: String) throws
}

/// Validates server configurations to ensure all required fields are present and valid
class ConfigurationValidator: ConfigurationValidatorProtocol {
    
    /// Validates a complete server configuration
    /// - Parameter config: The configuration to validate
    /// - Throws: ValidationError if any validation fails
    func validate(_ config: ServerConfiguration) throws {
        // Validate required field: name
        if config.name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.missingRequiredField("name")
        }
        
        // Validate required field: command
        if config.command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            throw ValidationError.missingRequiredField("command")
        }
        
        // Validate command is valid
        try validateCommand(config.command)
        
        // Validate optional regex patterns if provided
        if let readySignal = config.readySignalPattern, !readySignal.isEmpty {
            try validateRegexPattern(readySignal)
        }
        
        if let portPattern = config.portDetectionPattern, !portPattern.isEmpty {
            try validateRegexPattern(portPattern)
        }
        
        // Validate localhost URL if provided
        if let url = config.localhostURL, !url.isEmpty {
            try validateURL(url)
        }
        
        // Validate custom icon path if provided
        if let iconPath = config.customIconPath, !iconPath.isEmpty {
            try validateIconPath(iconPath)
        }
    }
    
    /// Validates a regular expression pattern
    /// - Parameter pattern: The regex pattern to validate
    /// - Throws: ValidationError.invalidRegexPattern if the pattern is invalid
    func validateRegexPattern(_ pattern: String) throws {
        do {
            _ = try NSRegularExpression(pattern: pattern, options: [])
        } catch {
            throw ValidationError.invalidRegexPattern(pattern)
        }
    }
    
    /// Validates a command string
    /// - Parameter command: The command to validate
    /// - Throws: ValidationError.invalidCommand if the command is invalid
    func validateCommand(_ command: String) throws {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if command is empty
        if trimmedCommand.isEmpty {
            throw ValidationError.invalidCommand(command)
        }
        
        // Extract the executable path (first component before any arguments)
        let components = trimmedCommand.split(separator: " ", maxSplits: 1)
        guard let executable = components.first else {
            throw ValidationError.invalidCommand(command)
        }
        
        let executableString = String(executable)
        
        // Check if it's an absolute path
        if executableString.hasPrefix("/") {
            // For absolute paths, verify the file exists and is executable
            let fileManager = FileManager.default
            
            // Check if file exists
            guard fileManager.fileExists(atPath: executableString) else {
                throw ValidationError.invalidCommand(command)
            }
            
            // Check if file is executable
            guard fileManager.isExecutableFile(atPath: executableString) else {
                throw ValidationError.invalidCommand(command)
            }
        } else {
            // For relative commands (like "npm", "python3"), we accept them
            // as they will be resolved via PATH at runtime
            // Just ensure they don't contain invalid characters
            let invalidCharacters = CharacterSet(charactersIn: "\0\n\r")
            if executableString.rangeOfCharacter(from: invalidCharacters) != nil {
                throw ValidationError.invalidCommand(command)
            }
        }
    }
    
    /// Validates a URL string
    /// - Parameter url: The URL string to validate
    /// - Throws: ValidationError.invalidURL if the URL is malformed
    func validateURL(_ url: String) throws {
        let trimmedURL = url.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if URL is empty
        if trimmedURL.isEmpty {
            throw ValidationError.invalidURL(url)
        }
        
        // Try to create a URL object
        guard let urlObject = URL(string: trimmedURL) else {
            throw ValidationError.invalidURL(url)
        }
        
        // Verify URL has a scheme (http, https, etc.)
        guard urlObject.scheme != nil else {
            throw ValidationError.invalidURL(url)
        }
        
        // For localhost URLs, verify the host is localhost or 127.0.0.1
        if let host = urlObject.host {
            let validHosts = ["localhost", "127.0.0.1", "::1", "0.0.0.0"]
            if !validHosts.contains(host.lowercased()) {
                // Allow any host for flexibility, but localhost is expected
                // This is a warning case, not an error
            }
        }
    }
    
    /// Validates an icon file path
    /// - Parameter path: The file path to validate
    /// - Throws: ValidationError.invalidCommand if the path is invalid or file doesn't exist
    private func validateIconPath(_ path: String) throws {
        let trimmedPath = path.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Check if path is empty
        if trimmedPath.isEmpty {
            return // Empty path is acceptable (will use default icon)
        }
        
        let fileManager = FileManager.default
        
        // Expand tilde in path
        let expandedPath = NSString(string: trimmedPath).expandingTildeInPath
        
        // Check if file exists
        guard fileManager.fileExists(atPath: expandedPath) else {
            throw ValidationError.invalidCommand("Icon file does not exist: \(path)")
        }
        
        // Check if it's a regular file (not a directory)
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory)
        
        if isDirectory.boolValue {
            throw ValidationError.invalidCommand("Icon path is a directory, not a file: \(path)")
        }
        
        // Optionally validate file extension (common image formats)
        let validExtensions = ["png", "jpg", "jpeg", "icns", "ico", "gif", "tiff", "tif"]
        let pathExtension = NSString(string: expandedPath).pathExtension.lowercased()
        
        if !validExtensions.contains(pathExtension) {
            throw ValidationError.invalidCommand("Icon file must be an image (png, jpg, icns, etc.): \(path)")
        }
    }
}
