//
//  AppBundleGeneratorTests.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import XCTest
@testable import LocalServerWrapper

final class AppBundleGeneratorTests: XCTestCase {
    
    var generator: AppBundleGenerator!
    var tempDirectory: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        generator = AppBundleGenerator()
        
        // Create a temporary directory for test output
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up temporary directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        generator = nil
        try await super.tearDown()
    }
    
    // MARK: - Bundle Structure Tests
    
    func testGenerateCreatesValidBundleStructure() async throws {
        // Given: A valid server configuration
        let config = ServerConfiguration(
            name: "Test Server",
            command: "npm",
            arguments: ["run", "dev"],
            localhostURL: "http://localhost:3000"
        )
        
        // When: Generating an app bundle
        let bundleURL = try await generator.generate(
            configuration: config,
            outputPath: tempDirectory,
            progressHandler: nil
        )
        
        // Then: Bundle should exist with correct structure
        XCTAssertTrue(FileManager.default.fileExists(atPath: bundleURL.path), "Bundle should exist")
        XCTAssertTrue(bundleURL.lastPathComponent.hasSuffix(".app"), "Bundle should have .app extension")
        
        // Verify Contents directory
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        XCTAssertTrue(FileManager.default.fileExists(atPath: contentsURL.path), "Contents directory should exist")
        
        // Verify MacOS directory
        let macOSURL = contentsURL.appendingPathComponent("MacOS")
        XCTAssertTrue(FileManager.default.fileExists(atPath: macOSURL.path), "MacOS directory should exist")
        
        // Verify Resources directory
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        XCTAssertTrue(FileManager.default.fileExists(atPath: resourcesURL.path), "Resources directory should exist")
    }
    
    func testGenerateCreatesExecutableInMacOSDirectory() async throws {
        // Given: A valid server configuration
        let config = ServerConfiguration(
            name: "Test Server",
            command: "python3",
            arguments: ["-m", "http.server"]
        )
        
        // When: Generating an app bundle
        let bundleURL = try await generator.generate(
            configuration: config,
            outputPath: tempDirectory,
            progressHandler: nil
        )
        
        // Then: Executable should exist in MacOS directory
        let executableURL = bundleURL.appendingPathComponent("Contents/MacOS/ServerAppBundle")
        XCTAssertTrue(FileManager.default.fileExists(atPath: executableURL.path), "Executable should exist")
        
        // Verify executable permissions
        let attributes = try FileManager.default.attributesOfItem(atPath: executableURL.path)
        let permissions = attributes[.posixPermissions] as? NSNumber
        XCTAssertNotNil(permissions, "Executable should have permissions set")
        XCTAssertEqual(permissions?.intValue, 0o755, "Executable should have 755 permissions")
    }
    
    // MARK: - Info.plist Generation Tests
    
    func testGenerateCreatesInfoPlist() async throws {
        // Given: A valid server configuration
        let config = ServerConfiguration(
            name: "Test Server",
            command: "npm",
            arguments: ["run", "dev"],
            localhostURL: "http://localhost:3000"
        )
        
        // When: Generating an app bundle
        let bundleURL = try await generator.generate(
            configuration: config,
            outputPath: tempDirectory,
            progressHandler: nil
        )
        
        // Then: Info.plist should exist in Contents directory
        let infoPlistURL = bundleURL.appendingPathComponent("Contents/Info.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistURL.path), "Info.plist should exist")
        
        // Verify Info.plist can be read and contains correct values
        let plistData = try Data(contentsOf: infoPlistURL)
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        
        // Verify key fields
        XCTAssertEqual(plist["CFBundleName"] as? String, "Test Server")
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "ServerAppBundle")
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "13.0")
        
        // Verify bundle identifier contains config ID
        let bundleIdentifier = plist["CFBundleIdentifier"] as? String
        XCTAssertNotNil(bundleIdentifier)
        XCTAssertTrue(bundleIdentifier!.contains(config.id.uuidString.lowercased()))
    }
    
    // MARK: - Configuration Embedding Tests
    
    func testGenerateEmbedsConfigurationJSON() async throws {
        // Given: A server configuration with all fields populated
        let config = ServerConfiguration(
            name: "Full Config Server",
            command: "node",
            arguments: ["server.js"],
            localhostURL: "http://localhost:8080",
            readySignalPattern: "Server listening",
            portDetectionPattern: "port (\\d+)",
            customIconPath: "/path/to/icon.png"
        )
        
        // When: Generating an app bundle
        let bundleURL = try await generator.generate(
            configuration: config,
            outputPath: tempDirectory,
            progressHandler: nil
        )
        
        // Then: Configuration JSON should exist in Resources
        let configURL = bundleURL.appendingPathComponent("Contents/Resources/configuration.json")
        XCTAssertTrue(FileManager.default.fileExists(atPath: configURL.path), "Configuration JSON should exist")
        
        // Verify configuration can be decoded
        let jsonData = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedConfig = try decoder.decode(ServerConfiguration.self, from: jsonData)
        
        // Verify all fields match
        XCTAssertEqual(decodedConfig.id, config.id)
        XCTAssertEqual(decodedConfig.name, config.name)
        XCTAssertEqual(decodedConfig.command, config.command)
        XCTAssertEqual(decodedConfig.arguments, config.arguments)
        XCTAssertEqual(decodedConfig.localhostURL, config.localhostURL)
        XCTAssertEqual(decodedConfig.readySignalPattern, config.readySignalPattern)
        XCTAssertEqual(decodedConfig.portDetectionPattern, config.portDetectionPattern)
        XCTAssertEqual(decodedConfig.customIconPath, config.customIconPath)
    }
    
    func testGenerateEmbedsMinimalConfiguration() async throws {
        // Given: A minimal server configuration (only required fields)
        let config = ServerConfiguration(
            name: "Minimal Server",
            command: "python3"
        )
        
        // When: Generating an app bundle
        let bundleURL = try await generator.generate(
            configuration: config,
            outputPath: tempDirectory,
            progressHandler: nil
        )
        
        // Then: Configuration should be embedded correctly
        let configURL = bundleURL.appendingPathComponent("Contents/Resources/configuration.json")
        let jsonData = try Data(contentsOf: configURL)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decodedConfig = try decoder.decode(ServerConfiguration.self, from: jsonData)
        
        XCTAssertEqual(decodedConfig.name, config.name)
        XCTAssertEqual(decodedConfig.command, config.command)
        XCTAssertEqual(decodedConfig.arguments, [])
        XCTAssertNil(decodedConfig.localhostURL)
        XCTAssertNil(decodedConfig.readySignalPattern)
    }
    
    // MARK: - Bundle Naming Tests
    
    func testGenerateSanitizesBundleName() async throws {
        // Given: A configuration with special characters in the name
        let config = ServerConfiguration(
            name: "My/Server:With*Special?Characters",
            command: "npm"
        )
        
        // When: Generating an app bundle
        let bundleURL = try await generator.generate(
            configuration: config,
            outputPath: tempDirectory,
            progressHandler: nil
        )
        
        // Then: Bundle name should be sanitized
        let bundleName = bundleURL.lastPathComponent
        XCTAssertFalse(bundleName.contains("/"))
        XCTAssertFalse(bundleName.contains(":"))
        XCTAssertFalse(bundleName.contains("*"))
        XCTAssertFalse(bundleName.contains("?"))
        XCTAssertTrue(bundleName.hasSuffix(".app"))
    }
    
    func testGenerateReplacesExistingBundle() async throws {
        // Given: A configuration and an existing bundle with the same name
        let config = ServerConfiguration(
            name: "Test Server",
            command: "npm"
        )
        
        // Create first bundle
        let firstBundleURL = try await generator.generate(
            configuration: config,
            outputPath: tempDirectory,
            progressHandler: nil
        )
        
        // Modify the first bundle to verify it gets replaced
        let markerURL = firstBundleURL.appendingPathComponent("Contents/marker.txt")
        try "marker".write(to: markerURL, atomically: true, encoding: .utf8)
        XCTAssertTrue(FileManager.default.fileExists(atPath: markerURL.path))
        
        // When: Generating a second bundle with the same name
        let secondBundleURL = try await generator.generate(
            configuration: config,
            outputPath: tempDirectory,
            progressHandler: nil
        )
        
        // Then: Second bundle should replace the first
        XCTAssertEqual(firstBundleURL.path, secondBundleURL.path)
        XCTAssertFalse(FileManager.default.fileExists(atPath: markerURL.path), "Old bundle should be replaced")
    }
    
    // MARK: - Error Handling Tests
    
    func testGenerateThrowsErrorForInvalidOutputPath() async throws {
        // Given: An invalid output path
        let invalidPath = URL(fileURLWithPath: "/nonexistent/path/that/does/not/exist")
        let config = ServerConfiguration(
            name: "Test Server",
            command: "npm"
        )
        
        // When/Then: Generating should throw invalidOutputPath error
        do {
            _ = try await generator.generate(
                configuration: config,
                outputPath: invalidPath,
                progressHandler: nil
            )
            XCTFail("Should have thrown invalidOutputPath error")
        } catch GenerationError.invalidOutputPath {
            // Expected error
        } catch {
            XCTFail("Unexpected error: \(error)")
        }
    }
    
    // MARK: - Progress Reporting Tests
    
    func testGenerateReportsProgress() async throws {
        // Given: A configuration and a progress handler
        let config = ServerConfiguration(
            name: "Test Server",
            command: "npm"
        )
        
        var progressUpdates: [(Double, String)] = []
        let progressHandler: (Double, String) -> Void = { progress, message in
            progressUpdates.append((progress, message))
        }
        
        // When: Generating an app bundle
        _ = try await generator.generate(
            configuration: config,
            outputPath: tempDirectory,
            progressHandler: progressHandler
        )
        
        // Then: Progress should be reported
        XCTAssertFalse(progressUpdates.isEmpty, "Progress updates should be reported")
        XCTAssertEqual(progressUpdates.first?.0, 0.0, "First progress should be 0.0")
        XCTAssertEqual(progressUpdates.last?.0, 1.0, "Last progress should be 1.0")
        
        // Verify progress is monotonically increasing
        for i in 1..<progressUpdates.count {
            XCTAssertGreaterThanOrEqual(progressUpdates[i].0, progressUpdates[i-1].0, "Progress should increase")
        }
    }
}
