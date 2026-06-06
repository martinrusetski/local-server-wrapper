//
//  ScriptResolver.swift
//  ServerAppBundle
//

import Foundation

/// Resolves a ServerConfiguration into the actual command and arguments to execute.
/// Handles script file execution, inline script temp file creation, and executable checks.
enum ScriptResolver {
    
    /// Resolved command info
    struct ResolvedCommand {
        let command: String
        let arguments: [String]
    }
    
    /// Resolve the command and arguments from a configuration.
    ///
    /// For `.command` mode, returns command + arguments as-is.
    /// For `.file` mode, returns the script path + extra arguments, wrapping with /bin/sh if not executable.
    /// For `.inline` mode, writes the inline script to a temp file, chmod +x, then resolves like `.file`.
    static func resolve(_ config: ServerConfiguration) -> ResolvedCommand {
        switch config.scriptSource {
        case .command:
            return ResolvedCommand(command: config.command, arguments: config.arguments)
            
        case .file:
            let expanded = (config.command as NSString).expandingTildeInPath
            return resolveFileScript(path: expanded, extraArgs: config.arguments)
            
        case .inline:
            let scriptPath = writeInlineScript(
                content: config.inlineScriptContent ?? "",
                configId: config.id
            )
            return resolveFileScript(path: scriptPath, extraArgs: config.arguments)
        }
    }
    
    // MARK: - Private
    
    private static func resolveFileScript(path: String, extraArgs: [String]) -> ResolvedCommand {
        if FileManager.default.isExecutableFile(atPath: path) {
            return ResolvedCommand(command: path, arguments: extraArgs)
        } else {
            return ResolvedCommand(command: "/bin/sh", arguments: [path] + extraArgs)
        }
    }
    
    private static func writeInlineScript(content: String, configId: UUID) -> String {
        let scriptsDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("LocalServerWrapper")
            .appendingPathComponent("Scripts")
        
        try? FileManager.default.createDirectory(at: scriptsDir, withIntermediateDirectories: true)
        
        let scriptURL = scriptsDir.appendingPathComponent("\(configId.uuidString).sh")
        
        // Write the script
        try? content.write(to: scriptURL, atomically: true, encoding: .utf8)
        
        // Make it executable
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        
        return scriptURL.path
    }
}
