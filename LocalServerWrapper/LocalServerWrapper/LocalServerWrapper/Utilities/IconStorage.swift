//
//  IconStorage.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation

/// Manages persistent icon storage in the app's Application Support directory
enum IconStorage {
    
    // MARK: - Directory
    
    /// The directory where managed icons are stored
    static var iconsDirectory: URL {
        let appSupport = FileManager.default.urls(
            for: .applicationSupportDirectory,
            in: .userDomainMask
        ).first!
        return appSupport.appendingPathComponent("LocalServerWrapper/Icons")
    }
    
    // MARK: - Public Methods
    
    /// Copy an icon file into managed storage for a configuration
    /// - Parameters:
    ///   - sourcePath: The path to the source icon file
    ///   - configurationId: The ID of the configuration
    /// - Returns: The path of the copied icon in managed storage, or nil on failure
    static func storeIcon(from sourcePath: String, for configurationId: UUID) -> String? {
        guard !sourcePath.isEmpty else { return nil }
        
        let sourceURL = URL(fileURLWithPath: sourcePath)
        guard FileManager.default.fileExists(atPath: sourceURL.path) else {
            print("⚠️ IconStorage: source file not found at \(sourcePath)")
            return nil
        }
        
        let fileManager = FileManager.default
        
        // Create the icons directory if needed
        do {
            try fileManager.createDirectory(at: iconsDirectory, withIntermediateDirectories: true)
        } catch {
            print("⚠️ IconStorage: failed to create icons directory: \(error)")
            return nil
        }
        
        // Create a per-configuration subdirectory
        let configDir = iconsDirectory.appendingPathComponent(configurationId.uuidString)
        do {
            try fileManager.createDirectory(at: configDir, withIntermediateDirectories: true)
        } catch {
            print("⚠️ IconStorage: failed to create config icon directory: \(error)")
            return nil
        }
        
        // Preserve the original file extension
        let ext = sourceURL.pathExtension.isEmpty ? "png" : sourceURL.pathExtension.lowercased()
        let destURL = configDir.appendingPathComponent("icon.\(ext)")
        
        // Remove any existing icon at destination
        try? fileManager.removeItem(at: destURL)
        
        // Copy the file
        do {
            try fileManager.copyItem(at: sourceURL, to: destURL)
            return destURL.path
        } catch {
            print("⚠️ IconStorage: failed to copy icon: \(error)")
            return nil
        }
    }
    
    /// Remove managed icon storage for a configuration
    /// - Parameter configurationId: The ID of the configuration
    static func removeIcon(for configurationId: UUID) {
        let configDir = iconsDirectory.appendingPathComponent(configurationId.uuidString)
        try? FileManager.default.removeItem(at: configDir)
    }
    
    /// Check whether the given path is already inside the managed icons directory
    /// - Parameter path: The icon path to check
    /// - Returns: True if the path is already managed
    static func isManagedPath(_ path: String) -> Bool {
        return path.hasPrefix(iconsDirectory.path)
    }
}
