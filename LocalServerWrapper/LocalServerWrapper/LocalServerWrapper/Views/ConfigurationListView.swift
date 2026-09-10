//
//  ConfigurationListView.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import SwiftUI
import AppKit

/// Identifies which sheet to present: new or edit.
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

/// One-pane library of configured server apps.
struct ConfigurationListView: View {
    @StateObject private var viewModel: ConfigurationListViewModel
    @State private var searchText = ""
    @State private var activeSheet: ConfigurationSheet?
    @State private var showingDeleteAlert = false
    @State private var configurationToDelete: ServerConfiguration?

    init(configurationManager: ConfigurationManager) {
        _viewModel = StateObject(
            wrappedValue: ConfigurationListViewModel(configurationManager: configurationManager)
        )
    }

    var body: some View {
        NavigationStack {
            Group {
                if viewModel.configurations.isEmpty {
                    EmptyStateView {
                        activeSheet = .new
                    }
                } else if filteredConfigurations.isEmpty {
                    SearchEmptyState(searchText: searchText)
                } else {
                    appList
                }
            }
            .navigationTitle("Server Apps")
            .searchable(text: $searchText, prompt: "Search apps")
            .toolbar {
                ToolbarItem(placement: .primaryAction) {
                    Button {
                        activeSheet = .new
                    } label: {
                        HStack(spacing: 5) {
                            Image(systemName: "plus")
                            Text("New App…")
                        }
                    }
                    .buttonStyle(.bordered)
                    .keyboardShortcut("n", modifiers: .command)
                    .help("Configure a new server app")
                }
            }
        }
        .sheet(item: $activeSheet) { sheet in
            ConfigurationEditorView(
                configurationManager: viewModel.configurationManager,
                editingConfiguration: sheet.editingConfig,
                onSave: viewModel.configurationDidSave
            )
        }
        .alert("Delete App Setup?", isPresented: $showingDeleteAlert, presenting: configurationToDelete) { config in
            Button("Cancel", role: .cancel) {
                configurationToDelete = nil
            }
            Button("Delete", role: .destructive) {
                viewModel.deleteConfiguration(config)
                configurationToDelete = nil
            }
        } message: { config in
            Text("Delete the saved setup for ‘\(config.name)’? App copies you already generated will not be removed.")
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
    }

    private var appList: some View {
        List(filteredConfigurations) { config in
            ConfigurationRowView(
                configuration: config,
                operationState: viewModel.operationState(for: config.id),
                exportedBundleURL: viewModel.exportedBundleURL(for: config.id),
                onEdit: { activeSheet = .edit(config) },
                onGenerate: { viewModel.exportStandaloneApp(for: config) },
                onRegenerate: { viewModel.regenerateExportedApp(for: config) },
                onCancelGeneration: { viewModel.cancelGeneration(for: config.id) },
                onTestLaunch: { viewModel.testLaunch(configuration: config) },
                onOpenExportedApp: { viewModel.openExportedApp(for: config) },
                onRevealExportedApp: { viewModel.revealExportedApp(for: config) },
                onDelete: { requestDelete(config) }
            )
            .listRowInsets(EdgeInsets(top: 7, leading: 8, bottom: 7, trailing: 8))
            .contextMenu {
                rowMenu(for: config)
            }
        }
        .listStyle(.plain)
        .padding(.top, 6)
    }

    @ViewBuilder
    private func rowMenu(for config: ServerConfiguration) -> some View {
        if viewModel.exportedBundleURL(for: config.id) == nil {
            Button("Generate App…") {
                viewModel.exportStandaloneApp(for: config)
            }
        } else {
            Button("Show in Finder") {
                viewModel.revealExportedApp(for: config)
            }

            Button("Regenerate App") {
                viewModel.regenerateExportedApp(for: config)
            }
        }

        Divider()

        Button("Edit…") {
            activeSheet = .edit(config)
        }

        Button("Test Launch") {
            viewModel.testLaunch(configuration: config)
        }

        if viewModel.exportedBundleURL(for: config.id) != nil {
            Button("Open App") {
                viewModel.openExportedApp(for: config)
            }
        }

        Divider()

        Button("Delete…", role: .destructive) {
            requestDelete(config)
        }
    }

    private func requestDelete(_ config: ServerConfiguration) {
        configurationToDelete = config
        showingDeleteAlert = true
    }

    private var filteredConfigurations: [ServerConfiguration] {
        guard !searchText.isEmpty else { return viewModel.configurations }

        return viewModel.configurations.filter { config in
            config.name.localizedCaseInsensitiveContains(searchText)
                || ConfigurationRowView.subtitle(for: config).localizedCaseInsensitiveContains(searchText)
        }
    }
}

// MARK: - App Icon

/// Displays a configuration's custom icon, falling back to the bundled server placeholder.
struct ConfigIconView: View {
    let configuration: ServerConfiguration
    var size: CGFloat = 40
    var cornerRadius: CGFloat = 9

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
            } else if let image = DefaultIcon.image {
                Image(nsImage: image)
                    .resizable()
                    .aspectRatio(contentMode: .fill)
                    .frame(width: size, height: size)
                    .clipShape(RoundedRectangle(cornerRadius: cornerRadius, style: .continuous))
            } else {
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(Color.accentColor.opacity(0.14))
                    .frame(width: size, height: size)
                    .overlay {
                        Image(systemName: "server.rack")
                            .font(.system(size: size * 0.46, weight: .medium))
                            .foregroundStyle(.tint)
                    }
            }
        }
        .accessibilityHidden(true)
    }
}

