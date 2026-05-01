//
//  ConfigurationLoaderTests.swift
//  ServerAppBundleTests
//
//  Created by Kiro
//

import XCTest
@testable import ServerAppBundle

final class ConfigurationLoaderTests: XCTestCase {
    
    // MARK: - Test Loading Valid Configuration
    
    func testLoadEmbeddedConfigurationWithFallback_ReturnsDefaultWhenFileNotFound() {
        // When loading configuration without an embedded file
        let config = ConfigurationLoader.loadEmbeddedConfigurationWithFallback()
        
        // Then it should return a default configuration
        XCTAssertEqual(config.name, "Default Server")
        XCTAssertEqual(config.command, "/bin/echo")
        XCTAssertTrue(config.arguments.contains("Configuration file not found. Please regenerate this app bundle."))
    }
    
    // MARK: - Test Error Handling
    
    func testLoadEmbeddedConfiguration_ThrowsWhenFileNotFound() {
        // When trying to load configuration without an embedded file
        // Then it should throw configurationFileNotFound error
        XCTAssertThrowsError(try ConfigurationLoader.loadEmbeddedConfiguration()) { error in
            guard let loadError = error as? ConfigurationLoadError else {
                XCTFail("Expected ConfigurationLoadError")
                return
            }
            
            switch loadError {
            case .configurationFileNotFound:
                // Expected error
                break
            default:
                XCTFail("Expected configurationFileNotFound error, got \(loadError)")
            }
        }
    }
    
    // MARK: - Test Configuration Decoding
    
    func testConfigurationDecoding_WithValidJSON() throws {
        // Given valid JSON data
        let jsonString = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "name": "Test Server",
            "command": "npm",
            "arguments": ["run", "dev"],
            "localhostURL": "http://localhost:3000",
            "readySignalPattern": "Server listening on",
            "portDetectionPattern": "port (\\\\d+)",
            "customIconPath": null,
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-01T00:00:00Z"
        }
        """
        
        let jsonData = jsonString.data(using: .utf8)!
        
        // When decoding the configuration
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let config = try decoder.decode(ServerConfiguration.self, from: jsonData)
        
        // Then all fields should be correctly decoded
        XCTAssertEqual(config.name, "Test Server")
        XCTAssertEqual(config.command, "npm")
        XCTAssertEqual(config.arguments, ["run", "dev"])
        XCTAssertEqual(config.localhostURL, "http://localhost:3000")
        XCTAssertEqual(config.readySignalPattern, "Server listening on")
        XCTAssertEqual(config.portDetectionPattern, "port (\\d+)")
        XCTAssertNil(config.customIconPath)
    }
    
    func testConfigurationDecoding_WithMissingOptionalFields() throws {
        // Given JSON with only required fields
        let jsonString = """
        {
            "id": "12345678-1234-1234-1234-123456789012",
            "name": "Minimal Server",
            "command": "python3",
            "arguments": ["-m", "http.server"],
            "createdAt": "2024-01-01T00:00:00Z",
            "updatedAt": "2024-01-01T00:00:00Z"
        }
        """
        
        let jsonData = jsonString.data(using: .utf8)!
        
        // When decoding the configuration
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let config = try decoder.decode(ServerConfiguration.self, from: jsonData)
        
        // Then required fields should be present and optional fields should be nil
        XCTAssertEqual(config.name, "Minimal Server")
        XCTAssertEqual(config.command, "python3")
        XCTAssertEqual(config.arguments, ["-m", "http.server"])
        XCTAssertNil(config.localhostURL)
        XCTAssertNil(config.readySignalPattern)
        XCTAssertNil(config.portDetectionPattern)
        XCTAssertNil(config.customIconPath)
    }
    
    func testConfigurationDecoding_WithInvalidJSON() {
        // Given invalid JSON data
        let invalidJSON = "{ invalid json }"
        let jsonData = invalidJSON.data(using: .utf8)!
        
        // When trying to decode
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        
        // Then it should throw a decoding error
        XCTAssertThrowsError(try decoder.decode(ServerConfiguration.self, from: jsonData))
    }
    
    // MARK: - Test Error Descriptions
    
    func testConfigurationLoadError_ErrorDescriptions() {
        let fileNotFoundError = ConfigurationLoadError.configurationFileNotFound
        XCTAssertNotNil(fileNotFoundError.errorDescription)
        XCTAssertTrue(fileNotFoundError.errorDescription!.contains("Configuration file not found"))
        
        let testError = NSError(domain: "test", code: 1, userInfo: nil)
        let invalidJSONError = ConfigurationLoadError.invalidJSON(testError)
        XCTAssertNotNil(invalidJSONError.errorDescription)
        XCTAssertTrue(invalidJSONError.errorDescription!.contains("Invalid JSON"))
        
        let decodingError = ConfigurationLoadError.decodingFailed(testError)
        XCTAssertNotNil(decodingError.errorDescription)
        XCTAssertTrue(decodingError.errorDescription!.contains("Failed to decode"))
    }
}
