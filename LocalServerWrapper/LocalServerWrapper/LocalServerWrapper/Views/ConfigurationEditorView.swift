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
            _readySignalPattern = State(initialValue: config.readySignalPattern ?? "")
            _portDetectionPattern = State(initialValue: config.portDetectionPattern ?? "")
            _customIconPath = State(initialValue: config.customIconPath ?? "")
            _workingDirectory = State(initialValue: config.workingDirectory ?? "")
            _scriptSource = State(initialValue: config.scriptSource)
            _inlineScriptContent = State(initialValue: config.inlineScriptContent ?? "")
        } else {
            _name = State(initialValue: "")
            _command = State(initialValue: "")
            _arguments = State(initialValue: "")
            _localhostURL = State(initialValue: "http://localhost:3000")
            _readySignalPattern = State(initialValue: "")
            _portDetectionPattern = State(initialValue: "")
            _customIconPath = State(initialValue: "")
            _workingDirectory = State(initialValue: "")
            _scriptSource = State(initialValue: .command)
            _inlineScriptContent = State(initialValue: "")
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                // Configuration Name Section
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Configuration Name", text: $name)
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
                                .foregroundColor(.red)
                        }
                    }
                } header: {
                    Text("Configuration")
                } footer: {
                    Text("Name is required")
                }
                
                // Launch Script Section
                Section {
                    Picker("Launch Method", selection: $scriptSource) {
                        Text("Script File — pick a .sh file on disk").tag(ScriptSource.file)
                        Text("Inline Script — type a script directly").tag(ScriptSource.inline)
                        Text("Manual Command — specify executable + args").tag(ScriptSource.command)
                    }
                    .pickerStyle(.radioGroup)
                    
                    Divider()
                        .padding(.vertical, 4)
                    
                    switch scriptSource {
                    case .file:
                        scriptFileFields
                    case .inline:
                        inlineScriptFields
                    case .command:
                        manualCommandFields
                    }
                } header: {
                    Text("Launch Script")
                } footer: {
                    launchScriptFooter
                }
                
                // Server Configuration Section
                Section {
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Localhost URL", text: $localhostURL, prompt: Text("http://localhost:3000"))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: localhostURL) { _ in
                                validateURL()
                            }
                            .accessibilityLabel("Localhost URL")
                            .accessibilityHint("Enter the URL where your server will be accessible")
                            .accessibilityValue(localhostURL.isEmpty ? "Empty" : localhostURL)
                        
                        if let error = urlError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("The URL where your server will be accessible")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Ready Signal Pattern", text: $readySignalPattern, prompt: Text("e.g., Server listening on, Ready on"))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: readySignalPattern) { _ in
                                validateReadySignal()
                            }
                            .accessibilityLabel("Ready Signal Pattern")
                            .accessibilityHint("Enter a regular expression to detect when the server is ready")
                            .accessibilityValue(readySignalPattern.isEmpty ? "Empty" : readySignalPattern)
                        
                        if let error = readySignalError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("Regular expression to detect when the server is ready")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Port Detection Pattern", text: $portDetectionPattern, prompt: Text("e.g., port (\\d+), localhost:(\\d+)"))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: portDetectionPattern) { _ in
                                validatePortPattern()
                            }
                            .accessibilityLabel("Port Detection Pattern")
                            .accessibilityHint("Enter a regular expression to extract port number from server output")
                            .accessibilityValue(portDetectionPattern.isEmpty ? "Empty" : portDetectionPattern)
                        
                        if let error = portPatternError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("Regular expression to extract port number (first capture group)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                } header: {
                    Text("Server Configuration")
                } footer: {
                    Text("Configure how the app detects when your server is ready")
                }
                
                // Appearance Section
                Section {
                    HStack {
                        VStack(alignment: .leading, spacing: 4) {
                            TextField("Custom Icon Path", text: $customIconPath, prompt: Text("Optional"))
                                .textFieldStyle(.roundedBorder)
                                .disabled(true)
                                .accessibilityLabel("Custom Icon Path")
                                .accessibilityHint("Shows the selected icon file path")
                                .accessibilityValue(customIconPath.isEmpty ? "No icon selected" : customIconPath)
                            
                            if let error = iconError {
                                Text(error)
                                    .font(.caption)
                                    .foregroundColor(.red)
                            } else if !customIconPath.isEmpty {
                                Text(customIconPath)
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                                    .lineLimit(1)
                                    .truncationMode(.middle)
                            } else {
                                Text("Choose a custom icon for the generated app bundle")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                        }
                        
                        Button("Choose...") {
                            showingIconPicker = true
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Choose Icon")
                        .accessibilityHint("Opens file picker to select a custom icon image")
                        
                        if !customIconPath.isEmpty {
                            Button {
                                customIconPath = ""
                                iconError = nil
                            } label: {
                                Image(systemName: "xmark.circle.fill")
                                    .foregroundColor(.secondary)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel("Clear Icon")
                            .accessibilityHint("Removes the selected custom icon")
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("A default icon will be used if no custom icon is provided")
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
    }
    
    // MARK: - Launch Script Subviews
    
    @ViewBuilder
    private var scriptFileFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    TextField("Script File", text: .constant(command.isEmpty ? "" : command))
                        .textFieldStyle(.roundedBorder)
                        .disabled(true)
                    
                    if command.isEmpty {
                        Text("Choose a shell script to run")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    } else {
                        Text(FileManager.default.displayName(atPath: command))
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    if let error = commandError {
                        Text(error)
                            .font(.caption)
                            .foregroundColor(.red)
                    }
                }
                
                Button("Choose...") {
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
                            .foregroundColor(.secondary)
                    }
                    .buttonStyle(.plain)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                TextField("Arguments", text: $arguments, prompt: Text("Extra arguments (optional)"))
                    .textFieldStyle(.roundedBorder)
                Text("Additional arguments appended after the script path")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        workingDirectoryField
    }
    
    @ViewBuilder
    private var inlineScriptFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Script Content")
                    .font(.subheadline)
                    .foregroundColor(.secondary)
                
                TextEditor(text: $inlineScriptContent)
                    .font(.system(.body, design: .monospaced))
                    .frame(minHeight: 120)
                    .border(Color.secondary.opacity(0.3))
                    .cornerRadius(4)
                
                Text("Enter the shell script content. It will be saved and executed by the wrapper.")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        workingDirectoryField
    }
    
    @ViewBuilder
    private var manualCommandFields: some View {
        VStack(alignment: .leading, spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Command", text: $command, prompt: Text("e.g., npm, python3, /usr/local/bin/node"))
                    .textFieldStyle(.roundedBorder)
                    .onChange(of: command) { _ in
                        validateCommand()
                    }
                
                if let error = commandError {
                    Text(error)
                        .font(.caption)
                        .foregroundColor(.red)
                } else {
                    Text("The executable to run")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            VStack(alignment: .leading, spacing: 4) {
                TextField("Arguments", text: $arguments, prompt: Text("e.g., run dev, -m http.server 8000"))
                    .textFieldStyle(.roundedBorder)
                Text("Space-separated arguments to pass to the command")
                    .font(.caption)
                    .foregroundColor(.secondary)
            }
        }
        workingDirectoryField
    }
    
    private var workingDirectoryField: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                TextField("Working Directory", text: $workingDirectory, prompt: Text("Optional (e.g., ~/Library/MyServer)"))
                    .textFieldStyle(.roundedBorder)
                
                if !workingDirectory.isEmpty {
                    Text(workingDirectory)
                        .font(.caption)
                        .foregroundColor(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                } else if scriptSource == .file {
                    Text("Auto-detected from the script file location")
                        .font(.caption)
                        .foregroundColor(.secondary)
                } else {
                    Text("The directory where the server process will run")
                        .font(.caption)
                        .foregroundColor(.secondary)
                }
            }
            
            Button("Choose...") {
                chooseWorkingDirectory()
            }
            .buttonStyle(.bordered)
            
            if !workingDirectory.isEmpty {
                Button {
                    workingDirectory = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundColor(.secondary)
                }
                .buttonStyle(.plain)
            }
        }
    }
    
    private var launchScriptFooter: Text {
        switch scriptSource {
        case .file:
            return Text("Pick a shell script. The working directory is automatically set to the script's location.")
        case .inline:
            return Text("Enter your script content and specify a working directory below.")
        case .command:
            return Text("Manually specify the executable and its arguments.")
        }
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