// MARK: - App Row

/// A complete generator-first row for one saved server app.
struct ConfigurationRowView: View {
    let configuration: ServerConfiguration
    let operationState: AppBundleOperationState
    let exportedBundleURL: URL?
    let onEdit: () -> Void
    let onGenerate: () -> Void
    let onRegenerate: () -> Void
    let onCancelGeneration: () -> Void
    let onTestLaunch: () -> Void
    let onOpenExportedApp: () -> Void
    let onRevealExportedApp: () -> Void
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            ConfigIconView(configuration: configuration)

            VStack(alignment: .leading, spacing: 3) {
                Text(configuration.name)
                    .font(.headline)
                    .lineLimit(1)

                Text(Self.subtitle(for: configuration))
                    .font(.system(.caption, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.middle)

                operationStatus
                    .padding(.top, 2)
            }
            .frame(minWidth: 120, maxWidth: .infinity, alignment: .leading)

            primaryActionButton
                .fixedSize()

            Menu {
                Button("Edit…", action: onEdit)
                Button("Test Launch", action: onTestLaunch)

                if exportedBundleURL != nil {
                    Divider()
                    Button("Open App", action: onOpenExportedApp)
                    Button("Regenerate App", action: onRegenerate)
                }

                Divider()
                Button("Delete…", role: .destructive, action: onDelete)
            } label: {
                Image(systemName: "ellipsis")
                    .frame(width: 22, height: 22)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
            .help("More actions")
            .accessibilityLabel("More actions for \(configuration.name)")
        }
        .frame(minHeight: 48)
        .alignmentGuide(.listRowSeparatorLeading) { dimensions in
            dimensions[.leading]
        }
        .alignmentGuide(.listRowSeparatorTrailing) { dimensions in
            dimensions[.trailing]
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2, perform: onEdit)
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var operationStatus: some View {
        switch operationState {
        case .idle:
            EmptyView()

        case .generating(_, let status):
            HStack(spacing: 7) {
                ProgressView()
                    .controlSize(.small)
                Text(status.isEmpty ? "Generating…" : status)
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .succeeded(let url):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                Text("Ready in \(url.deletingLastPathComponent().lastPathComponent)")
                    .lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.secondary)

        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .font(.caption)
                .foregroundStyle(.orange)
                .lineLimit(2)
                .help(message)
        }
    }

    @ViewBuilder
    private var primaryActionButton: some View {
        Group {
            if exportedBundleURL != nil {
                Button("Show in Finder", action: onRevealExportedApp)
            } else {
                switch operationState {
                case .generating:
                    Button("Cancel", action: onCancelGeneration)

                case .failed:
                    Button("Try Again", action: onGenerate)

                default:
                    Button("Generate App…", action: onGenerate)
                }
            }
        }
        .buttonStyle(.bordered)
    }

    static func subtitle(for configuration: ServerConfiguration) -> String {
        if !configuration.command.isEmpty {
            let args = configuration.arguments.joined(separator: " ")
            return args.isEmpty ? configuration.command : "\(configuration.command) \(args)"
        }

        if let firstLine = configuration.inlineScriptContent?
            .split(separator: "\n")
            .map({ $0.trimmingCharacters(in: .whitespaces) })
            .first(where: { !$0.isEmpty && !$0.hasPrefix("#") }) {
            return firstLine
        }

        if configuration.urlDetectionMode == .fixed,
           let url = configuration.localhostURL,
           !url.isEmpty {
            return url
        }

        return "No launch command"
    }
}

// MARK: - Empty State

struct EmptyStateView: View {
    let onCreateApp: () -> Void

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: "macwindow.badge.plus")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)

            Text("Turn a Local Server into a Mac App")
                .font(.title2.weight(.semibold))

            Text("Add the command you normally run in Terminal. Local Server Wrapper creates an app that starts the server and opens its interface.")
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)

            Button("Create Your First App…", action: onCreateApp)
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(32)
        .accessibilityElement(children: .contain)
    }
}

struct SearchEmptyState: View {
    let searchText: String

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "magnifyingglass")
                .font(.system(size: 34))
                .foregroundStyle(.secondary)
            Text("No Results")
                .font(.title3.weight(.semibold))
            Text("No apps match ‘\(searchText)’.")
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    ConfigurationListView(configurationManager: ConfigurationManager())
}
