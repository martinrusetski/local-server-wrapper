//
//  InfoPlistGeneratorTests.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import XCTest
@testable import LocalServerWrapper

final class InfoPlistGeneratorTests: XCTestCase {
    
    var tempDirectory: URL!
    
    override func setUp() {
        super.setUp()
        // Create a temporary directory for test bundles
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try? FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
    }
    
    override func tearDown() {
        // Clean up temporary directory
        try? FileManager.default.removeItem(at: tempDirectory)
        super.tearDown()
    }
    
    // MARK: - Test Info.plist Generation
    
    func testGenerateInfoPlistWithAllFields() throws {
        // Given: A configuration with all fields populated
        let config = ServerConfiguration(
            id: UUID(),
            name: "Test Server",
            command: "npm",
            arguments: ["run", "dev"],
            localhostURL: "http://localhost:3000",
            readySignalPattern: "Server ready",
            portDetectionPattern: "port (\\d+)",
            customIconPath: "/path/to/icon.png"
        )
        
        // Create bundle structure
        let bundleURL = tempDirectory.appendingPathComponent("TestApp.app")
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        
        // When: Generate Info.plist
        try InfoPlistGenerator.generate(for: config, at: bundleURL)
        
        // Then: Info.plist should exist
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistURL.path), "Info.plist should be created")
        
        // And: Info.plist should contain correct values
        let plistData = try Data(contentsOf: infoPlistURL)
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        
        // Verify bundle identifier
        let bundleIdentifier = plist["CFBundleIdentifier"] as? String
        XCTAssertNotNil(bundleIdentifier)
        XCTAssertTrue(bundleIdentifier!.hasPrefix("com.localserverwrapper.generated."))
        XCTAssertTrue(bundleIdentifier!.contains(config.id.uuidString.lowercased()))
        
        // Verify bundle name
        XCTAssertEqual(plist["CFBundleName"] as? String, "Test Server")
        XCTAssertEqual(plist["CFBundleDisplayName"] as? String, "Test Server")
        
        // Verify executable name
        XCTAssertEqual(plist["CFBundleExecutable"] as? String, "ServerAppBundle")
        
        // Verify icon file is set
        XCTAssertEqual(plist["CFBundleIconFile"] as? String, "AppIcon")
        
        // Verify minimum system version
        XCTAssertEqual(plist["LSMinimumSystemVersion"] as? String, "13.0")
        
        // Verify high resolution capable
        XCTAssertEqual(plist["NSHighResolutionCapable"] as? Bool, true)
        
        // Verify package type
        XCTAssertEqual(plist["CFBundlePackageType"] as? String, "APPL")
    }
    
    func testGenerateInfoPlistWithoutCustomIcon() throws {
        // Given: A configuration without custom icon
        let config = ServerConfiguration(
            name: "Simple Server",
            command: "python3",
            arguments: ["-m", "http.server"]
        )
        
        // Create bundle structure
        let bundleURL = tempDirectory.appendingPathComponent("SimpleApp.app")
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        
        // When: Generate Info.plist
        try InfoPlistGenerator.generate(for: config, at: bundleURL)
        
        // Then: Info.plist should exist
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        XCTAssertTrue(FileManager.default.fileExists(atPath: infoPlistURL.path))
        
        // And: Icon file should not be set
        let plistData = try Data(contentsOf: infoPlistURL)
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        
        XCTAssertNil(plist["CFBundleIconFile"], "Icon file should not be set when no custom icon is provided")
    }
    
    func testGenerateInfoPlistWithSpecialCharactersInName() throws {
        // Given: A configuration with special characters in name
        let config = ServerConfiguration(
            name: "My Server: Dev & Test!",
            command: "node",
            arguments: ["server.js"]
        )
        
        // Create bundle structure
        let bundleURL = tempDirectory.appendingPathComponent("SpecialApp.app")
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        
        // When: Generate Info.plist
        try InfoPlistGenerator.generate(for: config, at: bundleURL)
        
        // Then: Info.plist should exist and contain the name as-is
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let plistData = try Data(contentsOf: infoPlistURL)
        let plist = try PropertyListSerialization.propertyList(from: plistData, format: nil) as! [String: Any]
        
        XCTAssertEqual(plist["CFBundleName"] as? String, "My Server: Dev & Test!")
    }
    
    func testGenerateInfoPlistCreatesValidXMLFormat() throws {
        // Given: A basic configuration
        let config = ServerConfiguration(
            name: "XML Test",
            command: "npm"
        )
        
        // Create bundle structure
        let bundleURL = tempDirectory.appendingPathComponent("XMLApp.app")
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        try FileManager.default.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        
        // When: Generate Info.plist
        try InfoPlistGenerator.generate(for: config, at: bundleURL)
        
        // Then: Info.plist should be valid XML
        let infoPlistURL = contentsURL.appendingPathComponent("Info.plist")
        let plistData = try Data(contentsOf: infoPlistURL)
        
        // Should be able to parse as property list
        XCTAssertNoThrow(try PropertyListSerialization.propertyList(from: plistData, format: nil))
        
        // Should be XML format
        let xmlString = String(data: plistData, encoding: .utf8)
        XCTAssertNotNil(xmlString)
        XCTAssertTrue(xmlString!.contains("<?xml version=\"1.0\" encoding=\"UTF-8\"?>"))
        XCTAssertTrue(xmlString!.contains("<!DOCTYPE plist"))
    }
    
    func testGenerateInfoPlistFailsWithInvalidBundlePath() {
        // Given: A configuration and invalid bundle path
        let config = ServerConfiguration(
            name: "Test",
            command: "npm"
        )
        
        let invalidBundleURL = tempDirectory.appendingPathComponent("NonExistent.app")
        // Don't create the Contents directory
        
        // When/Then: Should throw error
        XCTAssertThrowsError(try InfoPlistGenerator.generate(for: config, at: invalidBundleURL)) { error in
            guard case GenerationError.bundleCreationFailed = error else {
                XCTFail("Expected GenerationError.bundleCreationFailed, got \(error)")
                return
            }
        }
    }
    
    func testBundleIdentifierIsUnique() throws {
        // Given: Two configurations with different IDs
        let config1 = ServerConfiguration(id: UUID(), name: "Server 1", command: "npm")
        let config2 = ServerConfiguration(id: UUID(), name: "Server 2", command: "npm")
        
        // Create bundle structures
        let bundle1URL = tempDirectory.appendingPathComponent("App1.app")
        let bundle2URL = tempDirectory.appendingPathComponent("App2.app")
        
        try FileManager.default.createDirectory(at: bundle1URL.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: bundle2URL.appendingPathComponent("Contents"), withIntermediateDirectories: true)
        
        // When: Generate Info.plist for both
        try InfoPlistGenerator.generate(for: config1, at: bundle1URL)
        try InfoPlistGenerator.generate(for: config2, at: bundle2URL)
        
        // Then: Bundle identifiers should be different
        let plist1Data = try Data(contentsOf: bundle1URL.appendingPathComponent("Contents/Info.plist"))
        let plist1 = try PropertyListSerialization.propertyList(from: plist1Data, format: nil) as! [String: Any]
        
        let plist2Data = try Data(contentsOf: bundle2URL.appendingPathComponent("Contents/Info.plist"))
        let plist2 = try PropertyListSerialization.propertyList(from: plist2Data, format: nil) as! [String: Any]
        
        let bundleId1 = plist1["CFBundleIdentifier"] as? String
        let bundleId2 = plist2["CFBundleIdentifier"] as? String
        
        XCTAssertNotNil(bundleId1)
        XCTAssertNotNil(bundleId2)
        XCTAssertNotEqual(bundleId1, bundleId2, "Bundle identifiers should be unique")
    }
}
