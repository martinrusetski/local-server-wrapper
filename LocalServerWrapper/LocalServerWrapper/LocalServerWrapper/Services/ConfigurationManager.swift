//
//  ConfigurationManager.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation
import os.log
import Combine

/// Logger for configuration management operations
private let logger = OSLog(subsystem: "com.localserverwrapper.configmanager", category: "configuration")

/// Protocol defining configuration management capabilities
protocol ConfigurationManagerProtocol {
    var loadError: String? { get }

    /// Creates a new server configuration
    /// - Parameter config: The configuration to create
    /// - Throws: ValidationError if the configuration is invalid, PersistenceError if save fails
    func createConfiguration(_ config: ServerConfiguration) throws
    
    /// Updates an existing server configuration
    /// - Parameter config: The configuration to update
    /// - Throws: ValidationError if the configuration is invalid, PersistenceError if save fails
    func updateConfiguration(_ config: ServerConfiguration) throws
    
    /// Deletes a server configuration
    /// - Parameter id: The unique identifier of the configuration to delete
    /// - Throws: PersistenceError if save fails
    func deleteConfiguration(id: UUID) throws
    
    /// Lists all server configurations
    /// - Returns: Array of all configurations
    func listConfigurations() -> [ServerConfiguration]
    
    /// Gets a specific configuration by ID
    /// - Parameter id: The unique identifier of the configuration
    /// - Returns: The configuration if found, nil otherwise
    func getConfiguration(id: UUID) -> ServerConfiguration?
}

/// Manages CRUD operations for server configurations
class ConfigurationManager: ConfigurationManagerProtocol, ObservableObject {
    
    // MARK: - Properties
    
    /// The validator used to validate configurations
    private let validator: ConfigurationValidatorProtocol
    
    /// The persistence manager used to save and load configurations
    private let persistenceManager: PersistenceManagerProtocol
    
    /// In-memory cache of configurations
    private var configurations: [ServerConfiguration]
    private(set) var loadError: String?
    
    // MARK: - Initialization
    
    /// Initialize a new configuration manager
    /// - Parameters:
    ///   - validator: The validator to use (defaults to ConfigurationValidator)
    ///   - persistenceManager: The persistence manager to use (defaults to PersistenceManager)
    init(
        validator: ConfigurationValidatorProtocol = ConfigurationValidator(),
        persistenceManager: PersistenceManagerProtocol = PersistenceManager()
    ) {
        self.validator = validator
        self.persistenceManager = persistenceManager
        
        // Load existing configurations from disk
        do {
            self.configurations = try persistenceManager.load()
            os_log(.info, log: logger, "Loaded %d configurations from disk", self.configurations.count)
        } catch {
            // Preserve the unreadable library and prevent subsequent writes.
            os_log(.error, log: logger, "Failed to load configurations: %{public}@", error.localizedDescription)
            print("Warning: Failed to load configurations: \(error)")
            self.configurations = []
            self.loadError = "Your saved app library could not be opened. No data has been changed. Restore configurations.json from a backup or correct its permissions, then reopen the manager.\n\n\(error.localizedDescription)"
        }
    }
    
    // MARK: - Public Methods
    
    /// Creates a new server configuration
    /// - Parameter config: The configuration to create
    /// - Throws: ValidationError if the configuration is invalid, PersistenceError if save fails
    func createConfiguration(_ config: ServerConfiguration) throws {
        if let loadError { throw PersistenceError.readFailed(loadError) }
        os_log(.info, log: logger, "Creating configuration: %{public}@", config.name)
        
        // Validate the configuration
        do {
            try validator.validate(config)
            os_log(.debug, log: logger, "Configuration validation passed for: %{public}@", config.name)
        } catch {
            os_log(.error, log: logger, "Validation failed for configuration '%{public}@': %{public}@", config.name, error.localizedDescription)
            throw error
        }
        
        // Check for duplicate name
        if configurations.contains(where: { $0.name == config.name }) {
            os_log(.error, log: logger, "Duplicate configuration name: %{public}@", config.name)
            throw ValidationError.duplicateName(config.name)
        }
        
        // Add to in-memory cache
        configurations.append(config)
        os_log(.debug, log: logger, "Added configuration to cache: %{public}@", config.name)
        
        // Persist to disk
        do {
            try persistenceManager.save(configurations)
            os_log(.info, log: logger, "Successfully created configuration: %{public}@", config.name)
        } catch {
            // Rollback in-memory change if persistence fails
            configurations.removeLast()
            os_log(.error, log: logger, "Failed to persist configuration '%{public}@', rolled back: %{public}@", config.name, error.localizedDescription)
            throw error
        }
    }
    
