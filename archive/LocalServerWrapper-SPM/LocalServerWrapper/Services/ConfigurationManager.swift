//
//  ConfigurationManager.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation

/// Protocol defining configuration management capabilities
protocol ConfigurationManagerProtocol {
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
class ConfigurationManager: ConfigurationManagerProtocol {
    
    // MARK: - Properties
    
    /// The validator used to validate configurations
    private let validator: ConfigurationValidatorProtocol
    
    /// The persistence manager used to save and load configurations
    private let persistenceManager: PersistenceManagerProtocol
    
    /// In-memory cache of configurations
    private var configurations: [ServerConfiguration]
    
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
        } catch {
            // If loading fails, start with empty array
            // Error will be logged but not thrown to allow app to start
            print("Warning: Failed to load configurations: \(error)")
            self.configurations = []
        }
    }
    
    // MARK: - Public Methods
    
    /// Creates a new server configuration
    /// - Parameter config: The configuration to create
    /// - Throws: ValidationError if the configuration is invalid, PersistenceError if save fails
    func createConfiguration(_ config: ServerConfiguration) throws {
        // Validate the configuration
        try validator.validate(config)
        
        // Check for duplicate name
        if configurations.contains(where: { $0.name == config.name }) {
            throw ValidationError.duplicateName(config.name)
        }
        
        // Add to in-memory cache
        configurations.append(config)
        
        // Persist to disk
        do {
            try persistenceManager.save(configurations)
        } catch {
            // Rollback in-memory change if persistence fails
            configurations.removeLast()
            throw error
        }
    }
    
    /// Updates an existing server configuration
    /// - Parameter config: The configuration to update
    /// - Throws: ValidationError if the configuration is invalid, PersistenceError if save fails
    func updateConfiguration(_ config: ServerConfiguration) throws {
        // Validate the configuration
        try validator.validate(config)
        
        // Find the index of the configuration to update
        guard let index = configurations.firstIndex(where: { $0.id == config.id }) else {
            // Configuration not found - this is not an error, just add it
            try createConfiguration(config)
            return
        }
        
        // Check for duplicate name (excluding the current configuration)
        if configurations.contains(where: { $0.name == config.name && $0.id != config.id }) {
            throw ValidationError.duplicateName(config.name)
        }
        
        // Store the old configuration for rollback
        let oldConfig = configurations[index]
        
        // Update the configuration with current timestamp
        var updatedConfig = config
        updatedConfig.touch()
        
        // Update in-memory cache
        configurations[index] = updatedConfig
        
        // Persist to disk
        do {
            try persistenceManager.save(configurations)
        } catch {
            // Rollback in-memory change if persistence fails
            configurations[index] = oldConfig
            throw error
        }
    }
    
    /// Deletes a server configuration
    /// - Parameter id: The unique identifier of the configuration to delete
    /// - Throws: PersistenceError if save fails
    func deleteConfiguration(id: UUID) throws {
        // Find the index of the configuration to delete
        guard let index = configurations.firstIndex(where: { $0.id == id }) else {
            // Configuration not found - this is not an error, just return
            return
        }
        
        // Store the deleted configuration for rollback
        let deletedConfig = configurations[index]
        
        // Remove from in-memory cache
        configurations.remove(at: index)
        
        // Persist to disk
        do {
            try persistenceManager.save(configurations)
        } catch {
            // Rollback in-memory change if persistence fails
            configurations.insert(deletedConfig, at: index)
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
