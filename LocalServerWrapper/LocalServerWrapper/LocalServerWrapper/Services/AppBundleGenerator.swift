//
//  AppBundleGenerator.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation
import os.log

/// Logger for app bundle generation operations
private let logger = OSLog(subsystem: "com.localserverwrapper.configmanager", category: "generation")

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
        os_log(.info, log: logger, "Starting bundle generation for: %{public}@", configuration.name)
        
        // Validate output path
        guard FileManager.default.fileExists(atPath: outputPath.path) else {
            os_log(.error, log: logger, "Invalid output path: %{public}@", outputPath.path)
            throw GenerationError.invalidOutputPath
        }
        
        // Report progress: Starting (0%)
        progressHandler?(0.0, "Starting bundle generation...")
        
        // Create bundle URL with .app extension
        let bundleName = sanitizeBundleName(configuration.name)
        let bundleURL = outputPath.appendingPathComponent("\(bundleName).app")
        os_log(.debug, log: logger, "Bundle will be created at: %{public}@", bundleURL.path)
        
        // Remove existing bundle if it exists
        if FileManager.default.fileExists(atPath: bundleURL.path) {
            os_log(.info, log: logger, "Removing existing bundle at: %{public}@", bundleURL.path)
            try? FileManager.default.removeItem(at: bundleURL)
        }
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Report progress: Creating structure (0-20%)
        progressHandler?(0.0, "Copying app template...")
        // Note: We skip createBundleStructure because copyExecutableTemplate
        // copies the entire ServerAppBundle.app which already has the structure
        try copyExecutableTemplate(to: bundleURL)
        progressHandler?(0.2, "App template copied")
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Report progress: Embedding configuration (40-60%)
        progressHandler?(0.4, "Embedding configuration...")
        try embedConfiguration(configuration, in: bundleURL)
        progressHandler?(0.6, "Configuration embedded")
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Report progress: Generating Info.plist (60-80%)
        progressHandler?(0.6, "Generating Info.plist...")
        try InfoPlistGenerator.generate(for: configuration, at: bundleURL)
        progressHandler?(0.8, "Info.plist generated")
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Report progress: Processing icon (80-90%)
        progressHandler?(0.8, "Processing icon...")
        do {
            try IconProcessor.processIcon(customIconPath: configuration.customIconPath, bundleURL: bundleURL)
            progressHandler?(0.9, "Icon processed")
        } catch {
            // Icon processing failed completely (even default icon failed)
            // Log the error but continue - the bundle will work without an icon
            os_log(.error, log: logger, "Icon processing failed completely: %{public}@", error.localizedDescription)
            progressHandler?(0.9, "Icon processing failed, continuing without custom icon")
        }
        
        // Check for cancellation
        try Task.checkCancellation()
        
        // Report progress: Code signing (90-100%)
        progressHandler?(0.9, "Signing bundle...")
        do {
            try signAdHoc(bundleURL)
        } catch {
            os_log(.error, log: logger, "Ad-hoc signing failed: %{public}@, bundle still functional without Keychain", error.localizedDescription)
        }
        
        // Report progress: Complete (100%)
        progressHandler?(1.0, "Bundle generation complete")
        os_log(.info, log: logger, "Successfully generated bundle: %{public}@", bundleURL.path)
        
        return bundleURL
    }
    
    // MARK: - Private Methods
    
    /// Create the standard macOS app bundle directory structure
    /// - Parameter bundleURL: The URL where the bundle should be created
    /// - Throws: GenerationError.bundleCreationFailed if structure creation fails
    private func createBundleStructure(at bundleURL: URL) throws {
        os_log(.debug, log: logger, "Creating bundle structure at: %{public}@", bundleURL.path)
        let fileManager = FileManager.default
        
        // Create main bundle directory
        do {
            try fileManager.createDirectory(at: bundleURL, withIntermediateDirectories: true)
            os_log(.debug, log: logger, "Created bundle directory")
        } catch {
            os_log(.error, log: logger, "Failed to create bundle directory: %{public}@", error.localizedDescription)
            throw GenerationError.bundleCreationFailed("Failed to create bundle directory: \(error.localizedDescription)")
        }
        
        // Create Contents directory
        let contentsURL = bundleURL.appendingPathComponent("Contents")
        do {
            try fileManager.createDirectory(at: contentsURL, withIntermediateDirectories: true)
            os_log(.debug, log: logger, "Created Contents directory")
        } catch {
            os_log(.error, log: logger, "Failed to create Contents directory: %{public}@", error.localizedDescription)
            throw GenerationError.bundleCreationFailed("Failed to create Contents directory: \(error.localizedDescription)")
        }
        
        // Create MacOS directory (for executable)
        let macOSURL = contentsURL.appendingPathComponent("MacOS")
        do {
            try fileManager.createDirectory(at: macOSURL, withIntermediateDirectories: true)
            os_log(.debug, log: logger, "Created MacOS directory")
        } catch {
            os_log(.error, log: logger, "Failed to create MacOS directory: %{public}@", error.localizedDescription)
            throw GenerationError.bundleCreationFailed("Failed to create MacOS directory: \(error.localizedDescription)")
        }
        
        // Create Resources directory (for configuration and assets)
        let resourcesURL = contentsURL.appendingPathComponent("Resources")
        do {
            try fileManager.createDirectory(at: resourcesURL, withIntermediateDirectories: true)
            os_log(.debug, log: logger, "Created Resources directory")
        } catch {
            os_log(.error, log: logger, "Failed to create Resources directory: %{public}@", error.localizedDescription)
            throw GenerationError.bundleCreationFailed("Failed to create Resources directory: \(error.localizedDescription)")
        }
    }
    
    /// Copy the executable template to the bundle's MacOS directory
    /// - Parameter bundleURL: The URL of the bundle being created
    /// - Throws: GenerationError.resourceCopyFailed if copying fails
    private func copyExecutableTemplate(to bundleURL: URL) throws {
        // Instead of copying just the executable, we need to copy the entire ServerAppBundle.app
        // and then customize it. This preserves all the necessary bundle structure.
        
        // Find the source ServerAppBundle.app
        var sourceAppURL: URL?
        
        // 1. Try embedded resource
        if let embeddedAppURL = Bundle.main.url(forResource: "ServerAppBundle", withExtension: "app") {
            if FileManager.default.fileExists(atPath: embeddedAppURL.path) {
                sourceAppURL = embeddedAppURL
                os_log(.info, log: logger, "Using embedded ServerAppBundle.app from resources")
            }
        }
        
        // 2. Try workspace Release build
        if sourceAppURL == nil, let executablePath = Bundle.main.executablePath {
            let executableURL = URL(fileURLWithPath: executablePath)
            var currentURL = executableURL
            for _ in 0..<10 {
                currentURL = currentURL.deletingLastPathComponent()
                if currentURL.lastPathComponent == "LocalServerWrapper" {
                    let workspaceRoot = currentURL.deletingLastPathComponent()
                    let releasePath = workspaceRoot.appendingPathComponent("ServerAppBundle/build/Build/Products/Release/ServerAppBundle.app")
                    if FileManager.default.fileExists(atPath: releasePath.path) {
                        sourceAppURL = releasePath
                        os_log(.info, log: logger, "Found Release build in workspace")
                        break
                    }
                }
            }
        }
        
        // 3. Try DerivedData Release builds
        if sourceAppURL == nil {
            let derivedDataPath = NSHomeDirectory() + "/Library/Developer/Xcode/DerivedData"
            let derivedDataURL = URL(fileURLWithPath: derivedDataPath)
            
            if let derivedDataContents = try? FileManager.default.contentsOfDirectory(
                at: derivedDataURL,
                includingPropertiesForKeys: [.isDirectoryKey],
                options: [.skipsHiddenFiles]
            ) {
                for folder in derivedDataContents {
                    if folder.lastPathComponent.hasPrefix("ServerAppBundle-") {
                        let releasePath = folder.appendingPathComponent("Build/Products/Release/ServerAppBundle.app")
                        if FileManager.default.fileExists(atPath: releasePath.path) {
                            sourceAppURL = releasePath
                            os_log(.info, log: logger, "Found Release build in DerivedData")
                            break
                        }
                    }
                }
            }
        }
        
        guard let sourceURL = sourceAppURL else {
            os_log(.error, log: logger, "ServerAppBundle.app not found")
            throw GenerationError.resourceCopyFailed("""
                ServerAppBundle.app not found.
                
                For development: Build ServerAppBundle in Release mode first.
                For distribution: Add ServerAppBundle.app to LocalServerWrapper's Copy Bundle Resources.
                
                See SIMPLE_SOLUTION.md for instructions.
                """)
        }
        
        os_log(.debug, log: logger, "Copying entire app bundle from: %{public}@", sourceURL.path)
        
        // Remove the bundle we created (we'll replace it with a copy of the source)
        try? FileManager.default.removeItem(at: bundleURL)
        
        do {
            // Copy the entire ServerAppBundle.app
            try FileManager.default.copyItem(at: sourceURL, to: bundleURL)
            
            os_log(.debug, log: logger, "App bundle copied successfully")
        } catch {
            os_log(.error, log: logger, "Failed to copy app bundle: %{public}@", error.localizedDescription)
            throw GenerationError.resourceCopyFailed("Failed to copy app bundle: \(error.localizedDescription)")
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
    
    /// Sign the app bundle with a simple ad-hoc signature (no entitlements)
    /// This enables Keychain access for the generated bundle
    /// - Parameter bundleURL: The URL of the bundle to sign
    /// - Throws: GenerationError.signingFailed if signing fails
    private func signAdHoc(_ bundleURL: URL) throws {
        os_log(.info, log: logger, "Signing bundle with ad-hoc signature")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--force", "--sign", "-", bundleURL.path]
        
        let errorPipe = Pipe()
        process.standardError = errorPipe
        
        do {
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                throw GenerationError.signingFailed(errorOutput)
            }
            
            os_log(.info, log: logger, "Bundle signed successfully")
        } catch let error as GenerationError {
            throw error
        } catch {
            throw GenerationError.signingFailed(error.localizedDescription)
        }
    }
    
    /// Sign the app bundle with entitlements using codesign
    /// - Parameter bundleURL: The URL of the bundle to sign
    /// - Throws: GenerationError.signingFailed if signing fails
    private func signBundle(at bundleURL: URL) async throws {
        os_log(.info, log: logger, "Signing bundle: %{public}@", bundleURL.lastPathComponent)
        
        // First, remove any existing signature from the executable
        // This is important because we copied a pre-signed executable
        let executableURL = bundleURL.appendingPathComponent("Contents/MacOS/ServerAppBundle")
        let removeProcess = Process()
        removeProcess.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        removeProcess.arguments = ["--remove-signature", executableURL.path]
        try? removeProcess.run()
        removeProcess.waitUntilExit()
        os_log(.debug, log: logger, "Removed existing signature from executable")
        
        // Locate the entitlements file
        var entitlementsURL: URL?
        var searchedPaths: [String] = []
        
        // 1. Try to find it in the main bundle resources
        if let bundleResource = Bundle.main.url(forResource: "ServerAppBundle", withExtension: "entitlements") {
            searchedPaths.append(bundleResource.path)
            if FileManager.default.fileExists(atPath: bundleResource.path) {
                entitlementsURL = bundleResource
            }
        }
        
        // 2. Try to find workspace root by navigating up from executable
        if entitlementsURL == nil, let executablePath = Bundle.main.executablePath {
            let executableURL = URL(fileURLWithPath: executablePath)
            var currentURL = executableURL
            for _ in 0..<10 {
                currentURL = currentURL.deletingLastPathComponent()
                if currentURL.lastPathComponent == "LocalServerWrapper" {
                    let workspaceRoot = currentURL.deletingLastPathComponent()
                    let candidatePath = workspaceRoot.appendingPathComponent("ServerAppBundle/ServerAppBundle/ServerAppBundle.entitlements")
                    searchedPaths.append(candidatePath.path)
                    if FileManager.default.fileExists(atPath: candidatePath.path) {
                        entitlementsURL = candidatePath
                        break
                    }
                }
            }
        }
        
        // 3. Try SRCROOT environment variable
        if entitlementsURL == nil, let sourceRoot = ProcessInfo.processInfo.environment["SRCROOT"] {
            let sourceRootURL = URL(fileURLWithPath: sourceRoot)
            let candidatePath = sourceRootURL
                .deletingLastPathComponent()
                .appendingPathComponent("ServerAppBundle/ServerAppBundle/ServerAppBundle.entitlements")
            searchedPaths.append(candidatePath.path)
            if FileManager.default.fileExists(atPath: candidatePath.path) {
                entitlementsURL = candidatePath
            }
        }
        
        // 4. Try absolute path (hardcoded for development)
        if entitlementsURL == nil {
            let absolutePath = URL(fileURLWithPath: "/Users/martinr/Developer/terminal-web-wrapper/ServerAppBundle/ServerAppBundle/ServerAppBundle.entitlements")
            searchedPaths.append(absolutePath.path)
            if FileManager.default.fileExists(atPath: absolutePath.path) {
                entitlementsURL = absolutePath
                os_log(.info, log: logger, "Using hardcoded absolute path for entitlements (development mode)")
            }
        }
        
        guard let entitlementsURL = entitlementsURL else {
            let searchedPathsString = searchedPaths.joined(separator: "\n  - ")
            os_log(.error, log: logger, "Entitlements file not found. Searched:\n%{public}@", searchedPathsString)
            throw GenerationError.signingFailed("Entitlements file not found. Searched locations:\n  - \(searchedPathsString)")
        }
        
        os_log(.debug, log: logger, "Using entitlements file: %{public}@", entitlementsURL.path)
        
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
                os_log(.error, log: logger, "codesign failed with status %d: %{public}@", process.terminationStatus, errorOutput)
                throw GenerationError.signingFailed("codesign failed with status \(process.terminationStatus): \(errorOutput)")
            }
            
            os_log(.debug, log: logger, "Bundle signed successfully")
            
            // Verify the signature after signing
            try await verifySignature(at: bundleURL)
            
        } catch let error as GenerationError {
            // Re-throw GenerationError as-is
            throw error
        } catch {
            os_log(.error, log: logger, "Failed to execute codesign: %{public}@", error.localizedDescription)
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
