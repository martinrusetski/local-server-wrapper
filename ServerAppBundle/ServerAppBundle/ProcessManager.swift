//
//  ProcessManager.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import Foundation
import Combine
import os.log

/// Logger for process management operations
private let logger = OSLog(subsystem: "com.localserverwrapper.serverappbundle", category: "process")

/// Protocol defining the interface for managing server processes
@MainActor
protocol ProcessManagerProtocol: ObservableObject {
    /// Whether the process is currently running
    var isRunning: Bool { get }
    
    /// The exit code of the process (nil if still running or not started)
    var exitCode: Int32? { get }
    
    /// The accumulated output from stdout and stderr
    var output: String { get }
    
    /// Start the server process with the given command and arguments
    /// - Parameters:
    ///   - command: The command to execute (e.g., "/usr/bin/npm", "python3")
    ///   - arguments: The command-line arguments
    /// - Throws: ProcessError if the process fails to start
    func start(command: String, arguments: [String]) throws
    
    /// Gracefully terminate the process (SIGTERM)
    func terminate()
    
    /// Forcefully kill the process (SIGKILL)
    func forceKill()
}

/// Errors that can occur during process management
enum ProcessError: Error, LocalizedError {
    case commandNotFound(String)
    case permissionDenied(String)
    case alreadyRunning
    case notRunning
    case startFailed(String)
    
    var errorDescription: String? {
        switch self {
        case .commandNotFound(let command):
            return "Command not found: \(command)"
        case .permissionDenied(let command):
            return "Permission denied: \(command)"
        case .alreadyRunning:
            return "Process is already running"
        case .notRunning:
            return "Process is not running"
        case .startFailed(let reason):
            return "Failed to start process: \(reason)"
        }
    }
}

/// Manages the lifecycle of a server process, capturing output and monitoring state
@MainActor
class ProcessManager: ProcessManagerProtocol {
    // MARK: - Published Properties
    
    @Published private(set) var isRunning: Bool = false
    @Published private(set) var exitCode: Int32?
    @Published private(set) var output: String = ""
    
    // MARK: - Private Properties
    
    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var terminationObserver: NSObjectProtocol?
    private var cancellables = Set<AnyCancellable>()
    
    // MARK: - Initialization
    
    init() {}
    
    // Note: deinit cannot be marked with @MainActor, so cleanup is done synchronously
    // This is safe because deinit is called when the object is being deallocated
    deinit {
        // Remove termination observer
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
        }
        
        // Close pipe handlers
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        
        // Close pipes
        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()
    }
    
    // MARK: - Public Methods
    
    func start(command: String, arguments: [String]) throws {
        os_log(.info, log: logger, "Starting process: %{public}@", command)
        
        // Check if already running
        guard !isRunning else {
            os_log(.error, log: logger, "Process already running")
            throw ProcessError.alreadyRunning
        }
        
        // Verify command exists
        guard FileManager.default.isExecutableFile(atPath: command) else {
            os_log(.error, log: logger, "Command not found or not executable: %{public}@", command)
            throw ProcessError.commandNotFound(command)
        }
        
        os_log(.debug, log: logger, "Command verified, arguments: %{public}@", arguments.joined(separator: " "))
        
        // Create new process
        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: command)
        newProcess.arguments = arguments
        
        // Set up pipes for stdout and stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        newProcess.standardOutput = stdoutPipe
        newProcess.standardError = stderrPipe
        
        // Store pipes for cleanup
        self.outputPipe = stdoutPipe
        self.errorPipe = stderrPipe
        
        // Set up output capture for stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let string = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in
                    self?.appendOutput(string)
                }
            }
        }
        
        // Set up output capture for stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let string = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in
                    self?.appendOutput(string)
                }
            }
        }
        
        // Observe process termination
        terminationObserver = NotificationCenter.default.addObserver(
            forName: Process.didTerminateNotification,
            object: newProcess,
            queue: .main
        ) { [weak self] notification in
            guard let self = self,
                  let terminatedProcess = notification.object as? Process else {
                return
            }
            
            Task { @MainActor in
                self.handleProcessTermination(terminatedProcess)
            }
        }
        
        // Start the process
        do {
            try newProcess.run()
            self.process = newProcess
            self.isRunning = true
            self.exitCode = nil
            
            os_log(.info, log: logger, "Process started successfully (PID: %d)", newProcess.processIdentifier)
            
            // Add initial output message
            let commandString = ([command] + arguments).joined(separator: " ")
            appendOutput("Starting process: \(commandString)\n")
            
        } catch {
            os_log(.error, log: logger, "Failed to start process: %{public}@", error.localizedDescription)
            cleanup()
            throw ProcessError.startFailed(error.localizedDescription)
        }
    }
    
    func terminate() {
        guard let process = process, isRunning else {
            os_log(.info, log: logger, "No process to terminate")
            return
        }
        
        os_log(.info, log: logger, "Terminating process (PID: %d)", process.processIdentifier)
        appendOutput("\n[Process terminating...]\n")
        process.terminate()
    }
    
    func forceKill() {
        guard let process = process else {
            os_log(.info, log: logger, "No process to kill")
            return
        }
        
        os_log(.error, log: logger, "Force killing process (PID: %d)", process.processIdentifier)
        appendOutput("\n[Process force killed]\n")
        
        // Send SIGKILL
        kill(process.processIdentifier, SIGKILL)
        
        // Clean up immediately
        cleanup()
        isRunning = false
    }
    
    // MARK: - Private Methods
    
    private func appendOutput(_ text: String) {
        output += text
    }
    
    private func handleProcessTermination(_ process: Process) {
        let code = process.terminationStatus
        self.exitCode = code
        self.isRunning = false
        
        os_log(.info, log: logger, "Process terminated with exit code: %d", code)
        
        // Close pipe handlers to flush any remaining output
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        
        // Add termination message
        if code == 0 {
            appendOutput("\n[Process exited with code 0]\n")
        } else {
            appendOutput("\n[Process exited with code \(code)]\n")
            os_log(.error, log: logger, "Process exited with non-zero code: %d", code)
        }
        
        // Clean up resources
        cleanup()
    }
    
    private func cleanup() {
        // Remove termination observer
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
            terminationObserver = nil
        }
        
        // Close pipe handlers
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        
        // Close pipes
        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()
        
        outputPipe = nil
        errorPipe = nil
        
        // Clear process reference
        process = nil
    }
}
