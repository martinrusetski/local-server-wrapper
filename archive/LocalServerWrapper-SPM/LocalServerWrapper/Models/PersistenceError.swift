//
//  PersistenceError.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation

/// Errors that can occur during configuration persistence operations
enum PersistenceError: Error, LocalizedError, Equatable {
    /// Failed to read from disk
    case readFailed(String)
    
    /// Failed to write to disk
    case writeFailed(String)
    
    /// Failed to decode JSON data
    case decodingFailed(String)
    
    /// Failed to encode data to JSON
    case encodingFailed(String)
    
    /// The configuration file is corrupted
    case corruptedData
    
    /// Failed to create backup
    case backupFailed(String)
    
    /// Failed to restore from backup
    case restoreFailed(String)
    
    /// Insufficient permissions to access the file
    case permissionDenied
    
    /// Insufficient disk space
    case diskFull
    
    var errorDescription: String? {
        switch self {
        case .readFailed(let details):
            return "Failed to read configuration file: \(details)"
        case .writeFailed(let details):
            return "Failed to write configuration file: \(details)"
        case .decodingFailed(let details):
            return "Failed to decode configuration data: \(details)"
        case .encodingFailed(let details):
            return "Failed to encode configuration data: \(details)"
        case .corruptedData:
            return "The configuration file is corrupted or invalid"
        case .backupFailed(let details):
            return "Failed to create backup: \(details)"
        case .restoreFailed(let details):
            return "Failed to restore from backup: \(details)"
        case .permissionDenied:
            return "Permission denied to access configuration file"
        case .diskFull:
            return "Insufficient disk space to save configuration"
        }
    }
    
    var recoverySuggestion: String? {
        switch self {
        case .readFailed, .decodingFailed, .corruptedData:
            return "Try restoring from a backup or creating a new configuration"
        case .writeFailed, .encodingFailed:
            return "Check your disk space and file permissions"
        case .backupFailed:
            return "Ensure you have sufficient disk space"
        case .restoreFailed:
            return "Verify the backup file is valid and accessible"
        case .permissionDenied:
            return "Check file permissions in ~/Library/Application Support/LocalServerWrapper"
        case .diskFull:
            return "Free up disk space and try again"
        }
    }
}
