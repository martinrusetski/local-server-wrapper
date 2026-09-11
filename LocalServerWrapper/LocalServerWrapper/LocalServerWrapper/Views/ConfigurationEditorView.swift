//
//  ConfigurationEditorView.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// View for creating and editing server app setups.
struct ConfigurationEditorView: View {
    // MARK: - Environment

    @Environment(\.dismiss) private var dismiss

    // MARK: - Properties

    /// The configuration manager
    let configurationManager: ConfigurationManagerProtocol

    /// The configuration being edited (nil for new configuration)
    let editingConfiguration: ServerConfiguration?

    /// Callback when configuration is saved. The configuration id lets the library refresh the
    /// matching exported bundle without coupling this editor to generation work.
    let onSave: (UUID) -> Void

    // MARK: - State

    @State private var name: String
    /// The single free-form shell command / script the server launches with. Saved verbatim as the
    /// inline script content and executed through the shell by the runtime.
    @State private var commandText: String
    @State private var localhostURL: String
    @State private var runWithoutTerminal: Bool
    @State private var customIconPath: String
    @State private var workingDirectory: String

    /// Advanced regexes are no longer editable here, but must be preserved on save so existing
    /// configs don't silently lose their ready-signal / port-detection behavior.
    private let preservedReadySignalPattern: String?
    private let preservedPortDetectionPattern: String?

    // Validation errors
    @State private var nameError: String?
    @State private var commandError: String?
    @State private var urlError: String?
    @State private var iconError: String?

    // UI state
    @State private var showingIconPicker = false
    @State private var showingError = false
    @State private var errorMessage: String?

    /// Whether the "Advanced options" disclosure group is expanded
    @State private var showAdvanced: Bool

    /// Drives the "Test launch" feature: runs the server once to discover its URL.
    @StateObject private var probe = ServerProbe()

    // MARK: - Initialization

    init(
        configurationManager: ConfigurationManagerProtocol,
        editingConfiguration: ServerConfiguration? = nil,
        onSave: @escaping (UUID) -> Void
    ) {
        self.configurationManager = configurationManager
        self.editingConfiguration = editingConfiguration
        self.onSave = onSave

        // Initialize state from editing configuration or with defaults
        if let config = editingConfiguration {
            _name = State(initialValue: config.name)
            _commandText = State(initialValue: Self.commandText(from: config))
            _localhostURL = State(initialValue: config.localhostURL ?? "")
            _runWithoutTerminal = State(initialValue: config.runWithoutTerminal)
            _customIconPath = State(initialValue: config.customIconPath ?? "")
            _workingDirectory = State(initialValue: config.workingDirectory ?? "")
            preservedReadySignalPattern = config.readySignalPattern
            preservedPortDetectionPattern = config.portDetectionPattern

            // Auto-expand Advanced only if the one advanced option it still exposes is in use.
            _showAdvanced = State(initialValue: config.runWithoutTerminal)
        } else {
            _name = State(initialValue: "")
            _commandText = State(initialValue: "")
            _localhostURL = State(initialValue: "")
            _runWithoutTerminal = State(initialValue: false)
            _customIconPath = State(initialValue: "")
            _workingDirectory = State(initialValue: "")
            preservedReadySignalPattern = nil
            preservedPortDetectionPattern = nil
            _showAdvanced = State(initialValue: false)
        }
    }

