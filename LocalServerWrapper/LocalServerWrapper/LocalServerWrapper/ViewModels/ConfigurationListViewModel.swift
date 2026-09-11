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

/// Visible per-app state for generation and export work in the one-pane library.
enum AppBundleOperationState: Equatable {
    case idle
    case generating(progress: Double, status: String)
    case succeeded(URL)
    case failed(String)
}

/// View model for the configuration list view
@MainActor
class ConfigurationListViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// The list of configurations
    @Published var configurations: [ServerConfiguration] = []
    
    /// Error message to display
    @Published var errorMessage: String?
    
    /// Whether to show the error alert
    @Published var showingError: Bool = false

    /// Inline generation state keyed by the app setup being operated on.
    @Published private(set) var operationStates: [UUID: AppBundleOperationState] = [:]

    /// Last exported bundle paths that still exist on disk.
    @Published private(set) var exportedBundleURLs: [UUID: URL] = [:]
    
    // MARK: - Properties
    
    /// The configuration manager
    let configurationManager: ConfigurationManagerProtocol
    
    /// The app bundle generator
    private let bundleGenerator: AppBundleGeneratorProtocol
    
    /// Active work keyed by configuration so progress and cancellation stay attached to one row.
    private var operationTasks: [UUID: Task<Void, Never>] = [:]
    private var operationTokens: [UUID: UUID] = [:]
    
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
        if let loadError = configurationManager.loadError {
            errorMessage = loadError
            showingError = true
            return
        }
        refreshExportedBundleURLs()
    }

    /// Refresh after an editor save, then update the existing user-exported app in place. New app
    /// setups have no exported path yet, so saving them only refreshes the library.
    func configurationDidSave(_ configurationID: UUID) {
        refresh()

        guard let configuration = configurations.first(where: { $0.id == configurationID }),
              let destinationURL = validExportedBundleURL(for: configurationID) else { return }

        regenerateExportedApp(configuration, at: destinationURL)
    }
    
    /// Delete a configuration
    /// - Parameter configuration: The configuration to delete
    func deleteConfiguration(_ configuration: ServerConfiguration) {
        os_log(.info, log: logger, "User deleting configuration: %{public}@", configuration.name)
        do {
            try configurationManager.deleteConfiguration(id: configuration.id)
            IconStorage.removeIcon(for: configuration.id)
            removeCanonicalBundle(for: configuration.id)
            removeExportedBundleReference(for: configuration.id)
            operationStates.removeValue(forKey: configuration.id)
            refresh()
            os_log(.info, log: logger, "Successfully deleted configuration: %{public}@", configuration.name)
        } catch {
            os_log(.error, log: logger, "Failed to delete configuration '%{public}@': %{public}@", configuration.name, error.localizedDescription)
            errorMessage = "Failed to delete configuration: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    /// Directory where run bundles are stored in the app library
    static var bundlesDirectory: URL {
        let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        return appSupport.appendingPathComponent("LocalServerWrapper/Bundles")
    }
    
    /// Generate and export a standalone copy of the app bundle to a user-chosen location.
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
        savePanel.title = "Generate App"
        savePanel.message = "Choose where to save the generated app"
        savePanel.prompt = "Generate"
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

            self.startOperation(for: configuration.id) {
                self.operationStates[configuration.id] = .generating(
                    progress: 0,
                    status: "Generating…"
                )
                do {
                    let canonicalURL = try await self.ensureCanonicalBundle(for: configuration)
                    try self.exportCopy(of: canonicalURL, to: destinationURL)
                    self.rememberExportedBundle(destinationURL, for: configuration.id)
                    self.operationStates[configuration.id] = .succeeded(destinationURL)
                    self.sendSuccessNotification(configurationName: configuration.name, bundleURL: destinationURL)
                    os_log(.info, log: logger, "Exported standalone app to: %{public}@", destinationURL.path)
                } catch is CancellationError {
                    self.operationStates[configuration.id] = .idle
                    os_log(.info, log: logger, "Standalone app export was cancelled")
                } catch {
                    self.operationStates[configuration.id] = .failed(self.formatBundleError(error))
                    os_log(.error, log: logger, "Bundle export failed: %{public}@", error.localizedDescription)
                }
            }
        }
    }

    func operationState(for configurationID: UUID) -> AppBundleOperationState {
        operationStates[configurationID] ?? .idle
    }

    func exportedBundleURL(for configurationID: UUID) -> URL? {
        exportedBundleURLs[configurationID]
    }

    /// Cancel generation for one app without disturbing another row's state.
    func cancelGeneration(for configurationID: UUID) {
        os_log(.info, log: logger, "User cancelling bundle generation")
        operationTasks[configurationID]?.cancel()
        operationTasks[configurationID] = nil
        operationTokens[configurationID] = nil
        operationStates[configurationID] = .idle
    }

    /// Secondary validation action. It launches the internal canonical bundle, not an exported copy.
    func testLaunch(configuration: ServerConfiguration) {
        os_log(.info, log: logger, "User initiating test launch for: %{public}@", configuration.name)

        startOperation(for: configuration.id) {
            self.operationStates[configuration.id] = .generating(
                progress: 0,
                status: "Preparing test…"
            )
            do {
                let bundleURL = try await self.ensureCanonicalBundle(for: configuration)
                self.operationStates[configuration.id] = .idle
                self.launchBundle(at: bundleURL)
            } catch is CancellationError {
                self.operationStates[configuration.id] = .idle
                os_log(.info, log: logger, "Test launch was cancelled during bundle generation")
            } catch {
                self.operationStates[configuration.id] = .failed(self.formatBundleError(error))
                os_log(.error, log: logger, "Test launch failed: %{public}@", error.localizedDescription)
            }
        }
    }

    /// Open the last user-exported bundle. This never generates an internal substitute.
    func openExportedApp(for configuration: ServerConfiguration) {
        guard let bundleURL = validExportedBundleURL(for: configuration.id) else {
            presentMissingExportedBundle(for: configuration)
            return
        }
        launchBundle(at: bundleURL)
    }

    func revealExportedApp(for configuration: ServerConfiguration) {
        guard let bundleURL = validExportedBundleURL(for: configuration.id) else {
            presentMissingExportedBundle(for: configuration)
            return
        }
        NSWorkspace.shared.activateFileViewerSelecting([bundleURL])
    }

    /// Regenerate the last user-exported copy at the same path, without asking for a destination.
    func regenerateExportedApp(for configuration: ServerConfiguration) {
        guard let destinationURL = validExportedBundleURL(for: configuration.id) else {
            presentMissingExportedBundle(for: configuration)
            return
        }
        regenerateExportedApp(configuration, at: destinationURL)
    }
    
    // MARK: - Private Methods
    
    /// Compute a SHA256 hash of a configuration to detect changes
    private func configHash(_ config: ServerConfiguration) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .sortedKeys
        encoder.dateEncodingStrategy = .iso8601
        guard var data = try? encoder.encode(config) else { return "" }
        // A manager update ships a new runtime even when the configuration is unchanged.
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? ""
        let version = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? ""
        data.append(Data("\n\(version):\(build)".utf8))
        return SHA256.hash(data: data).compactMap { String(format: "%02x", $0) }.joined()
    }
    
    /// UserDefaults key for storing the last-generated hash of a configuration
    private func hashKey(for configId: UUID) -> String {
        "generated_config_hash_\(configId.uuidString)"
    }

    private func exportedBundlePathKey(for configId: UUID) -> String {
        "exported_bundle_path_\(configId.uuidString)"
    }

    private func startOperation(
        for configurationID: UUID,
        operation: @escaping @MainActor () async -> Void
    ) {
        operationTasks[configurationID]?.cancel()
        let token = UUID()
        operationTokens[configurationID] = token
        let task = Task { [weak self] in
            await operation()
            guard self?.operationTokens[configurationID] == token else { return }
            self?.operationTasks[configurationID] = nil
            self?.operationTokens[configurationID] = nil
        }
        operationTasks[configurationID] = task
    }

    private func regenerateExportedApp(_ configuration: ServerConfiguration, at destinationURL: URL) {
        os_log(.info, log: logger, "Regenerating exported app after configuration save: %{public}@", configuration.name)

        startOperation(for: configuration.id) {
            self.operationStates[configuration.id] = .generating(
                progress: 0,
                status: "Updating app…"
            )
            do {
                let canonicalURL = try await self.ensureCanonicalBundle(for: configuration)
                try self.exportCopy(of: canonicalURL, to: destinationURL)
                self.rememberExportedBundle(destinationURL, for: configuration.id)
                self.operationStates[configuration.id] = .succeeded(destinationURL)
                os_log(.info, log: logger, "Regenerated exported app at: %{public}@", destinationURL.path)
            } catch is CancellationError {
                self.operationStates[configuration.id] = .idle
                os_log(.info, log: logger, "Exported app regeneration was cancelled")
            } catch {
                self.operationStates[configuration.id] = .failed(self.formatBundleError(error))
                os_log(.error, log: logger, "Exported app regeneration failed: %{public}@", error.localizedDescription)
            }
        }
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
            content.title = "App Ready"
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
    /// reused. This is the single source of truth shared by Test Launch and Generate App.
    /// - Parameter configuration: The configuration whose bundle is needed
    /// - Returns: The URL of the up-to-date canonical bundle
    /// - Throws: GenerationError or CancellationError if generation fails or is cancelled
    func ensureCanonicalBundle(for configuration: ServerConfiguration) async throws -> URL {
        let currentHash = configHash(configuration)
        let storedHash = UserDefaults.standard.string(forKey: hashKey(for: configuration.id))
        let directory = Self.bundlesDirectory.appendingPathComponent(configuration.id.uuidString, isDirectory: true)
        let bundleURL = directory.appendingPathComponent("\(sanitizeForBundleName(configuration.name)).app")

        if currentHash == storedHash, FileManager.default.fileExists(atPath: bundleURL.path) {
            os_log(.info, log: logger, "Configuration unchanged, reusing existing bundle: %{public}@", bundleURL.path)
            return bundleURL
        }

        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        os_log(.info, log: logger, "Generating canonical bundle for: %{public}@", configuration.name)
        let generatedURL = try await bundleGenerator.generate(
            configuration: configuration,
            outputPath: directory,
            progressHandler: { [weak self] progress, status in
                Task { @MainActor in
                    guard let self,
                          let state = self.operationStates[configuration.id],
                          case .generating = state else { return }
                    self.operationStates[configuration.id] = .generating(
                        progress: progress,
                        status: status
                    )
                }
            }
        )

        // A rename changes both the bundle filename and the hash, so without this the bundles
        // directory would accumulate an orphan under the old name. Remove the previous canonical
        // bundle when the path has changed.
        let pathKey = bundlePathKey(for: configuration.id)
        if let oldPath = UserDefaults.standard.string(forKey: pathKey), oldPath != generatedURL.path,
           URL(fileURLWithPath: oldPath).deletingLastPathComponent().path == directory.path {
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
    /// The replacement is staged beside the destination first, so a failed copy leaves the user's
    /// currently generated app intact. `copyItem` preserves the ad-hoc signature and cleared
    /// quarantine state, so the copy remains an exact, same-identity duplicate of the original.
    private func exportCopy(of source: URL, to destination: URL) throws {
        let fileManager = FileManager.default
        let stagedURL = destination
            .deletingLastPathComponent()
            .appendingPathComponent(".\(destination.lastPathComponent).\(UUID().uuidString).staged")

        defer {
            if fileManager.fileExists(atPath: stagedURL.path) {
                try? fileManager.removeItem(at: stagedURL)
            }
        }

        try fileManager.copyItem(at: source, to: stagedURL)

        if fileManager.fileExists(atPath: destination.path) {
            _ = try fileManager.replaceItemAt(destination, withItemAt: stagedURL)
        } else {
            try fileManager.moveItem(at: stagedURL, to: destination)
        }
    }

    /// Remove a configuration's canonical bundle and its bookkeeping keys (called on delete).
    private func removeCanonicalBundle(for configId: UUID) {
        let pathKey = bundlePathKey(for: configId)
        if let path = UserDefaults.standard.string(forKey: pathKey),
           URL(fileURLWithPath: path).deletingLastPathComponent().lastPathComponent == configId.uuidString {
            try? FileManager.default.removeItem(atPath: path)
            os_log(.info, log: logger, "Removed canonical bundle for deleted configuration: %{public}@", path)
        }
        UserDefaults.standard.removeObject(forKey: pathKey)
        UserDefaults.standard.removeObject(forKey: hashKey(for: configId))
    }

    private func rememberExportedBundle(_ url: URL, for configurationID: UUID) {
        UserDefaults.standard.set(url.path, forKey: exportedBundlePathKey(for: configurationID))
        exportedBundleURLs[configurationID] = url
    }

    private func removeExportedBundleReference(for configurationID: UUID) {
        exportedBundleURLs.removeValue(forKey: configurationID)
        UserDefaults.standard.removeObject(forKey: exportedBundlePathKey(for: configurationID))
    }

    private func refreshExportedBundleURLs() {
        let validIDs = Set(configurations.map(\.id))
        exportedBundleURLs = validIDs.reduce(into: [:]) { result, configurationID in
            let key = exportedBundlePathKey(for: configurationID)
            guard let path = UserDefaults.standard.string(forKey: key),
                  FileManager.default.fileExists(atPath: path) else {
                UserDefaults.standard.removeObject(forKey: key)
                return
            }
            result[configurationID] = URL(fileURLWithPath: path)
        }
    }

    private func validExportedBundleURL(for configurationID: UUID) -> URL? {
        guard let url = exportedBundleURLs[configurationID],
              FileManager.default.fileExists(atPath: url.path) else {
            removeExportedBundleReference(for: configurationID)
            return nil
        }
        return url
    }

    private func presentMissingExportedBundle(for configuration: ServerConfiguration) {
        errorMessage = "The generated copy of ‘\(configuration.name)’ could not be found. Generate the app again to choose a new location."
        showingError = true
    }

    private func formatBundleError(_ error: Error) -> String {
        if let generationError = error as? GenerationError {
            return formatGenerationError(generationError)
        }
        return "Failed to prepare app bundle: \(error.localizedDescription)"
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
