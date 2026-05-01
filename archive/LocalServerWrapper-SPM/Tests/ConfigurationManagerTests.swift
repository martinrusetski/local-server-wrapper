//
//  ConfigurationManagerTests.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import XCTest
@testable import LocalServerWrapper

final class ConfigurationManagerTests: XCTestCase {
    
    // MARK: - Mock Classes
    
    /// Mock validator for testing
    class MockValidator: ConfigurationValidatorProtocol {
        var shouldThrowError: ValidationError?
        var validateCallCount = 0
        
        func validate(_ config: ServerConfiguration) throws {
            validateCallCount += 1
            if let error = shouldThrowError {
                throw error
            }
        }
        
        func validateRegexPattern(_ pattern: String) throws {
            if let error = shouldThrowError {
                throw error
            }
        }
        
        func validateCommand(_ command: String) throws {
            if let error = shouldThrowError {
                throw error
            }
        }
        
        func validateURL(_ url: String) throws {
            if let error = shouldThrowError {
                throw error
            }
        }
    }
    
    /// Mock persistence manager for testing
    class MockPersistenceManager: PersistenceManagerProtocol {
        var configurations: [ServerConfiguration] = []
        var shouldThrowError: PersistenceError?
        var saveCallCount = 0
        var loadCallCount = 0
        
        func save(_ configurations: [ServerConfiguration]) throws {
            saveCallCount += 1
            if let error = shouldThrowError {
                throw error
            }
            self.configurations = configurations
        }
        
        func load() throws -> [ServerConfiguration] {
            loadCallCount += 1
            if let error = shouldThrowError {
                throw error
            }
            return configurations
        }
        
        func backup() throws {
            if let error = shouldThrowError {
                throw error
            }
        }
        
        func restore(from backupURL: URL) throws {
            if let error = shouldThrowError {
                throw error
            }
        }
    }
    
    // MARK: - Properties
    
    var mockValidator: MockValidator!
    var mockPersistence: MockPersistenceManager!
    var configManager: ConfigurationManager!
    
    // MARK: - Setup & Teardown
    
    override func setUp() {
        super.setUp()
        mockValidator = MockValidator()
        mockPersistence = MockPersistenceManager()
        configManager = ConfigurationManager(
            validator: mockValidator,
            persistenceManager: mockPersistence
        )
    }
    
    override func tearDown() {
        configManager = nil
        mockPersistence = nil
        mockValidator = nil
        super.tearDown()
    }
    
    // MARK: - Helper Methods
    
    func createTestConfig(name: String = "Test Server") -> ServerConfiguration {
        return ServerConfiguration(
            name: name,
            command: "npm",
            arguments: ["run", "dev"],
            localhostURL: "http://localhost:3000",
            readySignalPattern: "Server listening",
            portDetectionPattern: "port (\\d+)"
        )
    }
    
    // MARK: - Tests: createConfiguration
    
    func testCreateConfiguration_Success() throws {
        // Given
        let config = createTestConfig()
        
        // When
        try configManager.createConfiguration(config)
        
        // Then
        XCTAssertEqual(mockValidator.validateCallCount, 1, "Validator should be called once")
        XCTAssertEqual(mockPersistence.saveCallCount, 1, "Persistence should be called once")
        XCTAssertEqual(configManager.listConfigurations().count, 1, "Should have one configuration")
        XCTAssertEqual(configManager.listConfigurations().first?.id, config.id, "Configuration ID should match")
    }
    
    func testCreateConfiguration_ValidationError() {
        // Given
        let config = createTestConfig()
        mockValidator.shouldThrowError = .missingRequiredField("name")
        
        // When/Then
        XCTAssertThrowsError(try configManager.createConfiguration(config)) { error in
            XCTAssertEqual(error as? ValidationError, .missingRequiredField("name"))
        }
        
        XCTAssertEqual(configManager.listConfigurations().count, 0, "Should have no configurations")
        XCTAssertEqual(mockPersistence.saveCallCount, 0, "Persistence should not be called")
    }
    
    func testCreateConfiguration_DuplicateName() throws {
        // Given
        let config1 = createTestConfig(name: "My Server")
        let config2 = createTestConfig(name: "My Server")
        
        // When
        try configManager.createConfiguration(config1)
        
        // Then
        XCTAssertThrowsError(try configManager.createConfiguration(config2)) { error in
            XCTAssertEqual(error as? ValidationError, .duplicateName("My Server"))
        }
        
        XCTAssertEqual(configManager.listConfigurations().count, 1, "Should have only one configuration")
    }
    
    func testCreateConfiguration_PersistenceError_Rollback() throws {
        // Given
        let config = createTestConfig()
        mockPersistence.shouldThrowError = .writeFailed("Disk full")
        
        // When/Then
        XCTAssertThrowsError(try configManager.createConfiguration(config)) { error in
            XCTAssertEqual(error as? PersistenceError, .writeFailed("Disk full"))
        }
        
        XCTAssertEqual(configManager.listConfigurations().count, 0, "Should rollback and have no configurations")
    }
    