    // MARK: - Body

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    identitySection
                    Divider()
                    launchSection
                    Divider()
                    serverSection
                    Divider()
                    advancedSection
                }
                .padding(.horizontal, 20)
                .padding(.vertical, 14)
            }
            .navigationTitle(editingConfiguration == nil ? "New App" : "Edit App")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") {
                        dismiss()
                    }
                    .keyboardShortcut(.escape)
                    .accessibilityLabel("Cancel")
                    .accessibilityHint("Closes the editor without saving changes")
                }

                ToolbarItem(placement: .confirmationAction) {
                    Button(editingConfiguration == nil ? "Save App" : "Save Changes") {
                        saveConfiguration()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!isValid)
                    .accessibilityLabel(editingConfiguration == nil ? "Save App" : "Save Changes")
                    .accessibilityHint(isValid ? "Saves the app setup" : "Cannot save: form has validation errors")
                }
            }
            .fileImporter(
                isPresented: $showingIconPicker,
                allowedContentTypes: [.image],
                allowsMultipleSelection: false
            ) { result in
                handleIconSelection(result)
            }
            .alert("Error", isPresented: $showingError) {
                Button("OK") {
                    errorMessage = nil
                }
            } message: {
                if let message = errorMessage {
                    Text(message)
                }
            }
        }
        .frame(width: 580, height: showAdvanced ? 500 : 460)
        .animation(.easeInOut(duration: 0.18), value: showAdvanced)
        .onDisappear { probe.cancel() }
    }

    // MARK: - Compact Editor Sections

    private var identitySection: some View {
        HStack(alignment: .center, spacing: 12) {
            iconWell

            VStack(alignment: .leading, spacing: 4) {
                Text("App name")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                TextField("Name", text: $name, prompt: Text("My Dev Server"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: name) { _ in
                        validateName()
                    }
                    .accessibilityLabel("App Name")
                    .accessibilityHint("Enter a unique name for this server app")
                    .accessibilityValue(name.isEmpty ? "Empty" : name)

                if let error = nameError {
                    validationMessage(error)
                } else if let error = iconError {
                    validationMessage(error)
                }
            }
        }
    }

    private var launchSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Launch")
                    .font(.headline)

                Spacer()

                Button("Choose script…") {
                    chooseScriptFile()
                }
                .buttonStyle(.bordered)
                .help("Pick a shell script. Its quoted path replaces the command below and its folder becomes \u{201C}Run in folder\u{201D}.")
            }

            launchCommandFields

            Text("Runs through the shell. Enter one command or a multi-line script.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var serverSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Server")
                .font(.headline)

            HStack(alignment: .top, spacing: 8) {
                fixedURLField
                probeActionButton
            }

            probeStatusView

            Text("Leave blank to detect the URL and port automatically.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }

    private var advancedSection: some View {
        DisclosureGroup(isExpanded: $showAdvanced) {
            VStack(alignment: .leading, spacing: 4) {
                Toggle("Run without a terminal", isOn: $runWithoutTerminal)
                    .help("By default the server runs as if launched in Terminal, so scripts that only start when they detect an interactive terminal work. Turn this on only if a server misbehaves that way.")
                    .accessibilityLabel("Run without a terminal")

                Text("Leave off unless the server behaves incorrectly when attached to a terminal.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            .padding(.top, 6)
        } label: {
            Text("Advanced options")
                .font(.headline)
        }
    }

    private func validationMessage(_ message: String) -> some View {
        Text(message)
            .font(.caption)
            .foregroundStyle(.red)
    }

    // MARK: - Launch Subviews

    @ViewBuilder
    private var launchCommandFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            VStack(alignment: .leading, spacing: 4) {
                TextEditor(text: $commandText)
                    .font(.system(.body, design: .monospaced))
                    .frame(height: 68)
                    .overlay(
                        RoundedRectangle(cornerRadius: 4)
                            .stroke(Color.secondary.opacity(0.3), lineWidth: 1)
                    )
                    .onChange(of: commandText) { _ in
                        validateCommand()
                    }
                    .help("The shell command or script that starts your server.")
                    .accessibilityLabel("Launch command")

                if let error = commandError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            workingDirectoryField
        }
    }

    private var workingDirectoryField: some View {
        HStack(spacing: 8) {
            TextField("Run in folder", text: $workingDirectory, prompt: Text("optional · defaults to your home folder"))
                .textFieldStyle(.roundedBorder)
                .help("The folder the command runs in. Defaults to your home folder if left empty.")
                .accessibilityLabel("Run in folder")

            Button("Choose…") {
                chooseWorkingDirectory()
            }
            .buttonStyle(.bordered)

            if !workingDirectory.isEmpty {
                Button {
                    workingDirectory = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear run folder")
            }
        }
    }

    // MARK: - Server Address Subviews

    /// The optional URL text field. Empty ⇒ automatic detection; non-empty ⇒ loaded as written.
    private var fixedURLField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Server URL", text: $localhostURL, prompt: Text("optional · e.g. http://localhost:3000").foregroundColor(Color(nsColor: .placeholderTextColor)))
                .textFieldStyle(.roundedBorder)
                .onChange(of: localhostURL) { _ in
                    validateURL()
                }
                .help("Leave empty to detect automatically, or enter the URL your server is reachable at.")
                .accessibilityLabel("Server URL")
                .accessibilityHint("Optional. Leave empty to detect the URL automatically")
                .accessibilityValue(localhostURL.isEmpty ? "Empty" : localhostURL)

            if let error = urlError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    @ViewBuilder
    private var probeStatusView: some View {
        switch probe.phase {
        case .idle:
            EmptyView()
        case .launching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Launching server and watching for its port…")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        case .detected(let url):
            HStack(spacing: 6) {
                Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
                Text(url.absoluteString)
                    .textSelection(.enabled)
                Button("Pin as fixed URL") {
                    localhostURL = url.absoluteString
                    validateURL()
                    probe.reset()
                }
                .buttonStyle(.link)
                .font(.callout)
            }
        case .failed(let message):
            Label(message, systemImage: "exclamationmark.triangle.fill")
                .foregroundStyle(.orange)
                .font(.caption)
                .lineLimit(3)
        }
    }

    @ViewBuilder
    private var probeActionButton: some View {
        switch probe.phase {
        case .launching:
            Button("Stop") { probe.cancel() }
                .buttonStyle(.bordered)
        default:
            Button(probe.phase == .idle ? "Test launch" : "Test again") {
                runTestLaunch()
            }
            .buttonStyle(.bordered)
            .disabled(!canTestLaunch)
            .help(canTestLaunch
                  ? "Launch the server once to detect the URL it serves."
                  : "Enter a command first.")
        }
    }

    /// Whether there's enough in the form to actually launch something.
    private var canTestLaunch: Bool {
        !commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    /// Build a throwaway configuration from the current form and run the probe against it.
    private func runTestLaunch() {
        probe.start(config: draftConfiguration())
    }

    /// A configuration built from the current editor fields, used for test launches (no persistence).
    /// Built the same way as `saveConfiguration()` so a test launch exercises exactly what will run.
    private func draftConfiguration() -> ServerConfiguration {
        let trimmedWorkingDir = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = localhostURL.trimmingCharacters(in: .whitespacesAndNewlines)

        return ServerConfiguration(
            name: name.isEmpty ? "Test" : name,
            command: "",
            arguments: [],
            localhostURL: trimmedURL.isEmpty ? nil : trimmedURL,
            urlDetectionMode: trimmedURL.isEmpty ? .automatic : .fixed,
            runWithoutTerminal: runWithoutTerminal,
            readySignalPattern: preservedReadySignalPattern,
            portDetectionPattern: preservedPortDetectionPattern,
            workingDirectory: trimmedWorkingDir.isEmpty ? nil : trimmedWorkingDir,
            scriptSource: .inline,
            inlineScriptContent: commandText
        )
    }

    // MARK: - Icon Well

    /// The custom icon loaded from disk, if a valid path is set.
    private var loadedIconImage: NSImage? {
        let trimmed = customIconPath.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return nil }
        let expanded = NSString(string: trimmed).expandingTildeInPath
        guard FileManager.default.fileExists(atPath: expanded) else { return nil }
        return NSImage(contentsOfFile: expanded)
    }

    /// A clickable icon well that previews and chooses the custom app icon.
    private var iconWell: some View {
        Button {
            showingIconPicker = true
        } label: {
            Group {
                if let image = loadedIconImage {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else if let image = DefaultIcon.image {
                    Image(nsImage: image)
                        .resizable()
                        .aspectRatio(contentMode: .fill)
                } else {
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .fill(Color.accentColor.opacity(0.15))
                        .overlay {
                            Image(systemName: "photo.badge.plus")
                                .font(.system(size: 20))
                                .foregroundStyle(.tint)
                        }
                }
            }
            .frame(width: 48, height: 48)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
        }
        .buttonStyle(.plain)
        .overlay(alignment: .bottomTrailing) {
            if !customIconPath.isEmpty {
                Button {
                    customIconPath = ""
                    iconError = nil
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.body)
                        .foregroundStyle(.secondary)
                        .background(Circle().fill(.background))
                }
                .buttonStyle(.plain)
                .offset(x: 4, y: 4)
                .accessibilityLabel("Clear icon")
            }
        }
        .help(customIconPath.isEmpty
              ? "Choose a custom icon for the generated app (optional)."
              : "Click to change the app icon.")
        .accessibilityLabel("App icon")
    }

    // MARK: - Computed Properties

    /// Whether the form is valid and can be saved
    private var isValid: Bool {
        let nameValid = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && nameError == nil
        let commandValid = !commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && commandError == nil
        let urlValid = urlError == nil
        let iconValid = iconError == nil
        return nameValid && commandValid && urlValid && iconValid
    }

    // MARK: - Validation Methods

    private func validateName() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)

        if trimmedName.isEmpty {
            nameError = "Name is required"
            return
        }

        // Check for duplicate names (only if creating new or name changed)
        if editingConfiguration == nil || editingConfiguration?.name != trimmedName {
            let existingConfigs = configurationManager.listConfigurations()
            if existingConfigs.contains(where: { $0.name == trimmedName }) {
                nameError = "An app with this name already exists"
                return
            }
        }

        nameError = nil
    }

    /// The command is free-form shell text, so it can't be statically validated beyond presence.
    private func validateCommand() {
        if commandText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            commandError = "A launch command is required"
        } else {
            commandError = nil
        }
    }

    private func validateURL() {
        let trimmedURL = localhostURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // URL is optional
        if trimmedURL.isEmpty {
            urlError = nil
            return
        }

        let validator = ConfigurationValidator()
        do {
            try validator.validateURL(trimmedURL)
            urlError = nil
        } catch let error as ValidationError {
            urlError = error.errorDescription
        } catch {
            urlError = "Invalid URL format"
        }
    }

    private func validateIcon() {
        let trimmedPath = customIconPath.trimmingCharacters(in: .whitespacesAndNewlines)

        // Icon is optional
        if trimmedPath.isEmpty {
            iconError = nil
            return
        }

        let fileManager = FileManager.default
        let expandedPath = NSString(string: trimmedPath).expandingTildeInPath

        // Check if file exists
        guard fileManager.fileExists(atPath: expandedPath) else {
            iconError = "Icon file does not exist"
            return
        }

        // Check if it's a regular file
        var isDirectory: ObjCBool = false
        fileManager.fileExists(atPath: expandedPath, isDirectory: &isDirectory)

        if isDirectory.boolValue {
            iconError = "Icon path is a directory, not a file"
            return
        }

        // Check file extension
        let validExtensions = ["png", "jpg", "jpeg", "icns", "ico", "gif", "tiff", "tif"]
        let pathExtension = NSString(string: expandedPath).pathExtension.lowercased()

        if !validExtensions.contains(pathExtension) {
            iconError = "Icon must be an image file (png, jpg, icns, etc.)"
            return
        }

        iconError = nil
    }

    // MARK: - Action Methods

    private func handleIconSelection(_ result: Result<[URL], Error>) {
        switch result {
        case .success(let urls):
            if let url = urls.first {
                customIconPath = url.path
                validateIcon()
            }
        case .failure(let error):
            errorMessage = "Failed to select icon: \(error.localizedDescription)"
            showingError = true
        }
    }

    private func chooseWorkingDirectory() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = false
        panel.prompt = "Select"
        panel.message = "Choose the folder this server runs in"

        if panel.runModal() == .OK, let url = panel.url {
            workingDirectory = url.path
        }
    }

    private func chooseScriptFile() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.shellScript, .unixExecutable]
        panel.prompt = "Select"
        panel.message = "Choose a shell script to run"

        if panel.runModal() == .OK, let url = panel.url {
            // Replace the command with the quoted script path and default the run folder to its parent.
            commandText = Self.shellQuote(url.path)
            workingDirectory = url.deletingLastPathComponent().path
            validateCommand()
        }
    }

    private func saveConfiguration() {
        // Validate all fields one more time
        validateName()
        validateCommand()
        validateURL()
        validateIcon()

        guard isValid else {
            errorMessage = "Please fix all validation errors before saving"
            showingError = true
            return
        }

        let trimmedIconPath = customIconPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWorkingDir = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedURL = localhostURL.trimmingCharacters(in: .whitespacesAndNewlines)

        // Everything the editor saves is an inline script executed through the shell. The command
        // field's text becomes the inline content verbatim; command/arguments stay empty.
        let urlDetectionMode: URLDetectionMode = trimmedURL.isEmpty ? .automatic : .fixed

        // Create or update configuration
        var config: ServerConfiguration
        let configId: UUID

        if let existing = editingConfiguration {
            configId = existing.id
            config = ServerConfiguration(
                id: existing.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                command: "",
                arguments: [],
                localhostURL: trimmedURL.isEmpty ? nil : trimmedURL,
                urlDetectionMode: urlDetectionMode,
                runWithoutTerminal: runWithoutTerminal,
                readySignalPattern: preservedReadySignalPattern,
                portDetectionPattern: preservedPortDetectionPattern,
                customIconPath: nil, // set below after potential storage
                workingDirectory: trimmedWorkingDir.isEmpty ? nil : trimmedWorkingDir,
                scriptSource: .inline,
                inlineScriptContent: commandText
            )
            config.createdAt = existing.createdAt
            config.touch()
        } else {
            config = ServerConfiguration(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                command: "",
                arguments: [],
                localhostURL: trimmedURL.isEmpty ? nil : trimmedURL,
                urlDetectionMode: urlDetectionMode,
                runWithoutTerminal: runWithoutTerminal,
                readySignalPattern: preservedReadySignalPattern,
                portDetectionPattern: preservedPortDetectionPattern,
                customIconPath: nil, // set below after potential storage
                workingDirectory: trimmedWorkingDir.isEmpty ? nil : trimmedWorkingDir,
                scriptSource: .inline,
                inlineScriptContent: commandText
            )
            configId = config.id
        }

        // Store the icon in managed storage if a custom icon was selected
        if !trimmedIconPath.isEmpty {
            if IconStorage.isManagedPath(trimmedIconPath) {
                config.customIconPath = trimmedIconPath
            } else if let storedPath = IconStorage.storeIcon(from: trimmedIconPath, for: configId) {
                config.customIconPath = storedPath
            } else {
                // Fallback: keep the original path
                config.customIconPath = trimmedIconPath
            }
        }

        // Save configuration
        do {
            if editingConfiguration != nil {
                try configurationManager.updateConfiguration(config)
            } else {
                try configurationManager.createConfiguration(config)
            }

            onSave(configId)
            dismiss()
        } catch {
            errorMessage = "Failed to save app: \(error.localizedDescription)"
            showingError = true
        }
    }

    // MARK: - Migration Helpers

    /// Wrap a string in single quotes for safe use in a shell command line.
    private static func shellQuote(_ value: String) -> String {
        "'" + value.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }

    /// Build the single command-field text from an existing configuration, collapsing the old
    /// three launch modes into one shell command string.
    private static func commandText(from config: ServerConfiguration) -> String {
        switch config.scriptSource {
        case .inline:
            return config.inlineScriptContent ?? ""
        case .command:
            return ([config.command] + config.arguments)
                .filter { !$0.isEmpty }
                .joined(separator: " ")
        case .file:
            let quotedPath = shellQuote(config.command)
            let args = config.arguments.map { arg in
                arg.rangeOfCharacter(from: .whitespaces) != nil ? shellQuote(arg) : arg
            }
            return ([quotedPath] + args).joined(separator: " ")
        }
    }
}

// MARK: - Preview

#Preview("New App") {
    ConfigurationEditorView(
        configurationManager: ConfigurationManager(),
        editingConfiguration: nil,
        onSave: { _ in }
    )
}

#Preview("Edit App") {
    let config = ServerConfiguration(
        name: "My Dev Server",
        command: "npm",
        arguments: ["run", "dev"],
        localhostURL: "http://localhost:3000",
        readySignalPattern: "Ready on",
        portDetectionPattern: "localhost:(\\d+)"
    )

    return ConfigurationEditorView(
        configurationManager: ConfigurationManager(),
        editingConfiguration: config,
        onSave: { _ in }
    )
}
