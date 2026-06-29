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

        // Ensure the shared runtime is installed to ~/Library/Frameworks; the thin launcher we copy
        // below loads it from there (Step 2). Fail loudly if it can't be made available, otherwise
        // generated bundles would launch-crash with a missing framework.
        guard RuntimeInstaller.installIfNeeded() else {
            throw GenerationError.resourceCopyFailed("""
                Shared ServerRuntime.framework could not be installed to ~/Library/Frameworks.
                Build the ServerAppBundle scheme (Release) first so the framework exists.
                """)
        }
        
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

    /// Copy the thin launcher template (ServerAppBundle.app) to the destination bundle URL.
    ///
    /// The template is now a *thin launcher*: it loads the shared ServerRuntime.framework from
    /// ~/Library/Frameworks via the absolute rpath baked into its binary, so each generated copy is
    /// small and no longer embeds its own runtime. No `install_name_tool` patch is needed — the
    /// template already carries the right rpath.
    ///
    /// - Parameter bundleURL: The URL of the bundle being created
    /// - Throws: GenerationError.resourceCopyFailed if the template is missing or copying fails
    private func copyExecutableTemplate(to bundleURL: URL) throws {
        guard let sourceURL = ProductLocator.launcherTemplate() else {
            os_log(.error, log: logger, "Launcher template (ServerAppBundle.app) not found")
            throw GenerationError.resourceCopyFailed("""
                Launcher template (ServerAppBundle.app) not found.

                For development: build the ServerAppBundle scheme (Release) first.
                For distribution: ship ServerAppBundle.app (and ServerRuntime.framework) with the manager.
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
}

// NOTE: The unused signBundle(at:) and verifySignature(at:) helpers were removed here (TASK-6).
// They were never called — generation signs via the ad-hoc signAdHoc(_:) path above — and
// signBundle contained a hardcoded developer-specific entitlements path. Do not reintroduce them.
