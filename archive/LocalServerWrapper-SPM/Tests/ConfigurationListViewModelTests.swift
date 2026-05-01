//
//  ConfigurationListViewModelTests.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import XCTest
@testable import LocalServerWrapper

@MainActor
final class ConfigurationListViewModelTests: XCTestCase {
    
    var viewModel: ConfigurationListViewModel!
    var mockManager: MockConfigurationManager!
    
    override func setUp() async throws {
        mockManager = MockConfigurationManager()
        viewModel = ConfigurationListViewModel(configurationManager: mockManager)
    }
    
    override func tearDown() async throws {
        viewModel = nil
        mockManager = nil
    }
    
    // MARK: - Initialization Tests
    
    func testInitialization() {
        // Given: A view model is initialized
        // Then: It should load configurations from the manager
        XCTAssertEqual(viewModel.configurations.count, 0)
    }
    
    func testInitializationWithExistingConfigurations() {
        // Given: The manager has some configurations
        let config1 = ServerConfiguration(name: "Test 1", command: "npm")
        let config2 = ServerConfiguration(name: "Test 2", command: "python3")
        mockManager.configurations = [config1, config2]
        
        // When: A new view model is created
        let newViewModel = ConfigurationListViewModel(configurationManager: mockManager)
        
        // Then: It should load all configurations
        XCTAssertEqual(newViewModel.configurations.count, 2)
        XCTAssertEqual(newViewModel.configurations[0].name, "Test 1")
        XCTAssertEqual(newViewModel.configurations[1].name, "Test 2")
    }
    
    // MARK: - Refresh Tests
    
    func testRefresh() {
        // Given: The manager has configurations
        let config = ServerConfiguration(name: "Test", command: "npm")
        mockManager.configurations = [config]
        
        // When: Refresh is called
        viewModel.refresh()
        
        // Then: Configurations should be updated
        XCTAssertEqual(viewModel.configurations.count, 1)
        XCTAssertEqual(viewModel.configurations[0].name, "Test")
    }
    
    // MARK: - Delete Tests
    
    func testDeleteConfiguration() {
        // Given: A configuration exists
        let config = ServerConfiguration(name: "Test", command: "npm")
        mockManager.configurations = [config]
        viewModel.refresh()
        
        // When: Delete is called
        viewModel.deleteConfiguration(config)
        
        // Then: The configuration should be removed
        XCTAssertEqual(viewModel.configurations.count, 0)
        XCTAssertTrue(viewModel.showingSuccess)
        XCTAssertNotNil(viewModel.successMessage)
        XCTAssertTrue(viewModel.successMessage!.contains("Test"))
    }
    
    func testDeleteConfigurationError() {
        // Given: The manager will throw an error
        let config = ServerConfiguration(name: "Test", command: "npm")
        mockManager.shouldThrowError = true
        
        // When: Delete is called
        viewModel.deleteConfiguration(config)
        
        // Then: An error should be shown
        XCTAssertTrue(viewModel.showingError)
        XCTAssertNotNil(viewModel.errorMessage)
    }
    
    // MARK: - Generate App Bundle Tests
    
    func testGenerateAppBundle() {
        // Given: A configuration exists
        let config = ServerConfiguration(name: "Test", command: "npm")
        
        // When: Generate is called
        // Note: This will open a file picker dialog, which requires user interaction
        // We can't fully test this in a unit test, but we can verify it doesn't crash
        viewModel.generateAppBundle(for: config)
        
        // Then: The method should execute without crashing
        // The actual file picker interaction and bundle generation would be tested in UI tests
        XCTAssertFalse(viewModel.isGenerating) // Should not be generating yet (waiting for file picker)
    }
}

// MARK: - Mock Configuration Manager

class MockConfigurationManager: ConfigurationManagerProtocol {
    var configurations: [ServerConfiguration] = []
    var shouldThrowError = false
    
    func createConfiguration(_ config: ServerConfiguration) throws {
        if shouldThrowError {
            throw PersistenceError.writeFailed("Mock error")
        }
        configurations.append(config)
    }
    
    func updateConfiguration(_ config: ServerConfiguration) throws {
        if shouldThrowError {
            throw PersistenceError.writeFailed("Mock error")
        }
        if let index = configurations.firstIndex(where: { $0.id == config.id }) {
            configurations[index] = config
        }
    }
    
    func deleteConfiguration(id: UUID) throws {
        if shouldThrowError {
            throw PersistenceError.writeFailed("Mock error")
        }
        configurations.removeAll { $0.id == id }
    }
    
    func listConfigurations() -> [ServerConfiguration] {
        return configurations
    }
    
    func getConfiguration(id: UUID) -> ServerConfiguration? {
        return configurations.first { $0.id == id }
    }
}
