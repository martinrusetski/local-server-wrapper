//
//  ConfigurationListView.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import SwiftUI

/// Identifies which sheet to present: new or edit
enum ConfigurationSheet: Identifiable {
    case new
    case edit(ServerConfiguration)
    
    var id: String {
        switch self {
        case .new: return "new"
        case .edit(let config): return config.id.uuidString
        }
    }
    
    var editingConfig: ServerConfiguration? {
        switch self {
        case .new: return nil
        case .edit(let config): return config
        }
    }
}

/// Main view displaying the list of server configurations
struct ConfigurationListView: View {
    // MARK: - Properties
    
    /// The configuration manager instance
    @StateObject private var viewModel: ConfigurationListViewModel
    
    /// Search text for filtering configurations
    @State private var searchText = ""
    
    /// The active configuration sheet (nil when no sheet is presented)
    @State private var activeSheet: ConfigurationSheet?
    
    /// Whether the delete confirmation alert is shown
    @State private var showingDeleteAlert = false
    
    /// The configuration to delete
    @State private var configurationToDelete: ServerConfiguration?
    
    /// The currently selected configuration
    @State private var selectedConfiguration: ServerConfiguration?
    
    // MARK: - Initialization
    
    init(configurationManager: ConfigurationManager = ConfigurationManager()) {
        _viewModel = StateObject(wrappedValue: ConfigurationListViewModel(configurationManager: configurationManager))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
        }
        .sheet(item: $activeSheet) { sheet in
            ConfigurationEditorView(
                configurationManager: viewModel.configurationManager,
                editingConfiguration: sheet.editingConfig,
                onSave: {
                    viewModel.refresh()
                    if case .edit(let config) = sheet {
                        selectedConfiguration = viewModel.configurations.first(where: { $0.id == config.id })
                    }
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
                    status: viewModel.generationStatus,
                    onCancel: {
                        viewModel.cancelGeneration()
                    }
                )
            }
        }
    }
    
    // MARK: - Sidebar Content
    
    private var sidebarContent: some View {
        VStack(spacing: 0) {
            List(filteredConfigurations, selection: $selectedConfiguration) { config in
                ConfigurationRowView(configuration: config)
                    .tag(config)
                    .contextMenu {
                        Button("Edit") {
                            activeSheet = .edit(config)
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
            }
            .searchable(text: $searchText, prompt: "Search configurations")
            .navigationTitle("Server Configurations")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeSheet = .new
                    } label: {
                        Label("New Configuration", systemImage: "plus")
                    }
                    .keyboardShortcut("n", modifiers: .command)
                }
                
                ToolbarItem(placement: .automatic) {
                    Button {
                        viewModel.refresh()
                    } label: {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: .command)
                }
            }
        }
    }
    
    // MARK: - Detail Content
    
    private var detailContent: some View {
        Group {
            if let config = selectedConfiguration {
                ConfigurationDetailView(
                    configuration: config,
                    onEdit: {
                        activeSheet = .edit(config)
                    },
                    onGenerate: {
                        viewModel.generateAppBundle(for: config)
                    },
                    onDelete: {
                        configurationToDelete = config
                        showingDeleteAlert = true
                    }
                )
            } else if viewModel.configurations.isEmpty {
                EmptyStateView {
                    activeSheet = .new
                }
            } else {
                Text("Select a configuration to view details")
                    .foregroundColor(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
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
            .accessibilityLabel("Create New Configuration")
            .accessibilityHint("Opens the configuration editor to create your first server configuration")
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
    let onCancel: () -> Void
    
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
                
                // Cancel button
                Button("Cancel") {
                    onCancel()
                }
                .buttonStyle(.bordered)
                .controlSize(.large)
                .keyboardShortcut(.cancelAction)
                .accessibilityLabel("Cancel generation")
                .accessibilityHint("Stop the app bundle generation process")
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

// MARK: - Configuration Detail View

/// View displaying details of a selected configuration
struct ConfigurationDetailView: View {
    let configuration: ServerConfiguration
    let onEdit: () -> Void
    let onGenerate: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                // Header with icon and name
                HStack(spacing: 16) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 48))
                        .foregroundColor(.blue)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(configuration.name)
                            .font(.title)
                            .fontWeight(.bold)
                        
                        Text("Server Configuration")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    
                    Spacer()
                }
                .padding(.bottom, 8)
                
                Divider()
                
                // Command Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Command", systemImage: "terminal")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "Executable", value: configuration.command)
                        
                        if !configuration.arguments.isEmpty {
                            DetailRow(label: "Arguments", value: configuration.arguments.joined(separator: " "))
                        }
                    }
                    .padding(.leading, 28)
                }
                
                Divider()
                
                // Network Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Network", systemImage: "network")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if let url = configuration.localhostURL {
                            DetailRow(label: "Localhost URL", value: url)
                        } else {
                            Text("No URL configured")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 28)
                        }
                    }
                    .padding(.leading, 28)
                }
                
                Divider()
                
                // Detection Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Detection", systemImage: "magnifyingglass")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if let pattern = configuration.readySignalPattern, !pattern.isEmpty {
                            DetailRow(label: "Ready Signal", value: pattern)
                        } else {
                            Text("No ready signal pattern")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 28)
                        }
                        
                        if let pattern = configuration.portDetectionPattern, !pattern.isEmpty {
                            DetailRow(label: "Port Detection", value: pattern)
                        } else {
                            Text("No port detection pattern")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 28)
                        }
                    }
                    .padding(.leading, 28)
                }
                
                Divider()
                
                // Appearance Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Appearance", systemImage: "paintbrush")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        if let iconPath = configuration.customIconPath, !iconPath.isEmpty {
                            DetailRow(label: "Custom Icon", value: iconPath)
                        } else {
                            Text("Using default icon")
                                .font(.caption)
                                .foregroundColor(.secondary)
                                .padding(.leading, 28)
                        }
                    }
                    .padding(.leading, 28)
                }
                
                Divider()
                
                // Metadata Section
                VStack(alignment: .leading, spacing: 12) {
                    Label("Metadata", systemImage: "info.circle")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 8) {
                        DetailRow(label: "Created", value: formatDate(configuration.createdAt))
                        DetailRow(label: "Updated", value: formatDate(configuration.updatedAt))
                        DetailRow(label: "ID", value: configuration.id.uuidString)
                    }
                    .padding(.leading, 28)
                }
                
                Spacer()
                
                // Action Buttons
                VStack(spacing: 12) {
                    Button(action: onGenerate) {
                        HStack {
                            Image(systemName: "app.badge")
                            Text("Generate App Bundle")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    HStack(spacing: 12) {
                        Button(action: onEdit) {
                            HStack {
                                Image(systemName: "pencil")
                                Text("Edit")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        
                        Button(action: onDelete) {
                            HStack {
                                Image(systemName: "trash")
                                Text("Delete")
                            }
                            .frame(maxWidth: .infinity)
                        }
                        .buttonStyle(.bordered)
                        .controlSize(.large)
                        .tint(.red)
                    }
                }
            }
            .padding(24)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(nsColor: .controlBackgroundColor))
    }
    
    private func formatDate(_ date: Date) -> String {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter.string(from: date)
    }
}

// MARK: - Detail Row

/// A row displaying a label and value in the detail view
struct DetailRow: View {
    let label: String
    let value: String
    
    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(.secondary)
            
            Text(value)
                .font(.body)
                .textSelection(.enabled)
        }
    }
}

// MARK: - Preview

#Preview {
    ConfigurationListView()
}