    /// Updates an existing server configuration
    /// - Parameter config: The configuration to update
    /// - Throws: ValidationError if the configuration is invalid, PersistenceError if save fails
    func updateConfiguration(_ config: ServerConfiguration) throws {
        if let loadError { throw PersistenceError.readFailed(loadError) }
        os_log(.info, log: logger, "Updating configuration: %{public}@", config.name)
        
        // Validate the configuration
        do {
            try validator.validate(config)
            os_log(.debug, log: logger, "Configuration validation passed for: %{public}@", config.name)
        } catch {
            os_log(.error, log: logger, "Validation failed for configuration '%{public}@': %{public}@", config.name, error.localizedDescription)
            throw error
        }
        
        // Find the index of the configuration to update
        guard let index = configurations.firstIndex(where: { $0.id == config.id }) else {
            // Configuration not found - this is not an error, just add it
            os_log(.info, log: logger, "Configuration not found, creating new: %{public}@", config.name)
            try createConfiguration(config)
            return
        }
        
        // Check for duplicate name (excluding the current configuration)
        if configurations.contains(where: { $0.name == config.name && $0.id != config.id }) {
            os_log(.error, log: logger, "Duplicate configuration name: %{public}@", config.name)
            throw ValidationError.duplicateName(config.name)
        }
        
        // Store the old configuration for rollback
        let oldConfig = configurations[index]
        
        // Update the configuration with current timestamp
        var updatedConfig = config
        updatedConfig.touch()
        
        // Update in-memory cache
        configurations[index] = updatedConfig
        os_log(.debug, log: logger, "Updated configuration in cache: %{public}@", config.name)
        
        // Persist to disk
        do {
            try persistenceManager.save(configurations)
            os_log(.info, log: logger, "Successfully updated configuration: %{public}@", config.name)
        } catch {
            // Rollback in-memory change if persistence fails
            configurations[index] = oldConfig
            os_log(.error, log: logger, "Failed to persist configuration '%{public}@', rolled back: %{public}@", config.name, error.localizedDescription)
            throw error
        }
    }
    
    /// Deletes a server configuration
    /// - Parameter id: The unique identifier of the configuration to delete
    /// - Throws: PersistenceError if save fails
    func deleteConfiguration(id: UUID) throws {
        if let loadError { throw PersistenceError.readFailed(loadError) }
        os_log(.info, log: logger, "Deleting configuration with ID: %{public}@", id.uuidString)
        
        // Find the index of the configuration to delete
        guard let index = configurations.firstIndex(where: { $0.id == id }) else {
            // Configuration not found - this is not an error, just return
            os_log(.info, log: logger, "Configuration not found for deletion: %{public}@", id.uuidString)
            return
        }
        
        // Store the deleted configuration for rollback
        let deletedConfig = configurations[index]
        let configName = deletedConfig.name
        
        // Remove from in-memory cache
        configurations.remove(at: index)
        os_log(.debug, log: logger, "Removed configuration from cache: %{public}@", configName)
        
        // Persist to disk
        do {
            try persistenceManager.save(configurations)
            os_log(.info, log: logger, "Successfully deleted configuration: %{public}@", configName)
        } catch {
            // Rollback in-memory change if persistence fails
            configurations.insert(deletedConfig, at: index)
            os_log(.error, log: logger, "Failed to persist deletion of '%{public}@', rolled back: %{public}@", configName, error.localizedDescription)
            throw error
        }
    }
    
    /// Lists all server configurations
    /// - Returns: Array of all configurations
    func listConfigurations() -> [ServerConfiguration] {
        return configurations
    }
    
    /// Gets a specific configuration by ID
    /// - Parameter id: The unique identifier of the configuration
    /// - Returns: The configuration if found, nil otherwise
    func getConfiguration(id: UUID) -> ServerConfiguration? {
        return configurations.first(where: { $0.id == id })
    }
}
