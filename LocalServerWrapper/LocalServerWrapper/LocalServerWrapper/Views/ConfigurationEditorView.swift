//
//  ConfigurationEditorView.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import SwiftUI
import UniformTypeIdentifiers

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
    
    // Validation errors
    @State private var nameError: String?
    @State private var commandError: String?
    @State private var urlError: String?
    @State private var readySignalError: String?
    @State private var portPatternError: String?
    @State private var iconError: String?
    
    // UI state
    @State private var showingIconPicker = false
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
        } else {
            _name = State(initialValue: "")
            _command = State(initialValue: "")
            _arguments = State(initialValue: "")
            _localhostURL = State(initialValue: "http://localhost:3000")
            _readySignalPattern = State(initialValue: "")
            _portDetectionPattern = State(initialValue: "")
            _customIconPath = State(initialValue: "")
        }
    }
    
    // MARK: - Body
    
    var body: some View {
        NavigationStack {
            Form {
                // Basic Information Section
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
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Command", text: $command, prompt: Text("e.g., npm, python3, /usr/local/bin/node"))
                            .textFieldStyle(.roundedBorder)
                            .onChange(of: command) { _ in
                                validateCommand()
                            }
                            .accessibilityLabel("Command")
                            .accessibilityHint("Enter the command to execute, such as npm or python3")
                            .accessibilityValue(command.isEmpty ? "Empty" : command)
                        
                        if let error = commandError {
                            Text(error)
                                .font(.caption)
                                .foregroundColor(.red)
                        } else {
                            Text("The command to execute (e.g., npm, python3)")
                                .font(.caption)
                                .foregroundColor(.secondary)
                        }
                    }
                    
                    VStack(alignment: .leading, spacing: 4) {
                        TextField("Arguments", text: $arguments, prompt: Text("e.g., run dev, -m http.server 8000"))
                            .textFieldStyle(.roundedBorder)
                            .accessibilityLabel("Arguments")
                            .accessibilityHint("Enter space-separated arguments to pass to the command")
                            .accessibilityValue(arguments.isEmpty ? "Empty" : arguments)
                        
                        Text("Space-separated arguments to pass to the command")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                } header: {
                    Text("Basic Information")
                } footer: {
                    Text("Name and command are required fields")
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
    
    // MARK: - Computed Properties
    
    /// Whether the form is valid and can be saved
    private var isValid: Bool {
        return nameError == nil &&
               commandError == nil &&
               urlError == nil &&
               readySignalError == nil &&
               portPatternError == nil &&
               iconError == nil &&
               !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty &&
               !command.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
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
        
        // Create or update configuration
        var config: ServerConfiguration
        
        if let existing = editingConfiguration {
            // Update existing configuration
            config = ServerConfiguration(
                id: existing.id,
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                arguments: parsedArguments,
                localhostURL: localhostURL.isEmpty ? nil : localhostURL.trimmingCharacters(in: .whitespacesAndNewlines),
                readySignalPattern: readySignalPattern.isEmpty ? nil : readySignalPattern.trimmingCharacters(in: .whitespacesAndNewlines),
                portDetectionPattern: portDetectionPattern.isEmpty ? nil : portDetectionPattern.trimmingCharacters(in: .whitespacesAndNewlines),
                customIconPath: customIconPath.isEmpty ? nil : customIconPath.trimmingCharacters(in: .whitespacesAndNewlines)
            )
            config.createdAt = existing.createdAt
            config.touch()
        } else {
            // Create new configuration
            config = ServerConfiguration(
                name: name.trimmingCharacters(in: .whitespacesAndNewlines),
                command: command.trimmingCharacters(in: .whitespacesAndNewlines),
                arguments: parsedArguments,
                localhostURL: localhostURL.isEmpty ? nil : localhostURL.trimmingCharacters(in: .whitespacesAndNewlines),
                readySignalPattern: readySignalPattern.isEmpty ? nil : readySignalPattern.trimmingCharacters(in: .whitespacesAndNewlines),
                portDetectionPattern: portDetectionPattern.isEmpty ? nil : portDetectionPattern.trimmingCharacters(in: .whitespacesAndNewlines),
                customIconPath: customIconPath.isEmpty ? nil : customIconPath.trimmingCharacters(in: .whitespacesAndNewlines)
            )
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
