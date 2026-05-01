//
//  PersistenceManager.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation
import os.log

/// Logger for persistence operations
private let logger = OSLog(subsystem: "com.localserverwrapper.configmanager", category: "persistence")

/// Protocol defining configuration persistence capabilities
protocol PersistenceManagerProtocol {
    /// Saves configurations to disk
    /// - Parameter configurations: The array of configurations to save
    /// - Throws: PersistenceError if the save operation fails
    func save(_ configurations: [ServerConfiguration]) throws
    
    /// Loads configurations from disk
    /// - Returns: Array of saved configurations
    /// - Throws: PersistenceError if the load operation fails
    func load() throws -> [ServerConfiguration]
    
    /// Creates a backup of the current configuration file
    /// - Throws: PersistenceError if the backup operation fails
    func backup() throws
    
    /// Restores configurations from a backup file
    /// - Parameter backupURL: The URL of the backup file to restore from
    /// - Throws: PersistenceError if the restore operation fails
    func restore(from backupURL: URL) throws
}

/// Manages persistence of server configurations to disk
class PersistenceManager: PersistenceManagerProtocol {
    
    // MARK: - Properties
    
    /// The URL where configurations are stored
    private let configurationsURL: URL
    
    /// The directory where backups are stored
    private let backupsDirectory: URL
    
    /// File manager for file operations
    private let fileManager: FileManager
    
    /// JSON encoder with pretty printing
    private let encoder: JSONEncoder
    
    /// JSON decoder
    private let decoder: JSONDecoder
    
    // MARK: - Initialization
    
    /// Initialize a new persistence manager
    /// - Parameter fileManager: The file manager to use (defaults to .default)
    init(fileManager: FileManager = .default) {
        self.fileManager = fileManager
        
        // Set up the configurations directory path
        let appSupportURL = fileManager.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        
        let appDirectory = appSupportURL.appendingPathComponent("LocalServerWrapper")
        self.configurationsURL = appDirectory.appendingPathComponent("configurations.json")
        self.backupsDirectory = appDirectory.appendingPathComponent("Backups")
        
        // Configure JSON encoder
        self.encoder = JSONEncoder()
        self.encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        self.encoder.dateEncodingStrategy = .iso8601
        
        // Configure JSON decoder
        self.decoder = JSONDecoder()
        self.decoder.dateDecodingStrategy = .iso8601
        
        // Ensure the directories exist
        try? createDirectoriesIfNeeded()
    }
    
    // MARK: - Public Methods
    
