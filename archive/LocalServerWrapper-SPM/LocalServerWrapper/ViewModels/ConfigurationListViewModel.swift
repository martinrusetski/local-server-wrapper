//
//  ConfigurationListViewModel.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import Foundation
import SwiftUI
import AppKit

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
        do {
            try configurationManager.deleteConfiguration(id: configuration.id)
            refresh()
            successMessage = "Configuration '\(configuration.name)' deleted successfully"
            showingSuccess = true
        } catch {
            errorMessage = "Failed to delete configuration: \(error.localizedDescription)"
            showingError = true
        }
    }
    
    /// Generate an app bundle for a configuration
    /// - Parameter configuration: The configuration to generate a bundle for
    func generateAppBundle(for configuration: ServerConfiguration) {
        // Show file picker to select output location
        let savePanel = NSSavePanel()
        savePanel.title = "Save App Bundle"
        savePanel.message = "Choose where to save the generated app bundle"
        savePanel.nameFieldStringValue = "\(configuration.name).app"
        savePanel.canCreateDirectories = true
        savePanel.showsTagField = false
        savePanel.allowedContentTypes = [.applicationBundle]
        
        savePanel.begin { [weak self] response in
            guard let self = self else { return }
            
            if response == .OK, let outputURL = savePanel.url {
                // Get the directory (remove the .app filename)
                let outputDirectory = outputURL.deletingLastPathComponent()
                
                // Start generation
                Task {
                    await self.performGeneration(
                        configuration: configuration,
                        outputDirectory: outputDirectory
                    )
                }
            }
        }
    }
    
    // MARK: - Private Methods
    
    /// Perform the actual bundle generation
    /// - Parameters:
    ///   - configuration: The configuration to generate a bundle for
    ///   - outputDirectory: The directory where the bundle should be created
    private func performGeneration(
        configuration: ServerConfiguration,
        outputDirectory: URL
    ) async {
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
            successMessage = "App bundle generated successfully at:\n\(bundleURL.path)"
            showingSuccess = true
            
            // Optionally reveal in Finder
            NSWorkspace.shared.selectFile(bundleURL.path, inFileViewerRootedAtPath: "")
            
        } catch let error as GenerationError {
            // Handle generation-specific errors
            isGenerating = false
            errorMessage = formatGenerationError(error)
            showingError = true
            
        } catch {
            // Handle unexpected errors
            isGenerating = false
            errorMessage = "Failed to generate app bundle: \(error.localizedDescription)"
            showingError = true
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

