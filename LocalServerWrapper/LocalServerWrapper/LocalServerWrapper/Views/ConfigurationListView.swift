//
//  ConfigurationListView.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import SwiftUI
import AppKit

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
                        
                        Button("Run") {
                            viewModel.run(configuration: config)
                        }
                        
                        Button("Use as standalone app...") {
                            viewModel.exportStandaloneApp(for: config)
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
                    isGenerating: viewModel.isGenerating,
                    onEdit: {
                        activeSheet = .edit(config)
                    },
                    onGenerate: {
                        viewModel.exportStandaloneApp(for: config)
                    },
                    onRun: {
                        viewModel.run(configuration: config)
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

// MARK: - Configuration Icon View

/// Displays a configuration's custom icon, falling back to a tinted SF Symbol placeholder.
struct ConfigIconView: View {
    let configuration: ServerConfiguration
    var size: CGFloat = 28
    var cornerRadius: CGFloat = 6

    private var loadedImage: NSImage? {
        guard let path = configuration.customIconPath, !path.isEmpty,
              FileManager.default.fileExists(atPath: path) else { return nil }
        return NSImage(contentsOfFile: path)
    }

    var body: some View {
        Group {
            if let image = loadedImage {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.15))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "server.rack")
                            .font(.system(size: size * 0.5))
                            .foregroundStyle(.tint)
                    }
            }
        }
    }
}

// MARK: - Configuration Row View

/// View for a single configuration row in the list
struct ConfigurationRowView: View {
    let configuration: ServerConfiguration

    var body: some View {
        HStack(spacing: 10) {
            ConfigIconView(configuration: configuration, size: 28, cornerRadius: 6)

            VStack(alignment: .leading, spacing: 2) {
                Text(configuration.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)
            }
        }
        .padding(.vertical, 2)
    }

    /// The most identifying secondary line: a fixed URL when one is pinned, then the command, then a
    /// script hint. (In automatic mode the stored URL is only a fallback, so the command is more
    /// identifying than a placeholder address.)
    private var subtitle: String {
        if configuration.urlDetectionMode == .fixed, let url = configuration.localhostURL, !url.isEmpty {
            return url
        }
        if !configuration.command.isEmpty {
            let args = configuration.arguments.joined(separator: " ")
            return args.isEmpty ? configuration.command : "\(configuration.command) \(args)"
        }
        return configuration.scriptSource == .inline ? "Inline script" : "No command"
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

// MARK: - Configuration Detail View

/// View displaying details of a selected configuration
struct ConfigurationDetailView: View {
    let configuration: ServerConfiguration
    var isGenerating: Bool = false
    let onEdit: () -> Void
    let onGenerate: () -> Void
    let onRun: () -> Void
    let onDelete: () -> Void
    
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    header
                    launchScriptCard
                    HStack(alignment: .top, spacing: 16) {
                        networkCard
                        detectionCard
                    }
                    metadataFooter
                }
                .padding(24)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)

            actionBar
        }
        .background(Color(nsColor: .controlBackgroundColor))
    }

    // MARK: - Header

    private var header: some View {
        HStack(spacing: 14) {
            ConfigIconView(configuration: configuration, size: 52, cornerRadius: 12)

            VStack(alignment: .leading, spacing: 2) {
                Text(configuration.name)
                    .font(.title)
                    .fontWeight(.bold)
                Text(scriptSourceLabel)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Cards

    private var launchScriptCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
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
                            .foregroundStyle(.secondary)
                            .lineLimit(5)
                            .textSelection(.enabled)
                    }
                }

                if let wd = configuration.workingDirectory, !wd.isEmpty {
                    DetailRow(label: "Working Dir", value: wd)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("Launch Script", systemImage: "terminal")
        }
    }

    private var networkCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 4) {
                switch configuration.urlDetectionMode {
                case .automatic:
                    // In automatic mode localhostURL is only a fallback, so showing it would
                    // misrepresent the default as the real address. The actual URL is discovered
                    // when the server runs.
                    Label("Detected automatically when the server starts", systemImage: "wand.and.stars")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                case .fixed:
                    if let url = configuration.localhostURL, !url.isEmpty {
                        Text(url)
                            .font(.callout)
                            .textSelection(.enabled)
                    } else {
                        Text("Not configured")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("Network", systemImage: "network")
        }
        .frame(maxWidth: .infinity)
    }

    private var detectionCard: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if let pattern = configuration.readySignalPattern, !pattern.isEmpty {
                    DetailRow(label: "Ready Signal", value: pattern)
                } else {
                    Text("Not configured")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                if let pattern = configuration.portDetectionPattern, !pattern.isEmpty {
                    DetailRow(label: "Port", value: pattern)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(4)
        } label: {
            Label("Detection", systemImage: "magnifyingglass")
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Metadata Footer

    private var metadataFooter: some View {
        HStack {
            Text("Created \(formatDate(configuration.createdAt))")
                .font(.caption)
                .foregroundStyle(.secondary)

            Spacer()

            Button {
                let pasteboard = NSPasteboard.general
                pasteboard.clearContents()
                pasteboard.setString(configuration.id.uuidString, forType: .string)
            } label: {
                Label("Copy ID", systemImage: "doc.on.doc")
                    .font(.caption)
            }
            .buttonStyle(.borderless)
            .help(configuration.id.uuidString)
        }
        .padding(.top, 4)
    }

    // MARK: - Action Bar

    private var actionBar: some View {
        HStack(spacing: 8) {
            Button(action: onRun) {
                Label("Run", systemImage: "play.fill")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)

            Button(action: onGenerate) {
                HStack {
                    if isGenerating {
                        ProgressView()
                            .controlSize(.small)
                        Text("Generating…")
                    } else {
                        Image(systemName: "square.and.arrow.up")
                        Text("Use as standalone app...")
                    }
                }
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
            .disabled(isGenerating)
        }
        .controlSize(.large)
        .padding(.horizontal, 24)
        .padding(.vertical, 12)
        .background(.bar)
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

