//
//  ConfigurationListView.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import SwiftUI

/// Main view displaying the list of server configurations
struct ConfigurationListView: View {
    // MARK: - Properties
    
    /// The configuration manager instance
    @StateObject private var viewModel: ConfigurationListViewModel
    
    /// Search text for filtering configurations
    @State private var searchText = ""
    
    /// Whether the configuration editor sheet is presented
    @State private var showingEditor = false
    
    /// The configuration being edited (nil for new configuration)
    @State private var editingConfiguration: ServerConfiguration?
    
    /// Whether the delete confirmation alert is shown
    @State private var showingDeleteAlert = false
    
    /// The configuration to delete
    @State private var configurationToDelete: ServerConfiguration?
    
    // MARK: - Initialization
    
    init(configurationManager: ConfigurationManager = ConfigurationManager()) {
        _viewModel = StateObject(wrappedValue: ConfigurationListViewModel(configurationManager: configurationManager))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Configuration list
                List(filteredConfigurations) { config in
                    ConfigurationRowView(configuration: config)
                        .contextMenu {
                            Button("Edit") {
                                editingConfiguration = config
                                showingEditor = true
                            }
                            
                            Button("Generate App Bundle") {
                                viewModel.generateAppBundle(for: config)
                            }
                            
                            Divider()
                            
                            Button("Delete", role: .destructive) {
                                configurationToDelete = config
                                showingDeleteAlert = true
                            }
                        }
                        .swipeActions(edge: .trailing, allowsFullSwipe: false) {
                            Button(role: .destructive) {
                                configurationToDelete = config
                                showingDeleteAlert = true
                            } label: {
                                Label("Delete", systemImage: "trash")
                            }
                            
                            Button {
                                viewModel.generateAppBundle(for: config)
                            } label: {
                                Label("Generate", systemImage: "app.badge")
                            }
                            .tint(.blue)
                        }
                        .swipeActions(edge: .leading, allowsFullSwipe: false) {
                            Button {
                                editingConfiguration = config
                                showingEditor = true
                            } label: {
                                Label("Edit", systemImage: "pencil")
                            }
                            .tint(.orange)
                        }
                }
                .searchable(text: $searchText, prompt: "Search configurations")
                .navigationTitle("Server Configurations")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            editingConfiguration = nil
                            showingEditor = true
                        } label: {
                            Label("New Configuration", systemImage: "plus")
                        }
                    }
                    
                    ToolbarItem(placement: .automatic) {
                        Button {
                            viewModel.refresh()
                        } label: {
                            Label("Refresh", systemImage: "arrow.clockwise")
                        }
                    }
                }
            }
        } detail: {
            // Detail view (empty state or selected configuration details)
            if viewModel.configurations.isEmpty {
                EmptyStateView {
                    editingConfiguration = nil
                    showingEditor = true
                }
            } else {
                Text("Select a configuration to view details")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .sheet(isPresented: $showingEditor) {
            ConfigurationEditorView(
                configurationManager: viewModel.configurationManager,
                editingConfiguration: editingConfiguration,
                onSave: {
                    viewModel.refresh()
                }
            )
        }
        .alert("Delete Configuration", isPresented: $showingDeleteAlert, presenting: configurationToDelete) { config in
            Button("Cancel", role: .cancel) {
                configurationToDelete = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.deleteConfiguration(config)
                configurationToDelete = nil
            }
        } message: { config in
            Text("Are you sure you want to delete '\(config.name)'? This action cannot be undone.")
        }
        .alert("Error", isPresented: $viewModel.showingError) {
            Button("OK") {
                viewModel.errorMessage = nil
                viewModel.showingError = false
            }
        } message: {
            if let message = viewModel.errorMessage {
                Text(message)
            }
        }
        .alert("Success", isPresented: $viewModel.showingSuccess) {
            Button("OK") {
                viewModel.successMessage = nil
                viewModel.showingSuccess = false
            }
        } message: {
            if let message = viewModel.successMessage {
                Text(message)
            }
        }
        .overlay {
            if viewModel.isGenerating {
                GenerationProgressView(
                    progress: viewModel.generationProgress,
                    status: viewModel.generationStatus
                )
            }
        }
    }
    
    // MARK: - Computed Properties
    
    /// Filtered configurations based on search text
    private var filteredConfigurations: [ServerConfiguration] {
        if searchText.isEmpty {
            return viewModel.configurations
        } else {
            return viewModel.configurations.filter { config in
                config.name.localizedCaseInsensitiveContains(searchText) ||
                config.command.localizedCaseInsensitiveContains(searchText)
            }
        }
    }
}

// MARK: - Configuration Row View

/// View for a single configuration row in the list
struct ConfigurationRowView: View {
    let configuration: ServerConfiguration
    
    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(configuration.name)
                .font(.headline)
            
            HStack {
                Label(configuration.command, systemImage: "terminal")
                    .font(.caption)
                    .foregroundColor(.secondary)
                
                if !configuration.arguments.isEmpty {
                    Text(configuration.arguments.joined(separator: " "))
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                }
            }
            
            if let url = configuration.localhostURL {
                Label(url, systemImage: "network")
                    .font(.caption2)
                    .foregroundColor(.blue)
            }
        }
        .padding(.vertical, 4)
    }
}

// MARK: - Empty State View

/// View displayed when there are no configurations
struct EmptyStateView: View {
    let onCreateConfiguration: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            Image(systemName: "tray")
                .font(.system(size: 60))
                .foregroundColor(.secondary)
            
            Text("No Configurations")
                .font(.title2)
                .fontWeight(.semibold)
            
            Text("Create your first server configuration to get started")
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
            
            Button {
                onCreateConfiguration()
            } label: {
                Label("New Configuration", systemImage: "plus")
                    .font(.headline)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }
}

// MARK: - Generation Progress View

/// View displayed during app bundle generation
struct GenerationProgressView: View {
    let progress: Double
    let status: String
    
    var body: some View {
        ZStack {
            // Semi-transparent background
            Color.black.opacity(0.3)
                .ignoresSafeArea()
            
            // Progress card
            VStack(spacing: 20) {
                // Icon
                Image(systemName: "app.badge.checkmark")
                    .font(.system(size: 50))
                    .foregroundColor(.blue)
                
                // Title
                Text("Generating App Bundle")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                // Progress bar
                VStack(spacing: 8) {
                    ProgressView(value: progress, total: 1.0)
                        .progressViewStyle(.linear)
                        .frame(width: 300)
                    
                    // Status text
                    Text(status)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .frame(width: 300, alignment: .leading)
                    
                    // Percentage
                    Text("\(Int(progress * 100))%")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            .padding(40)
            .background(
                RoundedRectangle(cornerRadius: 16)
                    .fill(Color(nsColor: .windowBackgroundColor))
                    .shadow(radius: 20)
            )
        }
    }
}

// MARK: - Preview

#Preview {
    ConfigurationListView()
}

