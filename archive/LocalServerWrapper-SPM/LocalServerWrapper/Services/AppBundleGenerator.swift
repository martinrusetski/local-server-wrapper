//
//  AppBundleGenerator.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation

/// Protocol defining the interface for app bundle generation
protocol AppBundleGeneratorProtocol {
    /// Generate a standalone macOS app bundle from a server configuration
    /// - Parameters:
    ///   - configuration: The server configuration to embed in the bundle
    ///   - outputPath: The directory where the .app bundle should be created
    ///   - progressHandler: Optional closure to report progress (0.0 to 1.0) and status messages
    /// - Returns: URL of the generated app bundle
    /// - Throws: GenerationError if bundle creation fails
    func generate(
        configuration: ServerConfiguration,
        outputPath: URL,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> URL
}

/// Generates standalone macOS app bundles from server configurations
class AppBundleGenerator: AppBundleGeneratorProtocol {
    
    // MARK: - Public Methods
    
    func generate(
        configuration: ServerConfiguration,
        outputPath: URL,
        progressHandler: ((Double, String) -> Void)?
    ) async throws -> URL {
        // Validate output path
        guard FileManager.default.fileExists(atPath: outputPath.path) else {
            throw GenerationError.invalidOutputPath
        }
        
        // Report progress: Starting
        progressHandler?(0.0, "Starting bundle generation...")
        
        // Create bundle URL with .app extension
        let bundleName = sanitizeBundleName(configuration.name)
        let bundleURL = outputPath.appendingPathComponent("\(bundleName).app")
        
        // Remove existing bundle if it exists
        if FileManager.default.fileExists(atPath: bundleURL.path) {
            try? FileManager.default.removeItem(at: bundleURL)
        }
        
        // Report progress: Creating structure
        progressHandler?(0.2, "Creating bundle structure...")
        try createBundleStructure(at: bundleURL)
        
        // Report progress: Copying executable
        progressHandler?(0.4, "Copying executable...")
        try copyExecutableTemplate(to: bundleURL)
        
        // Report progress: Generating Info.plist
        progressHandler?(0.5, "Generating Info.plist...")
        try InfoPlistGenerator.generate(for: configuration, at: bundleURL)
        
        // Report progress: Embedding configuration
        progressHandler?(0.6, "Embedding configuration...")
        try embedConfiguration(configuration, in: bundleURL)
        
        // Report progress: Processing icon
        progressHandler?(0.75, "Processing icon...")
        try IconProcessor.processIcon(customIconPath: configuration.customIconPath, bundleURL: bundleURL)
        
        // Report progress: Signing bundle
        progressHandler?(0.9, "Signing bundle...")
        try await signBundle(at: bundleURL)
        
        // Report progress: Complete
        progressHandler?(1.0, "Bundle generation complete")
        
        return bundleURL
    }
    
    // MARK: - Private Methods
    
    /// Create the standard macOS app bundle directory structure
    /// - Parameter bundleURL: The URL where the bundle should be created
    /// - Throws: GenerationError.bundleCreationFailed if structure creation fails
    private func createBundleStructure(at bundleURL: URL) throws {
        let fileManager = FileManager.default
        
        // Create main bundle directory
        do {
            try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)
        } catch {
            throw GenerationError.bundleCreationFailed("Failed to create bundle directory: \(error.localizedDescription)")
        }
        
        // Create Contents directory
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        do {
            try fileManager.createDirectory(at: contentsURL, withIntermediateDirectories: true)
        } catch {
            throw GenerationError.bundleCreationFailed("Failed to create Contents directory: \(error.localizedDescription)")
        }
        
        // Create MacOS directory (for executable)
        let macOSURL = contentsURL.appendingPathComponent("MacOS")
        do {
            try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
        } catch {
            throw GenerationError.bundleCreationFailed("Failed to create MacOS directory: \(error.localizedDescription)")
        }
        
        // Create Resources directory (for configuration and assets)
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        do {
            try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
        } catch {
            throw GenerationError.bundleCreationFailed("Failed to create Resources directory: \(error.localizedDescription)")
        }
    }
    
    /// Copy the executable template to the bundle's MacOS directory
    /// - Parameter bundleURL: The URL of the bundle being created
    /// - Throws: GenerationError.resourceCopyFailed if copying fails
    private func copyExecutableTemplate(to bundleURL: URL) throws {
        // For now, this is a placeholder
        // In a real implementation, we would copy the ServerAppBundle executable
        // from the Configuration Manager's resources
        
        let macOSURL = bundleURL.appendingPathComponent("Contents/MacOS")
        let executableURL = macOSURL.appendingPathComponent("ServerAppBundle")
        
        // TODO: Copy actual executable from bundle resources
        // For now, create a placeholder file
        let placeholderData = Data("#!/bin/bash\necho 'Placeholder executable'\n".utf8)
        do {
            try placeholderData.write(to: executableURL)
            
            // Make executable
            let attributes = [FileAttributeKey.posixPermissions: 0o755]
            try FileManager.default.setAttributes(attributes, ofItemAtPath: executableURL.path)
        } catch {
            throw GenerationError.resourceCopyFailed("Failed to create executable: \(error.localizedDescription)")
        }
    }
    
