//
//  ConfigurationEditorView.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import SwiftUI
import UniformTypeIdentifiers
import AppKit

/// View for creating and editing server configurations
struct ConfigurationEditorView: View {
    // MARK: - Environment
    
    @Environment(\.dismiss) private var dismiss
    
    // MARK: - Properties
    
    /// The configuration manager
    let configurationManager: ConfigurationManagerProtocol
    
    /// The configuration being edited (nil for new configuration)
    let editingConfiguration: ServerConfiguration?
    
    /// Callback when configuration is saved
    let onSave: () -> Void
    
    // MARK: - State
    
    @State private var name: String
    @State private var command: String
    @State private var arguments: String
    @State private var localhostURL: String
    @State private var urlDetectionMode: URLDetectionMode
    @State private var runWithoutTerminal: Bool
    @State private var readySignalPattern: String
    @State private var portDetectionPattern: String
    @State private var customIconPath: String
    @State private var workingDirectory: String
    @State private var scriptSource: ScriptSource
    @State private var inlineScriptContent: String
    
    // Validation errors
    @State private var nameError: String?
    @State private var commandError: String?
    @State private var urlError: String?
    @State private var readySignalError: String?
    @State private var portPatternError: String?
    @State private var iconError: String?
    
    // UI state
    @State private var showingIconPicker = false
    @State private var showingDirectoryPicker = false
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
        onSave: @escaping () -> Void
    ) {
        self.configurationManager = configurationManager
        self.editingConfiguration = editingConfiguration
        self.onSave = onSave
        
        // Initialize state from editing configuration or with defaults
        if let config = editingConfiguration {
            _name = State(initialValue: config.name)
            _command = State(initialValue: config.command)
            _arguments = State(initialValue: config.arguments.joined(separator: " "))
            _localhostURL = State(initialValue: config.localhostURL ?? "")
            _urlDetectionMode = State(initialValue: config.urlDetectionMode)
            _runWithoutTerminal = State(initialValue: config.runWithoutTerminal)
            _readySignalPattern = State(initialValue: config.readySignalPattern ?? "")
            _portDetectionPattern = State(initialValue: config.portDetectionPattern ?? "")
            _customIconPath = State(initialValue: config.customIconPath ?? "")
            _workingDirectory = State(initialValue: config.workingDirectory ?? "")
            _scriptSource = State(initialValue: config.scriptSource)
            _inlineScriptContent = State(initialValue: config.inlineScriptContent ?? "")

            // Auto-expand Advanced if the existing config already uses any advanced option
            let hasAdvanced = !(config.readySignalPattern ?? "").isEmpty
                || !(config.portDetectionPattern ?? "").isEmpty
                || !(config.workingDirectory ?? "").isEmpty
                || config.runWithoutTerminal
            _showAdvanced = State(initialValue: hasAdvanced)
        } else {
            _name = State(initialValue: "")
            _command = State(initialValue: "")
            _arguments = State(initialValue: "")
            _localhostURL = State(initialValue: "http://localhost:3000")
            _urlDetectionMode = State(initialValue: .automatic)
            _runWithoutTerminal = State(initialValue: false)
            _readySignalPattern = State(initialValue: "")
            _portDetectionPattern = State(initialValue: "")
            _customIconPath = State(initialValue: "")
            _workingDirectory = State(initialValue: "")
            _scriptSource = State(initialValue: .command)
            _inlineScriptContent = State(initialValue: "")
            _showAdvanced = State(initialValue: false)
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                // Identity: icon well + name
                Section {
                    HStack(alignment: .center, spacing: 14) {
                        iconWell

                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Name", text: $name, prompt: Text("My Dev Server"))
                                .textFieldStyle(.roundedBorder)
                                .onChange(of: name) { _ in
                                    validateName()
                                }
                                .accessibilityLabel("Configuration Name")
                                .accessibilityHint("Enter a unique name for this server configuration")
                                .accessibilityValue(name.isEmpty ? "Empty" : name)

                            if let error = nameError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            } else if let error = iconError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundStyle(.red)
                            }
                        }
                    }
                }

                // Launch
                Section {
                    Picker("Launch method", selection: $scriptSource) {
                        Text("Command").tag(ScriptSource.command)
                        Text("Script File").tag(ScriptSource.file)
                        Text("Inline").tag(ScriptSource.inline)
                    }
                    .pickerStyle(.segmented)

                    switch scriptSource {
                    case .file:
                        scriptFileFields
                    case .inline:
                        inlineScriptFields
                    case .command:
                        manualCommandFields
                    }
                } header: {
                    Text("Launch")
                } footer: {
                    launchScriptFooter
                }

                // Server URL
                Section {
                    Picker("Address", selection: $urlDetectionMode) {
                        Text("Detect automatically").tag(URLDetectionMode.automatic)
                        Text("Fixed URL").tag(URLDetectionMode.fixed)
                    }
                    .pickerStyle(.segmented)
                    .onChange(of: urlDetectionMode) { _ in probe.reset() }

                    switch urlDetectionMode {
                    case .automatic:
                        automaticDetectionFields
                    case .fixed:
                        fixedURLField
                    }
                } header: {
                    Text("Server")
                } footer: {
                    if urlDetectionMode == .automatic {
                        Text("The app finds the port your server opens — no need to know it in advance. Works even when the server picks a free port automatically. Use \u{201C}Test launch\u{201D} to confirm it now.")
                    } else {
                        Text("Loaded exactly as entered, once the server is ready.")
                    }
                }

                // Advanced options (collapsed by default)
                Section {
                    DisclosureGroup(isExpanded: $showAdvanced) {
                        VStack(alignment: .leading, spacing: 12) {
                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Ready signal pattern", text: $readySignalPattern, prompt: Text("optional · e.g. Ready on"))
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: readySignalPattern) { _ in
                                        validateReadySignal()
                                    }
                                    .help("Regular expression to detect when the server is ready (matched against its output).")
                                    .accessibilityLabel("Ready Signal Pattern")

                                if let error = readySignalError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            VStack(alignment: .leading, spacing: 4) {
                                TextField("Port detection pattern", text: $portDetectionPattern, prompt: Text("optional · e.g. localhost:(\\d+)"))
                                    .textFieldStyle(.roundedBorder)
                                    .onChange(of: portDetectionPattern) { _ in
                                        validatePortPattern()
                                    }
                                    .help("Regular expression to extract the port number from the server output. The first capture group should contain the port.")
                                    .accessibilityLabel("Port Detection Pattern")

                                if let error = portPatternError {
                                    Text(error)
                                        .font(.caption)
                                        .foregroundStyle(.red)
                                }
                            }

                            workingDirectoryField

                            VStack(alignment: .leading, spacing: 4) {
                                Toggle("Run without a terminal", isOn: $runWithoutTerminal)
                                    .help("By default the server runs as if launched in Terminal, so scripts that only start when they detect an interactive terminal work. Turn this on only if a server misbehaves that way.")
                                    .accessibilityLabel("Run without a terminal")

                                Text("Leave off for most servers. Turn on only if a server behaves worse when run as if in a terminal.")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                        }
                        .padding(.top, 6)
                    } label: {
                        Text("Advanced options")
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(editingConfiguration == nil ? "New Configuration" : "Edit Configuration")
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
                    Button("Save") {
                        saveConfiguration()
                    }
                    .keyboardShortcut(.return, modifiers: .command)
                    .disabled(!isValid)
                    .accessibilityLabel("Save Configuration")
                    .accessibilityHint(isValid ? "Saves the configuration" : "Cannot save: form has validation errors")
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
        .frame(minWidth: 600, minHeight: 500)
        .onDisappear { probe.cancel() }
    }
    
    // MARK: - Launch Script Subviews
    
    @ViewBuilder
    private var scriptFileFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                HStack(spacing: 8) {
                    if command.isEmpty {
                        Text("No script selected")
                            .foregroundStyle(.secondary)
                    } else {
                        Label(FileManager.default.displayName(atPath: command), systemImage: "doc.text")
                            .lineLimit(1)
                            .truncationMode(.middle)
                            .help(command)
                    }

                    Spacer()

                    Button(command.isEmpty ? "Choose…" : "Change…") {
                        chooseScriptFile()
                    }
                    .buttonStyle(.bordered)

                    if !command.isEmpty {
                        Button {
                            command = ""
                            workingDirectory = ""
                            commandError = nil
                        } label: {
                            Image(systemName: "xmark.circle.fill")
                                .foregroundStyle(.secondary)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Clear script file")
                    }
                }

                if let error = commandError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            TextField("Arguments", text: $arguments, prompt: Text("optional · extra arguments"))
                .textFieldStyle(.roundedBorder)
                .help("Additional arguments appended after the script path.")
        }
    }

    @ViewBuilder
    private var inlineScriptFields: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextEditor(text: $inlineScriptContent)
                .font(.system(.body, design: .monospaced))
                .frame(minHeight: 120)
                .border(Color.secondary.opacity(0.3))
                .cornerRadius(4)
                .help("Enter the shell script content. It will be saved and executed by the wrapper.")
                .accessibilityLabel("Script content")
        }
    }

    @ViewBuilder
    private var manualCommandFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Command", text: $command, prompt: Text("e.g. npm, python3, /usr/local/bin/node"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: command) { _ in
                        validateCommand()
                    }
                    .help("The executable to run.")

                if let error = commandError {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }

            TextField("Arguments", text: $arguments, prompt: Text("e.g. run dev, -m http.server 8000"))
                .textFieldStyle(.roundedBorder)
                .help("Space-separated arguments to pass to the command.")
        }
    }

    private var workingDirectoryField: some View {
        HStack(spacing: 8) {
            TextField("Working directory", text: $workingDirectory, prompt: Text("optional · e.g. ~/Library/MyServer"))
                .textFieldStyle(.roundedBorder)
                .help(scriptSource == .file
                      ? "Defaults to the script file's location if left empty."
                      : "The directory where the server process will run.")

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
                .accessibilityLabel("Clear working directory")
            }
        }
    }

    private var launchScriptFooter: Text {
        switch scriptSource {
        case .file:
            return Text("Pick a shell script. Its folder is used as the working directory unless you set one under Advanced.")
        case .inline:
            return Text("Type a script to be saved and run by the wrapper.")
        case .command:
            return Text("Specify the executable and its arguments.")
        }
    }

    // MARK: - Server Address Subviews

    /// The fixed-URL text field (used in `.fixed` mode, and as the fallback URL editor).
    private var fixedURLField: some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Localhost URL", text: $localhostURL, prompt: Text("http://localhost:3000"))
                .textFieldStyle(.roundedBorder)
                .onChange(of: localhostURL) { _ in
                    validateURL()
                }
                .help("The URL where your server will be accessible once it's running.")
                .accessibilityLabel("Localhost URL")
                .accessibilityHint("Enter the URL where your server will be accessible")
                .accessibilityValue(localhostURL.isEmpty ? "Empty" : localhostURL)

            if let error = urlError {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }

    /// Automatic-mode content: a status line plus a "Test launch" button that runs the server once
    /// and reports the URL it actually serves.
    @ViewBuilder
    private var automaticDetectionFields: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                probeStatusView
                Spacer()
                probeActionButton
            }
        }
    }

    @ViewBuilder
    private var probeStatusView: some View {
        switch probe.phase {
        case .idle:
            Text("Detected when the server launches.")
                .foregroundStyle(.secondary)
        case .launching:
            HStack(spacing: 8) {
                ProgressView().controlSize(.small)
                Text("Launching server and watching for its port…")
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
                    urlDetectionMode = .fixed
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
                  : "Add a command or script first.")
        }
    }

    /// Whether there's enough in the form to actually launch something.
    private var canTestLaunch: Bool {
        switch scriptSource {
        case .command, .file:
            return !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        case .inline:
            return !inlineScriptContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        }
    }

    /// Build a throwaway configuration from the current form and run the probe against it.
    private func runTestLaunch() {
        probe.start(config: draftConfiguration())
    }

    /// A configuration built from the current editor fields, used for test launches (no persistence).
    private func draftConfiguration() -> ServerConfiguration {
        let parsedArguments = arguments
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map(String.init)
            .filter { !$0.isEmpty }
        let trimmedWorkingDir = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInline = inlineScriptContent.trimmingCharacters(in: .whitespacesAndNewlines)

        return ServerConfiguration(
            name: name.isEmpty ? "Test" : name,
            command: command.trimmingCharacters(in: .whitespacesAndNewlines),
            arguments: parsedArguments,
            localhostURL: localhostURL.isEmpty ? nil : localhostURL.trimmingCharacters(in: .whitespacesAndNewlines),
            urlDetectionMode: urlDetectionMode,
            runWithoutTerminal: runWithoutTerminal,
            workingDirectory: trimmedWorkingDir.isEmpty ? nil : trimmedWorkingDir,
            scriptSource: scriptSource,
            inlineScriptContent: trimmedInline.isEmpty ? nil : trimmedInline
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
            .frame(width: 56, height: 56)
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
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
    /// Whether the form is valid and can be saved
    private var isValid: Bool {
        let nameValid = !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && nameError == nil
        let urlValid = urlError == nil
        let signalValid = readySignalError == nil && portPatternError == nil
        let iconValid = iconError == nil
        
        switch scriptSource {
        case .file:
            return nameValid && !command.isEmpty && commandError == nil && urlValid && signalValid && iconValid
        case .inline:
            let contentValid = !inlineScriptContent.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            return nameValid && contentValid && urlValid && signalValid && iconValid
        case .command:
            let cmdValid = !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && commandError == nil
            return nameValid && cmdValid && urlValid && signalValid && iconValid
        }
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
                nameError = "A configuration with this name already exists"
                return
            }
        }
        
        nameError = nil
    }
    
    private func validateCommand() {
        let trimmedCommand = command.trimmingCharacters(in: .whitespacesAndNewlines)
        
        if trimmedCommand.isEmpty {
            commandError = "Command is required"
            return
        }
        
        let validator = ConfigurationValidator()
        do {
            try validator.validateCommand(trimmedCommand)
            commandError = nil
        } catch let error as ValidationError {
            commandError = error.errorDescription
        } catch {
            commandError = "Invalid command"
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
    
    private func validateReadySignal() {
        let trimmedPattern = readySignalPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Ready signal is optional
        if trimmedPattern.isEmpty {
            readySignalError = nil
            return
        }
        
        let validator = ConfigurationValidator()
        do {
            try validator.validateRegexPattern(trimmedPattern)
            readySignalError = nil
        } catch let error as ValidationError {
            readySignalError = error.errorDescription
        } catch {
            readySignalError = "Invalid regular expression"
        }
    }
    
    private func validatePortPattern() {
        let trimmedPattern = portDetectionPattern.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Port pattern is optional
        if trimmedPattern.isEmpty {
            portPatternError = nil
            return
        }
        
        let validator = ConfigurationValidator()
        do {
            try validator.validateRegexPattern(trimmedPattern)
            portPatternError = nil
        } catch let error as ValidationError {
            portPatternError = error.errorDescription
        } catch {
            portPatternError = "Invalid regular expression"
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
        panel.message = "Choose the working directory for this server"
        
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
            command = url.path
            workingDirectory = url.deletingLastPathComponent().path
            commandError = nil
        }
    }
    
    private func saveConfiguration() {
        // Validate all fields one more time
        validateName()
        validateCommand()
        validateURL()
        validateReadySignal()
        validatePortPattern()
        validateIcon()
        
        guard isValid else {
            errorMessage = "Please fix all validation errors before saving"
            showingError = true
            return
        }
        
        // Parse arguments
        let parsedArguments = arguments
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .split(separator: " ")
            .map { String($0) }
            .filter { !$0.isEmpty }
        
        let trimmedIconPath = customIconPath.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedWorkingDir = workingDirectory.trimmingCharacters(in: .whitespacesAndNewlines)
        let trimmedInlineContent = inlineScriptContent.trimmingCharacters(in: .whitespacesAndNewlines)
        
        // Create or update configuration
        var config: ServerConfiguration
        let configId: UUID
        
        if let existing = editingConfiguration {
            configId = existing.id
            config = ServerConfiguration(
                id: existing.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                arguments: parsedArguments,
                localhostURL: localhostURL.isEmpty ? nil : localhostURL.trimmingCharacters(in: .whitespacesAndNewlines),
                urlDetectionMode: urlDetectionMode,
                runWithoutTerminal: runWithoutTerminal,
                readySignalPattern: readySignalPattern.isEmpty ? nil : readySignalPattern.trimmingCharacters(in: .whitespacesAndNewlines),
                portDetectionPattern: portDetectionPattern.isEmpty ? nil : portDetectionPattern.trimmingCharacters(in: .whitespacesAndNewlines),
                customIconPath: nil, // set below after potential storage
                workingDirectory: trimmedWorkingDir.isEmpty ? nil : trimmedWorkingDir,
                scriptSource: scriptSource,
                inlineScriptContent: trimmedInlineContent.isEmpty ? nil : trimmedInlineContent
            )
            config.createdAt = existing.createdAt
            config.touch()
        } else {
            config = ServerConfiguration(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                arguments: parsedArguments,
                localhostURL: localhostURL.isEmpty ? nil : localhostURL.trimmingCharacters(in: .whitespacesAndNewlines),
                urlDetectionMode: urlDetectionMode,
                runWithoutTerminal: runWithoutTerminal,
                readySignalPattern: readySignalPattern.isEmpty ? nil : readySignalPattern.trimmingCharacters(in: .whitespacesAndNewlines),
                portDetectionPattern: portDetectionPattern.isEmpty ? nil : portDetectionPattern.trimmingCharacters(in: .whitespacesAndNewlines),
                customIconPath: nil, // set below after potential storage
                workingDirectory: trimmedWorkingDir.isEmpty ? nil : trimmedWorkingDir,
                scriptSource: scriptSource,
                inlineScriptContent: trimmedInlineContent.isEmpty ? nil : trimmedInlineContent
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
            
            onSave()
            dismiss()
        } catch {
            errorMessage = "Failed to save configuration: \(error.localizedDescription)"
            showingError = true
        }
    }
}

// MARK: - Preview

#Preview("New Configuration") {
    ConfigurationEditorView(
        configurationManager: ConfigurationManager(),
        editingConfiguration: nil,
        onSave: {}
    )
}

#Preview("Edit Configuration") {
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
        onSave: {}
    )
}
