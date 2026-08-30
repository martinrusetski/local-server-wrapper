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
        try signAdHoc(bundleURL)
        
        // Clear quarantine from the finished bundle. The launcher template (and any user-provided
        // custom icon) may carry com.apple.quarantine if the manager itself was downloaded, and
        // copyItem preserves it; left in place it can trip Gatekeeper/dyld on a user's machine even
        // though dev-machine bundles are never quarantined. The attribute is excluded from the code
        // signature, so doing this after signing does not invalidate it.
        QuarantineRemover.removeRecursively(at: bundleURL)

        // Report progress: Complete (100%)
        progressHandler?(1.0, "Bundle generation complete")
        os_log(.info, log: logger, "Successfully generated bundle: %{public}@", bundleURL.path)
        
        return bundleURL
    }
    
    // MARK: - Private Methods

    /// Copy the self-contained launcher template (ServerAppBundle.app) to the destination bundle URL.
    ///
    /// The template embeds its signed ServerRuntime.framework under Contents/Frameworks and uses
    /// only the bundle-relative rpath, so generated apps do not execute code from a user-home path.
    ///
    /// - Parameter bundleURL: The URL of the bundle being created
    /// - Throws: GenerationError.resourceCopyFailed if the template is missing or copying fails
    private func copyExecutableTemplate(to bundleURL: URL) throws {
        guard let sourceURL = ProductLocator.launcherTemplate() else {
            os_log(.error, log: logger, "Launcher template (ServerAppBundle.app) not found")
            throw GenerationError.resourceCopyFailed("""
                Launcher template (ServerAppBundle.app) not found.

                For development: build the ServerAppBundle scheme (Release) first.
                For distribution: ship the self-contained ServerAppBundle.app with the manager.
                """)
        }

        os_log(.debug, log: logger, "Copying launcher template from: %{public}@", sourceURL.path)

        // Remove the bundle we created (we'll replace it with a copy of the template)
        try? FileManager.default.removeItem(at: bundleURL)

        do {
            try FileManager.default.copyItem(at: sourceURL, to: bundleURL)
            os_log(.debug, log: logger, "Launcher template copied successfully")
        } catch {
            os_log(.error, log: logger, "Failed to copy launcher template: %{public}@", error.localizedDescription)
            throw GenerationError.resourceCopyFailed("Failed to copy launcher template: \(error.localizedDescription)")
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
    
    /// Re-sign the modified app bundle with hardened runtime enabled, then verify the complete
    /// nested bundle. Generation fails closed because an unsigned or partially signed launcher
    /// must not be presented as a usable credential-bearing app.
    /// - Parameter bundleURL: The URL of the bundle to sign
    /// - Throws: GenerationError.signingFailed if signing fails
    private func signAdHoc(_ bundleURL: URL) throws {
        os_log(.info, log: logger, "Signing bundle with ad-hoc signature")
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = [
            "--force", "--sign", "-",
            "--options", "runtime",
            "--preserve-metadata=entitlements",
            bundleURL.path
        ]
        
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
            
            try verifySignature(bundleURL)
            os_log(.info, log: logger, "Bundle signed and verified successfully")
        } catch let error as GenerationError {
            throw error
        } catch {
            throw GenerationError.signingFailed(error.localizedDescription)
        }
    }

    private func verifySignature(_ bundleURL: URL) throws {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/codesign")
        process.arguments = ["--verify", "--deep", "--strict", "--verbose=2", bundleURL.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe
        try process.run()
        process.waitUntilExit()

        guard process.terminationStatus == 0 else {
            let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
            let output = String(data: data, encoding: .utf8) ?? "Unknown verification error"
            throw GenerationError.signingFailed(output)
        }
    }
}

// NOTE: The old signBundle(at:) helper was removed here (TASK-6). It contained a hardcoded
// developer-specific entitlements path. Generation signs and verifies through the methods above.
