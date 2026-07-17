//
//  ScriptResolver.swift
//  LocalServerWrapper
//

import Foundation

// NOTE: This type is DUPLICATED across both Xcode projects and must be kept byte-identical
// (modulo this file's top header comment):
//   - ServerAppBundle/ServerAppBundle/ScriptResolver.swift               (runtime)
//   - LocalServerWrapper/.../LocalServerWrapper/Utilities/ScriptResolver.swift (manager)
// Any change here MUST be mirrored in the twin. See docs/IMPLEMENTATION_SPEC.md §1.

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

        // Ensure the script runs through a shell. Inline content is arbitrary shell text
        // (e.g. "npm run dev" or a multi-line script) that is executed directly via posix_spawn,
        // which fails with ENOEXEC unless the file starts with a shebang. Prepend one when the
        // author hasn't provided their own, so plain commands and multi-line scripts both run.
        let trimmedLeading = content.drop(while: { $0 == " " || $0 == "\t" || $0 == "\n" })
        let scriptBody: String
        if trimmedLeading.hasPrefix("#!") {
            scriptBody = content
        } else {
            scriptBody = "#!/bin/zsh\n" + content
        }

        // Write the script
        try? scriptBody.write(to: scriptURL, atomically: true, encoding: .utf8)
        
        // Make it executable
        try? FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: scriptURL.path)
        
        return scriptURL.path
    }
}