    /// Embed the server configuration as JSON in the bundle's Resources directory
    /// - Parameters:
    ///   - configuration: The configuration to embed
    ///   - bundleURL: The URL of the bundle being created
    /// - Throws: GenerationError.configurationEmbedFailed if embedding fails
    private func embedConfiguration(_ configuration: ServerConfiguration, in bundleURL: URL) throws {
        let resourcesURL = bundleURL.appendingPathComponent("Contents/Resources")
        let configURL = resourcesURL.appendingPathComponent("configuration.json")
        
        // Encode configuration to JSON
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        
        do {
            let jsonData = try encoder.encode(configuration)
            try jsonData.write(to: configURL)
        } catch {
            throw GenerationError.configurationEmbedFailed("Failed to encode or write configuration: \(error.localizedDescription)")
        }
    }
    
    /// Sanitize a configuration name to be safe for use as a bundle name
    /// - Parameter name: The configuration name to sanitize
    /// - Returns: A sanitized name safe for filesystem use
    private func sanitizeBundleName(_ name: String) -> String {
        // Remove or replace characters that are invalid in filenames
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let components = name.components(separatedBy: invalidCharacters)
        let sanitized = components.joined(separator: "_")
        
        // Trim whitespace and ensure it's not empty
        let trimmed = sanitized.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "ServerApp" : trimmed
    }
    
    /// Sign the app bundle with entitlements using codesign
    /// - Parameter bundleURL: The URL of the bundle to sign
    /// - Throws: GenerationError.signingFailed if signing fails
    private func signBundle(at bundleURL: URL) async throws {
        // Locate the entitlements file
        // First try to find it in the main bundle resources
        var entitlementsURL = Bundle.main.url(forResource: "ServerAppBundle", withExtension: "entitlements")
        
        // If not found in bundle resources, try relative to the executable
        if entitlementsURL == nil {
            let executablePath = Bundle.main.executablePath ?? ""
            let executableDir = URL(fileURLWithPath: executablePath).deletingLastPathComponent()
            let candidatePath = executableDir.appendingPathComponent("../ServerAppBundle.entitlements")
            if FileManager.default.fileExists(atPath: candidatePath.path) {
                entitlementsURL = candidatePath
            }
        }
        
        // If still not found, try the project root (for development/testing)
        if entitlementsURL == nil {
            let projectRoot = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
            let candidatePath = projectRoot.appendingPathComponent("ServerAppBundle.entitlements")
            if FileManager.default.fileExists(atPath: candidatePath.path) {
                entitlementsURL = candidatePath
            }
        }
        
        guard let entitlementsURL = entitlementsURL else {
            throw GenerationError.signingFailed("Entitlements file not found in bundle resources")
        }
        
        // Create the codesign process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        
        // Set up arguments for ad-hoc signing with entitlements
        // --force: Replace existing signature if present
        // --sign -: Ad-hoc signing (no developer certificate required)
        // --entitlements: Path to entitlements file
        // --deep: Sign nested code (if any)
        process.arguments = [
            "--force",
            "--sign", "-",
            "--entitlements", entitlementsURL.path,
            "--deep",
            bundleURL.path
        ]
        
        // Capture output for error reporting
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Run the codesign process
        do {
            try process.run()
            process.waitUntilExit()
            
            // Check exit status
            if process.terminationStatus != 0 {
                // Read error output
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw GenerationError.signingFailed("codesign failed with status \(process.terminationStatus): \(errorOutput)")
            }
            
            // Verify the signature after signing
            try await verifySignature(at: bundleURL)
            
        } catch let error as GenerationError {
            // Re-throw GenerationError as-is
            throw error
        } catch {
            throw GenerationError.signingFailed("Failed to execute codesign: \(error.localizedDescription)")
        }
    }
    
    /// Verify the code signature of the bundle
    /// - Parameter bundleURL: The URL of the bundle to verify
    /// - Throws: GenerationError.signingFailed if verification fails
    private func verifySignature(at bundleURL: URL) async throws {
        // Create the codesign verification process
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        
        // Set up arguments for verification
        // --verify: Verify the code signature
        // --deep: Verify nested code
        // --strict: Use strict verification
        // --verbose: Provide detailed output
        process.arguments = [
            "--verify",
            "--deep",
            "--strict",
            "--verbose=2",
            bundleURL.path
        ]
        
        // Capture output for error reporting
        let outputPipe = Pipe()
        let errorPipe = Pipe()
        process.standardOutput = outputPipe
        process.standardError = errorPipe
        
        // Run the verification process
        do {
            try process.run()
            process.waitUntilExit()
            
            // Check exit status
            if process.terminationStatus != 0 {
                // Read error output
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw GenerationError.signingFailed("Signature verification failed: \(errorOutput)")
            }
            
        } catch let error as GenerationError {
            // Re-throw GenerationError as-is
            throw error
        } catch {
            throw GenerationError.signingFailed("Failed to verify signature: \(error.localizedDescription)")
        }
    }
}
