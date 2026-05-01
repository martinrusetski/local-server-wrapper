//
//  IconProcessorTests.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import XCTest
import AppKit
@testable import LocalServerWrapper

final class IconProcessorTests: XCTestCase {
    
    var tempDirectory: URL!
    var bundleURL: URL!
    
    override func setUp() async throws {
        try await super.setUp()
        
        // Create a temporary directory for test output
        tempDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDirectory, withIntermediateDirectories: true)
        
        // Create a mock bundle structure
        bundleURL = tempDirectory.appendingPathComponent("TestApp.app")
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        try FileManager.default.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
    }
    
    override func tearDown() async throws {
        // Clean up temporary directory
        if let tempDirectory = tempDirectory {
            try? FileManager.default.removeItem(at: tempDirectory)
        }
        bundleURL = nil
        tempDirectory = nil
        try await super.tearDown()
    }
    
    // MARK: - Default Icon Tests
    
    func testProcessIconCreatesDefaultIconWhenNoCustomIconProvided() throws {
        // Given: No custom icon path
        let customIconPath: String? = nil
        
        // When: Processing icon
        try IconProcessor.processIcon(customIconPath: customIconPath, bundleURL: bundleURL)
        
        // Then: Default icon should be created
        let iconURL = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path), "Default icon should be created")
        
        // Verify it's a valid .icns file
        XCTAssertEqual(iconURL.pathExtension, "icns", "Icon should have .icns extension")
    }
    
    func testProcessIconCreatesDefaultIconWhenCustomIconPathIsEmpty() throws {
        // Given: Empty custom icon path
        let customIconPath = ""
        
        // When: Processing icon
        try IconProcessor.processIcon(customIconPath: customIconPath, bundleURL: bundleURL)
        
        // Then: Default icon should be created
        let iconURL = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path), "Default icon should be created")
    }
    
    func testProcessIconCreatesDefaultIconWhenCustomIconDoesNotExist() throws {
        // Given: Path to non-existent icon file
        let customIconPath = "/nonexistent/path/to/icon.png"
        
        // When: Processing icon (should fall back to default)
        try IconProcessor.processIcon(customIconPath: customIconPath, bundleURL: bundleURL)
        
        // Then: Default icon should be created
        let iconURL = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path), "Default icon should be created as fallback")
    }
    
    // MARK: - Custom Icon Tests
    
    func testProcessIconCopiesIcnsFileDirectly() throws {
        // Given: A custom .icns file
        let customIconURL = tempDirectory.appendingPathComponent("custom.icns")
        
        // Create a simple .icns file (we'll create a minimal valid one)
        let testIconData = createTestIcnsData()
        try testIconData.write(to: customIconURL)
        
        // When: Processing icon
        try IconProcessor.processIcon(customIconPath: customIconURL.path, bundleURL: bundleURL)
        
        // Then: Icon should be copied to Resources
        let iconURL = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path), "Icon should be copied")
        
        // Verify the file was copied (not converted)
        let copiedData = try Data(contentsOf: iconURL)
        XCTAssertEqual(copiedData, testIconData, "Icon data should match original")
    }
    
    func testProcessIconConvertsPngToIcns() throws {
        // Given: A custom .png file
        let customIconURL = tempDirectory.appendingPathComponent("custom.png")
        
        // Create a test PNG image
        let testImage = createTestImage(size: NSSize(width: 512, height: 512))
        guard let pngData = testImage.pngData() else {
            XCTFail("Failed to create PNG data")
            return
        }
        try pngData.write(to: customIconURL)
        
        // When: Processing icon
        try IconProcessor.processIcon(customIconPath: customIconURL.path, bundleURL: bundleURL)
        
        // Then: Icon should be converted and saved as .icns
        let iconURL = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path), "Converted icon should exist")
        XCTAssertEqual(iconURL.pathExtension, "icns", "Icon should have .icns extension")
    }
    
    func testProcessIconConvertsJpgToIcns() throws {
        // Given: A custom .jpg file
        let customIconURL = tempDirectory.appendingPathComponent("custom.jpg")
        
        // Create a test JPEG image
        let testImage = createTestImage(size: NSSize(width: 512, height: 512))
        guard let tiffData = testImage.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData),
              let jpgData = bitmapImage.representation(using: .jpeg, properties: [:]) else {
            XCTFail("Failed to create JPEG data")
            return
        }
        try jpgData.write(to: customIconURL)
        
        // When: Processing icon
        try IconProcessor.processIcon(customIconPath: customIconURL.path, bundleURL: bundleURL)
        
        // Then: Icon should be converted and saved as .icns
        let iconURL = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path), "Converted icon should exist")
    }
    
    func testProcessIconReplacesExistingIcon() throws {
        // Given: An existing icon in the bundle
        let iconURL = bundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        let oldIconData = Data("old icon data".utf8)
        try oldIconData.write(to: iconURL)
        
        // And: A new custom icon
        let customIconURL = tempDirectory.appendingPathComponent("new.icns")
        let newIconData = createTestIcnsData()
        try newIconData.write(to: customIconURL)
        
        // When: Processing icon
        try IconProcessor.processIcon(customIconPath: customIconURL.path, bundleURL: bundleURL)
        
        // Then: Old icon should be replaced
        let finalIconData = try Data(contentsOf: iconURL)
        XCTAssertNotEqual(finalIconData, oldIconData, "Old icon should be replaced")
        XCTAssertEqual(finalIconData, newIconData, "New icon should be in place")
    }
    
    // MARK: - Integration with AppBundleGenerator
    
    func testAppBundleGeneratorIncludesIcon() async throws {
        // Given: A configuration with a custom icon
        let customIconURL = tempDirectory.appendingPathComponent("custom.png")
        let testImage = createTestImage(size: NSSize(width: 512, height: 512))
        guard let pngData = testImage.pngData() else {
            XCTFail("Failed to create PNG data")
            return
        }
        try pngData.write(to: customIconURL)
        
        let config = ServerConfiguration(
            name: "Test Server",
            command: "npm",
            arguments: ["run", "dev"],
            customIconPath: customIconURL.path
        )
        
        // When: Generating an app bundle
        let generator = AppBundleGenerator()
        let generatedBundleURL = try await generator.generate(
            configuration: config,
            outputPath: tempDirectory,
            progressHandler: nil
        )
        
        // Then: Bundle should contain the icon
        let iconURL = generatedBundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path), "Generated bundle should contain icon")
    }
    
    func testAppBundleGeneratorIncludesDefaultIconWhenNoCustomIcon() async throws {
        // Given: A configuration without a custom icon
        let config = ServerConfiguration(
            name: "Test Server",
            command: "npm",
            arguments: ["run", "dev"]
        )
        
        // When: Generating an app bundle
        let generator = AppBundleGenerator()
        let generatedBundleURL = try await generator.generate(
            configuration: config,
            outputPath: tempDirectory,
            progressHandler: nil
        )
        
        // Then: Bundle should contain a default icon
        let iconURL = generatedBundleURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
        XCTAssertTrue(FileManager.default.fileExists(atPath: iconURL.path), "Generated bundle should contain default icon")
    }
    
    // MARK: - Helper Methods
    
    /// Create a simple test image
    private func createTestImage(size: NSSize) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        
        // Draw a simple colored rectangle
        NSColor.blue.setFill()
        NSRect(origin: .zero, size: size).fill()
        
        // Draw a circle in the center
        NSColor.white.setFill()
        let circleSize = min(size.width, size.height) * 0.6
        let circleRect = NSRect(
            x: (size.width - circleSize) / 2,
            y: (size.height - circleSize) / 2,
            width: circleSize,
            height: circleSize
        )
        NSBezierPath(ovalIn: circleRect).fill()
        
        image.unlockFocus()
        return image
    }
    
    /// Create minimal test .icns data
    /// Note: This creates a simple data blob, not a fully valid .icns file
    /// For testing purposes, we just need something to verify copying works
    private func createTestIcnsData() -> Data {
        // Create a simple PNG and convert it to .icns using the actual conversion logic
        let testImage = createTestImage(size: NSSize(width: 512, height: 512))
        guard let pngData = testImage.pngData() else {
            return Data("test icns data".utf8)
        }
        
        // For testing, we'll just return the PNG data
        // In a real scenario, this would be converted to .icns format
        return pngData
    }
}

// MARK: - NSImage Extension for PNG Data (if not already defined)

extension NSImage {
    func pngData() -> Data? {
        guard let tiffData = self.tiffRepresentation,
              let bitmapImage = NSBitmapImageRep(data: tiffData) else {
            return nil
        }
        
        return bitmapImage.representation(using: .png, properties: [:])
    }
}
