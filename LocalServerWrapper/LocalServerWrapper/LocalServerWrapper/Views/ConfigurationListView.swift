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
    
    /// The open window action for test run windows
    @Environment(\.openWindow) private var openWindow
    
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
    
    init(configurationManager: ConfigurationManager) {
        _viewModel = StateObject(wrappedValue: ConfigurationListViewModel(configurationManager: configurationManager))
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationSplitView {
            sidebarContent
        } detail: {
            detailContent
            .toolbar {
                if let config = selectedConfiguration {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            activeSheet = .edit(config)
                        } label: {
                            Label("Edit", systemImage: "pencil")
                        }
                    }
                }
            }
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
                        
                        Button("Test Run") {
                            viewModel.testRun(configuration: config, openWindow: openWindow)
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
                    onTestRun: {
                        viewModel.testRun(configuration: config, openWindow: openWindow)
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
    let onTestRun: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Header with icon and name
                HStack(spacing: 12) {
                    Image(systemName: "server.rack")
                        .font(.system(size: 36))
                        .foregroundColor(.blue)
                    
                    Text(configuration.name)
                        .font(.title)
                        .fontWeight(.bold)
                }
                .padding(.bottom, 4)
                
                Divider()
                
                // Launch Script Section
                VStack(alignment: .leading, spacing: 6) {
                    Label("Launch Script", systemImage: "terminal")
                        .font(.headline)
                    
                    VStack(alignment: .leading, spacing: 4) {
                        Text(scriptSourceLabel)
                            .font(.callout)
                            .foregroundColor(.primary)
                        
                        switch configuration.scriptSource {
                        case .command:
                            DetailRow(label: "Executable", value: configuration.command)
                            if !configuration.arguments.isEmpty {
                                DetailRow(label: "Arguments", value: configuration.arguments.joined(separator: " "))
                            }
                        case .file:
                            DetailRow(label: "Script", value: configuration.command)
                            if !configuration.arguments.isEmpty {
                                DetailRow(label: "Arguments", value: configuration.arguments.joined(separator: " "))
                            }
                        case .inline:
                            if let content = configuration.inlineScriptContent, !content.isEmpty {
                                Text(content)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundColor(.secondary)
                                    .lineLimit(3)
                            }
                        }
                        
                        if let wd = configuration.workingDirectory, !wd.isEmpty {
                            DetailRow(label: "Working Dir", value: wd)
                        }
                    }
                    .padding(.leading, 28)
                }
                
                Divider()
                
                // Network & Detection
                HStack(alignment: .top, spacing: 16) {
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Network", systemImage: "network")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if let url = configuration.localhostURL {
                                Text(url)
                                    .font(.callout)
                                    .textSelection(.enabled)
                            } else {
                                Text("Not configured")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        .padding(.leading, 28)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    
                    VStack(alignment: .leading, spacing: 6) {
                        Label("Detection", systemImage: "magnifyingglass")
                            .font(.headline)
                        
                        VStack(alignment: .leading, spacing: 4) {
                            if let pattern = configuration.readySignalPattern, !pattern.isEmpty {
                                DetailRow(label: "Ready Signal", value: pattern)
                            } else {
                                Text("Not configured")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            if let pattern = configuration.portDetectionPattern, !pattern.isEmpty {
                                DetailRow(label: "Port", value: pattern)
                            }
                        }
                        .padding(.leading, 28)
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                
                Divider()
                
                // Actions
                VStack(spacing: 8) {
                    Button(action: onGenerate) {
                        HStack {
                            Image(systemName: "app.badge")
                            Text("Generate App Bundle")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    
                    Button(action: onTestRun) {
                        HStack {
                            Image(systemName: "play.fill")
                            Text("Test Run")
                        }
                        .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.large)
                }
                
                // Metadata
                VStack(alignment: .leading, spacing: 2) {
                    Text("Created \(formatDate(configuration.createdAt))")
                        .font(.caption2)
                        .foregroundColor(.secondary)
                    Text(configuration.id.uuidString)
                        .font(.caption2)
                        .foregroundColor(.secondary.opacity(0.7))
                        .textSelection(.enabled)
                        .lineLimit(1)
                        .truncationMode(.middle)
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
    
    private var scriptSourceLabel: String {
        switch configuration.scriptSource {
        case .command: return "Manual Command"
        case .file: return "Script File"
        case .inline: return "Inline Script"
        }
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
    ConfigurationListView(configurationManager: ConfigurationManager())
}

