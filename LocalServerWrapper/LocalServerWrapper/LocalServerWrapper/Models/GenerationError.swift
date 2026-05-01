//
//  GenerationError.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation

/// Errors that can occur during app bundle generation
enum GenerationError: Error, LocalizedError, Equatable {
    /// The specified output path is invalid or inaccessible
    case invalidOutputPath
    
    /// Failed to create the app bundle structure
    case bundleCreationFailed(String)
    
    /// Failed to copy resources to the bundle
    case resourceCopyFailed(String)
    
    /// Failed to sign the app bundle
    case signingFailed(String)
    
    /// Failed to embed configuration data into the bundle
    case configurationEmbedFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .invalidOutputPath:
            return "The output path is invalid or inaccessible"
        case .bundleCreationFailed(let details):
            return "Failed to create app bundle: \(details)"
        case .resourceCopyFailed(let details):
            return "Failed to copy resources: \(details)"
        case .signingFailed(let details):
            return "Failed to sign app bundle: \(details)"
        case .configurationEmbedFailed(let details):
            return "Failed to embed configuration: \(details)"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .invalidOutputPath:
            return "Choose a valid directory where you have write permissions"
        case .bundleCreationFailed:
            return "Ensure you have sufficient disk space and permissions"
        case .resourceCopyFailed:
            return "Check that all required resources are available"
        case .signingFailed:
            return "Verify your code signing configuration"
        case .configurationEmbedFailed:
            return "Ensure the configuration data is valid"
        }
    }
}