    /// Saves configurations to disk using atomic write
    /// - Parameter configurations: The array of configurations to save
    /// - Throws: PersistenceError if the save operation fails
    func save(_ configurations: [ServerConfiguration]) throws {
        os_log(.info, log: logger, "Saving %d configurations to disk", configurations.count)
        
        // Ensure directories exist
        try createDirectoriesIfNeeded()
        
        // Encode configurations to JSON
        let data: Data
        do {
            data = try encoder.encode(configurations)
            os_log(.debug, log: logger, "Encoded %d configurations to JSON (%d bytes)", configurations.count, data.count)
        } catch {
            os_log(.error, log: logger, "Failed to encode configurations: %{public}@", error.localizedDescription)
            throw PersistenceError.encodingFailed(error.localizedDescription)
        }
        
        // Check available disk space
        try checkDiskSpace(requiredBytes: data.count)
        
        // Write atomically to prevent corruption
        do {
            try data.write(to: configurationsURL, options: .atomic)
            os_log(.info, log: logger, "Successfully saved configurations to: %{public}@", configurationsURL.path)
        } catch let error as NSError {
            // Check for specific error types
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileWriteNoPermissionError:
                    os_log(.error, log: logger, "Permission denied writing to: %{public}@", configurationsURL.path)
                    throw PersistenceError.permissionDenied
                case NSFileWriteOutOfSpaceError:
                    os_log(.error, log: logger, "Disk full writing to: %{public}@", configurationsURL.path)
                    throw PersistenceError.diskFull
                default:
                    os_log(.error, log: logger, "Write failed: %{public}@", error.localizedDescription)
                    throw PersistenceError.writeFailed(error.localizedDescription)
                }
            }
            os_log(.error, log: logger, "Write failed: %{public}@", error.localizedDescription)
            throw PersistenceError.writeFailed(error.localizedDescription)
        }
    }
    
    /// Loads configurations from disk
    /// - Returns: Array of saved configurations
    /// - Throws: PersistenceError if the load operation fails
    func load() throws -> [ServerConfiguration] {
        os_log(.info, log: logger, "Loading configurations from disk")
        
        // Check if file exists
        guard fileManager.fileExists(atPath: configurationsURL.path) else {
            // Return empty array if file doesn't exist (first run)
            os_log(.info, log: logger, "Configuration file not found (first run), returning empty array")
            return []
        }
        
        // Read data from file
        let data: Data
        do {
            data = try Data(contentsOf: configurationsURL)
            os_log(.debug, log: logger, "Read %d bytes from: %{public}@", data.count, configurationsURL.path)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain && error.code == NSFileReadNoPermissionError {
                os_log(.error, log: logger, "Permission denied reading from: %{public}@", configurationsURL.path)
                throw PersistenceError.permissionDenied
            }
            os_log(.error, log: logger, "Read failed: %{public}@", error.localizedDescription)
            throw PersistenceError.readFailed(error.localizedDescription)
        }
        
        // Decode JSON data
        do {
            let configurations = try decoder.decode([ServerConfiguration].self, from: data)
            os_log(.info, log: logger, "Successfully loaded %d configurations", configurations.count)
            return configurations
        } catch {
            // If decoding fails, the file might be corrupted
            os_log(.error, log: logger, "Failed to decode configurations: %{public}@", error.localizedDescription)
            throw PersistenceError.decodingFailed(error.localizedDescription)
        }
    }
    
    /// Creates a backup of the current configuration file
    /// - Throws: PersistenceError if the backup operation fails
    func backup() throws {
        os_log(.info, log: logger, "Creating backup of configurations")
        
        // Check if configurations file exists
        guard fileManager.fileExists(atPath: configurationsURL.path) else {
            // Nothing to backup
            os_log(.info, log: logger, "No configuration file to backup")
            return
        }
        
        // Ensure backup directory exists
        try createDirectoriesIfNeeded()
        
        // Create backup filename with timestamp and UUID to ensure uniqueness
        let timestamp = ISO8601DateFormatter().string(from: Date())
        let safeTimestamp = timestamp.replacingOccurrences(of: ":", with: "-")
        let uniqueId = UUID().uuidString.prefix(8)
        let backupFilename = "configurations-\(safeTimestamp)-\(uniqueId).json"
        let backupURL = backupsDirectory.appendingPathComponent(backupFilename)
        
        // Copy file to backup location
        do {
            try fileManager.copyItem(at: configurationsURL, to: backupURL)
            os_log(.info, log: logger, "Successfully created backup: %{public}@", backupFilename)
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileWriteNoPermissionError:
                    os_log(.error, log: logger, "Permission denied creating backup")
                    throw PersistenceError.permissionDenied
                case NSFileWriteOutOfSpaceError:
                    os_log(.error, log: logger, "Disk full creating backup")
                    throw PersistenceError.diskFull
                default:
                    os_log(.error, log: logger, "Backup failed: %{public}@", error.localizedDescription)
                    throw PersistenceError.backupFailed(error.localizedDescription)
                }
            }
            os_log(.error, log: logger, "Backup failed: %{public}@", error.localizedDescription)
            throw PersistenceError.backupFailed(error.localizedDescription)
        }
    }
    
    /// Restores configurations from a backup file
    /// - Parameter backupURL: The URL of the backup file to restore from
    /// - Throws: PersistenceError if the restore operation fails
    func restore(from backupURL: URL) throws {
        os_log(.info, log: logger, "Restoring configurations from backup: %{public}@", backupURL.lastPathComponent)
        
        // Verify backup file exists
        guard fileManager.fileExists(atPath: backupURL.path) else {
            os_log(.error, log: logger, "Backup file not found: %{public}@", backupURL.path)
            throw PersistenceError.restoreFailed("Backup file does not exist")
        }
        
        // Verify backup file is readable and valid JSON
        let data: Data
        do {
            data = try Data(contentsOf: backupURL)
            os_log(.debug, log: logger, "Read %d bytes from backup file", data.count)
        } catch {
            os_log(.error, log: logger, "Cannot read backup file: %{public}@", error.localizedDescription)
            throw PersistenceError.restoreFailed("Cannot read backup file: \(error.localizedDescription)")
        }
        
        // Validate that the backup contains valid configuration data
        do {
            _ = try decoder.decode([ServerConfiguration].self, from: data)
            os_log(.debug, log: logger, "Backup file contains valid configuration data")
        } catch {
            os_log(.error, log: logger, "Backup file contains invalid data: %{public}@", error.localizedDescription)
            throw PersistenceError.restoreFailed("Backup file contains invalid data: \(error.localizedDescription)")
        }
        
        // Create a backup of current file before restoring (if it exists)
        if fileManager.fileExists(atPath: configurationsURL.path) {
            os_log(.info, log: logger, "Creating backup of current configuration before restore")
            try? backup()
        }
        
        // Ensure directories exist
        try createDirectoriesIfNeeded()
        
        // Copy backup file to configurations location
        do {
            // Remove existing file if present
            if fileManager.fileExists(atPath: configurationsURL.path) {
                try fileManager.removeItem(at: configurationsURL)
            }
            
            // Copy backup to configurations location
            try fileManager.copyItem(at: backupURL, to: configurationsURL)
            os_log(.info, log: logger, "Successfully restored configurations from backup")
        } catch let error as NSError {
            if error.domain == NSCocoaErrorDomain {
                switch error.code {
                case NSFileWriteNoPermissionError:
                    os_log(.error, log: logger, "Permission denied restoring backup")
                    throw PersistenceError.permissionDenied
                case NSFileWriteOutOfSpaceError:
                    os_log(.error, log: logger, "Disk full restoring backup")
                    throw PersistenceError.diskFull
                default:
                    os_log(.error, log: logger, "Restore failed: %{public}@", error.localizedDescription)
                    throw PersistenceError.restoreFailed(error.localizedDescription)
                }
            }
            os_log(.error, log: logger, "Restore failed: %{public}@", error.localizedDescription)
            throw PersistenceError.restoreFailed(error.localizedDescription)
        }
    }
    
    // MARK: - Private Helper Methods
    
    /// Creates necessary directories if they don't exist
    /// - Throws: PersistenceError if directory creation fails
    private func createDirectoriesIfNeeded() throws {
        let directories = [
            configurationsURL.deletingLastPathComponent(),
            backupsDirectory
        ]
        
        for directory in directories {
            if !fileManager.fileExists(atPath: directory.path) {
                do {
                    try fileManager.createDirectory(
                        at: directory,
                        withIntermediateDirectories: true,
                        attributes: nil
                    )
                } catch let error as NSError {
                    if error.domain == NSCocoaErrorDomain && error.code == NSFileWriteNoPermissionError {
                        throw PersistenceError.permissionDenied
                    }
                    throw PersistenceError.writeFailed("Failed to create directory: \(error.localizedDescription)")
                }
            }
        }
    }
    
    /// Checks if there is sufficient disk space for the operation
    /// - Parameter requiredBytes: The number of bytes required
    /// - Throws: PersistenceError.diskFull if insufficient space
    private func checkDiskSpace(requiredBytes: Int) throws {
        let directoryURL = configurationsURL.deletingLastPathComponent()
        
        do {
            let values = try directoryURL.resourceValues(forKeys: [.volumeAvailableCapacityForImportantUsageKey])
            
            if let availableCapacity = values.volumeAvailableCapacityForImportantUsage {
                // Require at least 10MB free space or 2x the file size, whichever is larger
                let minimumRequired = max(requiredBytes * 2, 10_000_000)
                
                if availableCapacity < minimumRequired {
                    throw PersistenceError.diskFull
                }
            }
        } catch is PersistenceError {
            throw PersistenceError.diskFull
        } catch {
            // If we can't determine disk space, proceed anyway
            // This might happen on some file systems
        }
    }
}