    // MARK: - Tests: updateConfiguration
    
    func testUpdateConfiguration_Success() throws {
        // Given
        var config = createTestConfig()
        try configManager.createConfiguration(config)
        
        // When
        config.name = "Updated Server"
        config.command = "python3"
        try configManager.updateConfiguration(config)
        
        // Then
        XCTAssertEqual(mockValidator.validateCallCount, 2, "Validator should be called twice")
        XCTAssertEqual(mockPersistence.saveCallCount, 2, "Persistence should be called twice")
        
        let updated = configManager.getConfiguration(id: config.id)
        XCTAssertEqual(updated?.name, "Updated Server")
        XCTAssertEqual(updated?.command, "python3")
    }
    
    func testUpdateConfiguration_NonExistent_CreatesNew() throws {
        // Given
        let config = createTestConfig()
        
        // When
        try configManager.updateConfiguration(config)
        
        // Then
        XCTAssertEqual(configManager.listConfigurations().count, 1, "Should create new configuration")
        XCTAssertEqual(configManager.getConfiguration(id: config.id)?.name, config.name)
    }
    
    func testUpdateConfiguration_DuplicateName() throws {
        // Given
        let config1 = createTestConfig(name: "Server 1")
        let config2 = createTestConfig(name: "Server 2")
        try configManager.createConfiguration(config1)
        try configManager.createConfiguration(config2)
        
        // When
        var updatedConfig2 = config2
        updatedConfig2.name = "Server 1"
        
        // Then
        XCTAssertThrowsError(try configManager.updateConfiguration(updatedConfig2)) { error in
            XCTAssertEqual(error as? ValidationError, .duplicateName("Server 1"))
        }
        
        // Verify original config2 is unchanged
        XCTAssertEqual(configManager.getConfiguration(id: config2.id)?.name, "Server 2")
    }
    
    func testUpdateConfiguration_ValidationError() throws {
        // Given
        var config = createTestConfig()
        try configManager.createConfiguration(config)
        
        mockValidator.shouldThrowError = .invalidCommand("bad command")
        config.command = "bad command"
        
        // When/Then
        XCTAssertThrowsError(try configManager.updateConfiguration(config)) { error in
            XCTAssertEqual(error as? ValidationError, .invalidCommand("bad command"))
        }
        
        // Verify original config is unchanged
        XCTAssertEqual(configManager.getConfiguration(id: config.id)?.command, "npm")
    }
    
    func testUpdateConfiguration_PersistenceError_Rollback() throws {
        // Given
        var config = createTestConfig()
        try configManager.createConfiguration(config)
        
        mockPersistence.shouldThrowError = .diskFull
        config.name = "Updated Server"
        
        // When/Then
        XCTAssertThrowsError(try configManager.updateConfiguration(config)) { error in
            XCTAssertEqual(error as? PersistenceError, .diskFull)
        }
        
        // Verify rollback - original name should be preserved
        XCTAssertEqual(configManager.getConfiguration(id: config.id)?.name, "Test Server")
    }
    
    func testUpdateConfiguration_UpdatesTimestamp() throws {
        // Given
        var config = createTestConfig()
        try configManager.createConfiguration(config)
        let originalUpdatedAt = config.updatedAt
        
        // Wait a bit to ensure timestamp changes
        Thread.sleep(forTimeInterval: 0.01)
        
        // When
        config.name = "Updated Server"
        try configManager.updateConfiguration(config)
        
        // Then
        let updated = configManager.getConfiguration(id: config.id)
        XCTAssertNotNil(updated)
        XCTAssertGreaterThan(updated!.updatedAt, originalUpdatedAt, "updatedAt should be newer")
    }
    
    // MARK: - Tests: deleteConfiguration
    
    func testDeleteConfiguration_Success() throws {
        // Given
        let config = createTestConfig()
        try configManager.createConfiguration(config)
        XCTAssertEqual(configManager.listConfigurations().count, 1)
        
        // When
        try configManager.deleteConfiguration(id: config.id)
        
        // Then
        XCTAssertEqual(configManager.listConfigurations().count, 0, "Should have no configurations")
        XCTAssertNil(configManager.getConfiguration(id: config.id), "Configuration should not exist")
        XCTAssertEqual(mockPersistence.saveCallCount, 2, "Persistence should be called twice (create + delete)")
    }
    
    func testDeleteConfiguration_NonExistent_NoError() throws {
        // Given
        let nonExistentId = UUID()
        
        // When/Then - should not throw
        try configManager.deleteConfiguration(id: nonExistentId)
        
        XCTAssertEqual(configManager.listConfigurations().count, 0)
        XCTAssertEqual(mockPersistence.saveCallCount, 0, "Persistence should not be called")
    }
    
