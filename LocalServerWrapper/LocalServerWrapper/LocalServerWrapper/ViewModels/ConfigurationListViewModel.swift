//
//  ConfigurationListViewModel.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation
import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers
import CryptoKit
import UserNotifications
import os.log

/// Logger for view model operations
private let logger = OSLog(subsystem: "com.localserverwrapper.configmanager", category: "viewmodel")

/// View model for the configuration list view
@MainActor
class ConfigurationListViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// The list of configurations
    @Published var configurations: [ServerConfiguration] = []
    
    /// Error message to display
    @Published var errorMessage: String?
    
    /// Success message to display
    @Published var successMessage: String?
    
    /// Whether to show the error alert
    @Published var showingError: Bool = false
    
    /// Whether to show the success alert
    @Published var showingSuccess: Bool = false
    
    /// Whether bundle generation is in progress
    @Published var isGenerating: Bool = false
    
    /// Progress of bundle generation (0.0 to 1.0)
    @Published var generationProgress: Double = 0.0
    
    /// Status message for bundle generation
    @Published var generationStatus: String = ""
    
    // MARK: - Properties
    
    /// The configuration manager
    let configurationManager: ConfigurationManagerProtocol
    
    /// The app bundle generator
    private let bundleGenerator: AppBundleGeneratorProtocol
    
    /// Task for bundle generation (for cancellation support)
    private var generationTask: Task<Void, Never>?
    
    // MARK: - Initialization
    
    /// Initialize the view model
    /// - Parameters:
    ///   - configurationManager: The configuration manager to use
    ///   - bundleGenerator: The app bundle generator to use
    init(
        configurationManager: ConfigurationManagerProtocol,
        bundleGenerator: AppBundleGeneratorProtocol = AppBundleGenerator()
    ) {
        self.configurationManager = configurationManager
        self.bundleGenerator = bundleGenerator
        refresh()
    }
    
    // MARK: - Public Methods
    
    /// Refresh the list of configurations
    func refresh() {
        configurations = configurationManager.listConfigurations()
    }
    
    /// Delete a configuration
    /// - Parameter configuration: The configuration to delete
    func deleteConfiguration(_ configuration: ServerConfiguration) {
        os_log(.info, log: logger, "User deleting configuration: %{public}@", configuration.name)
        do {
            try configurationManager.deleteConfiguration(id: configuration.id)
            IconStorage.removeIcon(for: configuration.id)
            refresh()
            successMessage = "Configuration '\(configuration.name)' deleted successfully"
            showingSuccess = true
            os_log(.info, log: logger, "Successfully deleted configuration: %{public}@", configuration.name)
        } catch {
            os_log(.error, log: logger, "Failed to delete configuration '%{public}@': %{public}@", configuration.name, error.localizedDescription)
            errorMessage = "Failed to delete configuration: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    /// Directory where run bundles are stored in the app library
    private static var bundlesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LocalServerWrapper/Bundles")
    }
    
    /// Ensure the bundles directory exists
    private func ensureBundlesDirectory() throws {
        let dir = Self.bundlesDirectory
        if !FileManager.default.fileExists(atPath: dir.path) {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
    }
    
    /// Generate an app bundle and save it to a user-chosen location (default: /Applications)
    /// - Parameter configuration: The configuration to generate a bundle for
    func generateAppBundle(for configuration: ServerConfiguration) {
        os_log(.info, log: logger, "User initiating standalone app bundle generation for: %{public}@", configuration.name)
        
        let savePanel = NSSavePanel()
        savePanel.title = "Use as Standalone App"
        savePanel.message = "Choose where to save the standalone app bundle"
        savePanel.nameFieldStringValue = "\(configuration.name).app"
        savePanel.directoryURL = URL(fileURLWithPath: "/Applications")
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.allowedContentTypes = [.applicationBundle]
        
        savePanel.begin { [weak self] response in
            guard let self = self else { return }
            
            if response == .OK, let outputURL = savePanel.url {
                os_log(.debug, log: logger, "User selected output location: %{public}@", outputURL.path)
                let outputDirectory = outputURL.deletingLastPathComponent()
                
                self.generationTask = Task {
                    await self.performGeneration(
                        configuration: configuration,
                        outputDirectory: outputDirectory,
                        onSuccess: { bundleURL in
                            self.sendSuccessNotification(configurationName: configuration.name)
                            NSWorkspace.shared.selectFile(bundleURL.path, inFileViewerRootedAtPath: "")
                        }
                    )
                }
            } else {
                os_log(.info, log: logger, "User cancelled standalone app bundle generation")
            }
        }
    }
    
    /// Cancel the current bundle generation
    func cancelGeneration() {
        os_log(.info, log: logger, "User cancelling bundle generation")
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
        generationProgress = 0.0
        generationStatus = "Cancelled"
    }
    
    /// Run a configuration by generating an app bundle in the library and launching it.
    /// Skips regeneration if the configuration hasn't changed since the last run.
    /// - Parameter configuration: The configuration to run
    func run(configuration: ServerConfiguration) {
        os_log(.info, log: logger, "User initiating run for: %{public}@", configuration.name)
        
        let currentHash = configHash(configuration)
        let storedHash = UserDefaults.standard.string(forKey: hashKey(for: configuration.id))
        let bundleURL = Self.bundlesDirectory.appendingPathComponent("\(sanitizeForBundleName(configuration.name)).app")
        
        if currentHash == storedHash, FileManager.default.fileExists(atPath: bundleURL.path) {
            os_log(.info, log: logger, "Configuration unchanged, launching existing bundle: %{public}@", bundleURL.path)
            let config = NSWorkspace.OpenConfiguration()
            NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, error in
                if let error = error {
                    os_log(.error, log: logger, "Failed to launch bundle: %{public}@", error.localizedDescription)
                }
            }
            return
        }
        
        do {
            try ensureBundlesDirectory()
        } catch {
            os_log(.error, log: logger, "Failed to create bundles directory: %{public}@", error.localizedDescription)
            errorMessage = "Failed to create bundles directory: \(error.localizedDescription)"
            showingError = true
            return
        }
        
        generationTask = Task {
            await performGeneration(
                configuration: configuration,
                outputDirectory: Self.bundlesDirectory,
                onSuccess: { bundleURL in
                    UserDefaults.standard.set(currentHash, forKey: self.hashKey(for: configuration.id))
                    self.sendSuccessNotification(configurationName: configuration.name)
                    let config = NSWorkspace.OpenConfiguration()
                    NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, error in
                        if let error = error {
                            os_log(.error, log: logger, "Failed to launch bundle: %{public}@", error.localizedDescription)
                        }
                    }
                }
            )
        }
    }
    
    // MARK: - Private Methods
    
    /// Compute a SHA256 hash of a configuration to detect changes
    private func configHash(_ config: ServerConfiguration) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(config) else { return "" }
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// UserDefaults key for storing the last-generated hash of a configuration
    private func hashKey(for configId: UUID) -> String {
        "generated_config_hash_\(configId.uuidString)"
    }
    
    /// Sanitize a name for use as a bundle filename
    private func sanitizeForBundleName(_ name: String) -> String {
        let invalidCharacters = CharacterSet(charactersIn: ":/\\?%*|\"<>")
        let components = name.components(separatedBy: invalidCharacters)
        let sanitized = components.joined(separator: "_")
        let trimmed = sanitized.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? "ServerApp" : trimmed
    }
    
    /// Send a system notification for successful bundle generation
    private func sendSuccessNotification(configurationName: String) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Bundle Ready"
            content.body = "\"\(configurationName)\" app bundle generated successfully."
            content.sound = .default
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    /// Perform the actual bundle generation
    /// - Parameters:
    ///   - configuration: The configuration to generate a bundle for
    ///   - outputDirectory: The directory where the bundle should be created
    ///   - onSuccess: Optional closure called with the generated bundle URL on success
    private func performGeneration(
        configuration: ServerConfiguration,
        outputDirectory: URL,
        onSuccess: ((URL) -> Void)? = nil
    ) async {
        os_log(.info, log: logger, "Starting bundle generation for: %{public}@", configuration.name)
        
        // Reset state
        isGenerating = true
        generationProgress = 0.0
        generationStatus = "Starting..."
        
        do {
            // Generate the bundle with progress tracking
            let bundleURL = try await bundleGenerator.generate(
                configuration: configuration,
                outputPath: outputDirectory,
                progressHandler: { [weak self] progress, status in
                    Task { @MainActor in
                        self?.generationProgress = progress
                        self?.generationStatus = status
                    }
                }
            )
            
            // Success!
            isGenerating = false
            generationTask = nil
            os_log(.info, log: logger, "Bundle generation completed successfully: %{public}@", bundleURL.path)

            onSuccess?(bundleURL)
            
        } catch is CancellationError {
            // Handle cancellation
            isGenerating = false
            generationTask = nil
            os_log(.info, log: logger, "Bundle generation was cancelled by user")
            // Don't show error for user-initiated cancellation
            
        } catch let error as GenerationError {
            // Handle generation-specific errors
            isGenerating = false
            generationTask = nil
            errorMessage = formatGenerationError(error)
            showingError = true
            os_log(.error, log: logger, "Bundle generation failed: %{public}@", error.localizedDescription)
            
        } catch {
            // Handle unexpected errors
            isGenerating = false
            generationTask = nil
            errorMessage = "Failed to generate app bundle: \(error.localizedDescription)"
            showingError = true
            os_log(.error, log: logger, "Bundle generation failed with unexpected error: %{public}@", error.localizedDescription)
        }
    }
    
    /// Format a generation error into a user-friendly message
    /// - Parameter error: The generation error
    /// - Returns: A formatted error message
    private func formatGenerationError(_ error: GenerationError) -> String {
        switch error {
        case .invalidOutputPath:
            return "The selected output location is invalid. Please choose a different location."
            
        case .bundleCreationFailed(let details):
            return "Failed to create app bundle structure:\n\(details)"
            
        case .resourceCopyFailed(let details):
            return "Failed to copy resources to app bundle:\n\(details)"
            
        case .signingFailed(let details):
            return "Failed to sign app bundle:\n\(details)"
            
        case .configurationEmbedFailed(let details):
            return "Failed to embed configuration in app bundle:\n\(details)"
        }
    }
}

