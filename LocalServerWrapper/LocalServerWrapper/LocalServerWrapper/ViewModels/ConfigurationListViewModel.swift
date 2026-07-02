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
            removeCanonicalBundle(for: configuration.id)
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
    
    /// Export a standalone copy of the configuration's app bundle to a user-chosen location
    /// (default: /Applications).
    ///
    /// This is a *copy* of the same canonical bundle the Run button launches — not a second,
    /// independent generation. Because the copy keeps the original's ad-hoc signature (identical
    /// cdhash) and bundle identifier (derived from the configuration id), it shares the same live
    /// config, UserDefaults state, and Keychain credentials as the Run bundle, and Gatekeeper treats
    /// the two as the same app.
    /// - Parameter configuration: The configuration to export
    func exportStandaloneApp(for configuration: ServerConfiguration) {
        os_log(.info, log: logger, "User initiating standalone app export for: %{public}@", configuration.name)

        let savePanel = NSSavePanel()
        savePanel.title = "Use as Standalone App"
        savePanel.message = "Choose where to save the standalone app"
        savePanel.nameFieldStringValue = "\(configuration.name).app"
        savePanel.directoryURL = URL(fileURLWithPath: "/Applications")
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.allowedContentTypes = [.applicationBundle]

        savePanel.begin { [weak self] response in
            guard let self = self else { return }

            guard response == .OK, let destinationURL = savePanel.url else {
                os_log(.info, log: logger, "User cancelled standalone app export")
                return
            }

            os_log(.debug, log: logger, "User selected export location: %{public}@", destinationURL.path)

            self.generationTask = Task {
                defer { self.generationTask = nil }
                do {
                    let canonicalURL = try await self.ensureCanonicalBundle(for: configuration)
                    try self.exportCopy(of: canonicalURL, to: destinationURL)
                    self.sendSuccessNotification(configurationName: configuration.name, bundleURL: destinationURL)
                    os_log(.info, log: logger, "Exported standalone app to: %{public}@", destinationURL.path)
                } catch is CancellationError {
                    os_log(.info, log: logger, "Standalone app export was cancelled")
                } catch {
                    self.presentBundleError(error)
                }
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
    
    /// Run a configuration by ensuring its canonical app bundle is current and launching it.
    /// The bundle is generated lazily on first run (or after a change that affects generation) and
    /// reused otherwise; "Use as standalone app" exports a copy of this same bundle.
    /// - Parameter configuration: The configuration to run
    func run(configuration: ServerConfiguration) {
        os_log(.info, log: logger, "User initiating run for: %{public}@", configuration.name)

        generationTask = Task {
            defer { generationTask = nil }
            do {
                let bundleURL = try await ensureCanonicalBundle(for: configuration)
                launchBundle(at: bundleURL)
            } catch is CancellationError {
                os_log(.info, log: logger, "Run was cancelled during bundle generation")
            } catch {
                presentBundleError(error)
            }
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
    
    /// Send a system notification for a successful standalone export.
    /// Clicking the notification reveals the bundle in Finder (handled by AppDelegate).
    private func sendSuccessNotification(configurationName: String, bundleURL: URL) {
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { granted, _ in
            guard granted else { return }
            let content = UNMutableNotificationContent()
            content.title = "Standalone App Ready"
            content.body = "\"\(configurationName)\" was saved. Click to reveal in Finder."
            content.sound = .default
            content.userInfo = [AppDelegate.bundlePathUserInfoKey: bundleURL.path]
            let request = UNNotificationRequest(
                identifier: UUID().uuidString,
                content: content,
                trigger: nil
            )
            UNUserNotificationCenter.current().add(request)
        }
    }
    
    /// UserDefaults key for storing the path of the last-generated canonical bundle of a configuration
    private func bundlePathKey(for configId: UUID) -> String {
        "generated_bundle_path_\(configId.uuidString)"
    }

    /// Ensure the configuration's canonical app bundle exists and is current in the bundles
    /// directory, then return its URL. Regenerates only when the configuration changed in a way that
    /// affects generation (hash mismatch) or the bundle is missing; otherwise the existing bundle is
    /// reused. This is the single source of truth shared by Run (which launches it) and
    /// "Use as standalone app" (which copies it).
    /// - Parameter configuration: The configuration whose bundle is needed
    /// - Returns: The URL of the up-to-date canonical bundle
    /// - Throws: GenerationError or CancellationError if generation fails or is cancelled
    private func ensureCanonicalBundle(for configuration: ServerConfiguration) async throws -> URL {
        let currentHash = configHash(configuration)
        let storedHash = UserDefaults.standard.string(forKey: hashKey(for: configuration.id))
        let bundleURL = Self.bundlesDirectory.appendingPathComponent("\(sanitizeForBundleName(configuration.name)).app")

        if currentHash == storedHash, FileManager.default.fileExists(atPath: bundleURL.path) {
            os_log(.info, log: logger, "Configuration unchanged, reusing existing bundle: %{public}@", bundleURL.path)
            return bundleURL
        }

        try ensureBundlesDirectory()

        isGenerating = true
        generationProgress = 0.0
        generationStatus = "Starting..."
        defer { isGenerating = false }

        os_log(.info, log: logger, "Generating canonical bundle for: %{public}@", configuration.name)
        let generatedURL = try await bundleGenerator.generate(
            configuration: configuration,
            outputPath: Self.bundlesDirectory,
            progressHandler: { [weak self] progress, status in
                Task { @MainActor in
                    self?.generationProgress = progress
                    self?.generationStatus = status
                }
            }
        )

        // A rename changes both the bundle filename and the hash, so without this the bundles
        // directory would accumulate an orphan under the old name. Remove the previous canonical
        // bundle when the path has changed.
        let pathKey = bundlePathKey(for: configuration.id)
        if let oldPath = UserDefaults.standard.string(forKey: pathKey), oldPath != generatedURL.path {
            try? FileManager.default.removeItem(atPath: oldPath)
        }
        UserDefaults.standard.set(generatedURL.path, forKey: pathKey)
        UserDefaults.standard.set(currentHash, forKey: hashKey(for: configuration.id))

        os_log(.info, log: logger, "Canonical bundle ready: %{public}@", generatedURL.path)
        return generatedURL
    }

    /// Launch an app bundle without blocking the main actor.
    private func launchBundle(at bundleURL: URL) {
        let config = NSWorkspace.OpenConfiguration()
        NSWorkspace.shared.openApplication(at: bundleURL, configuration: config) { _, error in
            if let error = error {
                os_log(.error, log: logger, "Failed to launch bundle: %{public}@", error.localizedDescription)
            }
        }
    }

    /// Copy the canonical bundle to a user-chosen destination, replacing any existing item there.
    /// `copyItem` preserves the ad-hoc signature and (already-cleared) quarantine state, so the copy
    /// is an exact, same-identity duplicate of the original.
    private func exportCopy(of source: URL, to destination: URL) throws {
        if FileManager.default.fileExists(atPath: destination.path) {
            try FileManager.default.removeItem(at: destination)
        }
        try FileManager.default.copyItem(at: source, to: destination)
    }

    /// Remove a configuration's canonical bundle and its bookkeeping keys (called on delete).
    private func removeCanonicalBundle(for configId: UUID) {
        let pathKey = bundlePathKey(for: configId)
        if let path = UserDefaults.standard.string(forKey: pathKey) {
            try? FileManager.default.removeItem(atPath: path)
            os_log(.info, log: logger, "Removed canonical bundle for deleted configuration: %{public}@", path)
        }
        UserDefaults.standard.removeObject(forKey: pathKey)
        UserDefaults.standard.removeObject(forKey: hashKey(for: configId))
    }

    /// Present a bundle generation/export error to the user.
    private func presentBundleError(_ error: Error) {
        if let generationError = error as? GenerationError {
            errorMessage = formatGenerationError(generationError)
        } else {
            errorMessage = "Failed to prepare app bundle: \(error.localizedDescription)"
        }
        showingError = true
        os_log(.error, log: logger, "Bundle operation failed: %{public}@", error.localizedDescription)
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