    func testDeleteConfiguration_PersistenceError_Rollback() throws {
        // Given
        let config = createTestConfig()
        try configManager.createConfiguration(config)
        
        mockPersistence.shouldThrowError = .writeFailed("Error")
        
        // When/Then
        XCTAssertThrowsError(try configManager.deleteConfiguration(id: config.id)) { error in
            XCTAssertEqual(error as? PersistenceError, .writeFailed("Error"))
        }
        
        // Verify rollback - configuration should still exist
        XCTAssertEqual(configManager.listConfigurations().count, 1)
        XCTAssertNotNil(configManager.getConfiguration(id: config.id))
    }
    
    // MARK: - Tests: listConfigurations
    
    func testListConfigurations_Empty() {
        // When
        let configs = configManager.listConfigurations()
        
        // Then
        XCTAssertEqual(configs.count, 0, "Should have no configurations")
    }
    
    func testListConfigurations_Multiple() throws {
        // Given
        let config1 = createTestConfig(name: "Server 1")
        let config2 = createTestConfig(name: "Server 2")
        let config3 = createTestConfig(name: "Server 3")
        
        try configManager.createConfiguration(config1)
        try configManager.createConfiguration(config2)
        try configManager.createConfiguration(config3)
        
        // When
        let configs = configManager.listConfigurations()
        
        // Then
        XCTAssertEqual(configs.count, 3, "Should have three configurations")
        XCTAssertTrue(configs.contains(where: { $0.id == config1.id }))
        XCTAssertTrue(configs.contains(where: { $0.id == config2.id }))
        XCTAssertTrue(configs.contains(where: { $0.id == config3.id }))
    }
    
    // MARK: - Tests: getConfiguration
    
    func testGetConfiguration_Exists() throws {
        // Given
        let config = createTestConfig()
        try configManager.createConfiguration(config)
        
        // When
        let retrieved = configManager.getConfiguration(id: config.id)
        
        // Then
        XCTAssertNotNil(retrieved)
        XCTAssertEqual(retrieved?.id, config.id)
        XCTAssertEqual(retrieved?.name, config.name)
    }
    
    func testGetConfiguration_NotExists() {
        // Given
        let nonExistentId = UUID()
        
        // When
        let retrieved = configManager.getConfiguration(id: nonExistentId)
        
        // Then
        XCTAssertNil(retrieved, "Should return nil for non-existent configuration")
    }
    
    // MARK: - Tests: Initialization
    
    func testInitialization_LoadsExistingConfigurations() {
        // Given
        let config1 = createTestConfig(name: "Server 1")
        let config2 = createTestConfig(name: "Server 2")
        
        // Create a fresh mock persistence manager with pre-loaded configurations
        let freshMockPersistence = MockPersistenceManager()
        freshMockPersistence.configurations = [config1, config2]
        
        // When
        let manager = ConfigurationManager(
            validator: mockValidator,
            persistenceManager: freshMockPersistence
        )
        
        // Then
        XCTAssertEqual(freshMockPersistence.loadCallCount, 1, "Should load on initialization")
        XCTAssertEqual(manager.listConfigurations().count, 2, "Should have loaded configurations")
    }
    
    func testInitialization_LoadError_StartsEmpty() {
        // Given
        mockPersistence.shouldThrowError = .readFailed("Error")
        
        // When
        let manager = ConfigurationManager(
            validator: mockValidator,
            persistenceManager: mockPersistence
        )
        
        // Then
        XCTAssertEqual(manager.listConfigurations().count, 0, "Should start with empty array on load error")
    }
    
    // MARK: - Tests: Integration Scenarios
    
    func testIntegration_CreateUpdateDelete() throws {
        // Create
        var config = createTestConfig(name: "My Server")
        try configManager.createConfiguration(config)
        XCTAssertEqual(configManager.listConfigurations().count, 1)
        
        // Update
        config.command = "python3"
        config.arguments = ["manage.py", "runserver"]
        try configManager.updateConfiguration(config)
        
        let updated = configManager.getConfiguration(id: config.id)
        XCTAssertEqual(updated?.command, "python3")
        XCTAssertEqual(updated?.arguments, ["manage.py", "runserver"])
        
        // Delete
        try configManager.deleteConfiguration(id: config.id)
        XCTAssertEqual(configManager.listConfigurations().count, 0)
        XCTAssertNil(configManager.getConfiguration(id: config.id))
    }
    
    func testIntegration_MultipleConfigurations() throws {
        // Create multiple configurations
        let configs = [
            createTestConfig(name: "Node Server"),
            createTestConfig(name: "Python Server"),
            createTestConfig(name: "Ruby Server")
        ]
        
        for config in configs {
            try configManager.createConfiguration(config)
        }
        
        XCTAssertEqual(configManager.listConfigurations().count, 3)
        
        // Update one
        var updated = configs[1]
        updated.command = "python3"
        try configManager.updateConfiguration(updated)
        
        // Delete one
        try configManager.deleteConfiguration(id: configs[0].id)
        
        // Verify final state
        XCTAssertEqual(configManager.listConfigurations().count, 2)
        XCTAssertNil(configManager.getConfiguration(id: configs[0].id))
        XCTAssertNotNil(configManager.getConfiguration(id: configs[1].id))
        XCTAssertNotNil(configManager.getConfiguration(id: configs[2].id))
    }
}
