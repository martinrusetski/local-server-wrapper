//
//  ValidationError.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation

/// Errors that can occur during configuration validation
enum ValidationError: Error, LocalizedError, Equatable {
    /// A required field is missing or empty
    case missingRequiredField(String)
    
    /// A regular expression pattern is invalid
    case invalidRegexPattern(String)
    
    /// A configuration name is already in use
    case duplicateName(String)
    
    /// A command is invalid or not executable
    case invalidCommand(String)
    
    /// A URL string is malformed
    case invalidURL(String)
    
    var errorDescription: String? {
        switch self {
        case .missingRequiredField(let field):
            return "Required field '\(field)' is missing or empty"
        case .invalidRegexPattern(let pattern):
            return "Invalid regular expression pattern: '\(pattern)'"
        case .duplicateName(let name):
            return "A configuration with the name '\(name)' already exists"
        case .invalidCommand(let command):
            return "Invalid or non-executable command: '\(command)'"
        case .invalidURL(let url):
            return "Invalid URL format: '\(url)'"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .missingRequiredField:
            return "Please provide a value for this field"
        case .invalidRegexPattern:
            return "Check your regular expression syntax and try again"
        case .duplicateName:
            return "Please choose a different name for this configuration"
        case .invalidCommand:
            return "Verify the command exists and is executable"
        case .invalidURL:
            return "Use a valid URL format like 'http://localhost:3000'"
        }
    }
}
