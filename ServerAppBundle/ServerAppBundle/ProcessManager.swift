//
//  ProcessManager.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import Foundation
import Combine
import Darwin
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
    
    /// The accumulated output from stdout and stderr, as plain text (ANSI escape codes interpreted
    /// and removed). Used for the log buffer, accessibility, and tests.
    var output: String { get }

    /// The accumulated output rendered with ANSI colors/styles for display.
    var attributedOutput: AttributedString { get }
    
    /// Start the server process with the given command and arguments
    /// - Parameters:
    ///   - command: The command to execute (e.g., "/usr/bin/npm", "python3")
    ///   - arguments: The command-line arguments
    ///   - workingDirectory: Directory where the process runs (nil for default)
    /// - Throws: ProcessError if the process fails to start
    func start(command: String, arguments: [String], workingDirectory: String?) throws
    
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
    @Published private(set) var attributedOutput = AttributedString()
    @Published private(set) var isAutoAnswering: Bool = false

    /// Emits each newly-appended output chunk (not the whole buffer). Used by readiness
    /// detection so scanning stays incremental instead of re-scanning the full accumulated output.
    let outputChunks = PassthroughSubject<String, Never>()

    // MARK: - Private Properties

    /// ANSI terminal emulator that turns the raw byte stream into colored, control-code-aware
    /// output. Bounds its own retained buffer by line count (TASK-3). Main-actor only.
    private let terminal = ANSITerminal()

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var inputPipe: Pipe?
    private var autoAnswerTimer: Timer?
    private var terminationObserver: NSObjectProtocol?
    /// Scheduled SIGKILL escalation for a terminating process tree (TASK-2). Captures the PID
    /// list so it can reap orphaned grandchildren even after the direct child has exited.
    private var forceKillWorkItem: DispatchWorkItem?
    private var cancellables = Set<AnyCancellable>()
    
    /// Directories prepended (in order) to the child process PATH.
    /// Used to inject the browser-open shim so launch scripts can't pop the system browser.
    var additionalPathDirectories: [String] = []
    
    /// Extra environment variables merged into the child process environment.
    var additionalEnvironment: [String: String] = [:]
    
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
        try? inputPipe?.fileHandleForWriting.close()
    }
    
    // MARK: - Public Methods
    
    func start(command: String, arguments: [String], workingDirectory: String? = nil) throws {
        os_log(.info, log: logger, "Starting process: %{public}@", command)
        
        // Check if already running
        guard !isRunning else {
            os_log(.error, log: logger, "Process already running")
            throw ProcessError.alreadyRunning
        }
        
        // Resolve the executable. Foundation's Process does NOT do PATH lookup for
        // `executableURL`, so a bare command like "npm" must be resolved to an absolute path
        // ourselves over the same PATH the child will inherit (TASK-1).
        let searchDirectories = Self.searchPathDirectories(additional: additionalPathDirectories)
        let resolvedCommand = try Self.resolveExecutable(command, searchDirectories: searchDirectories)

        os_log(.debug, log: logger, "Command resolved to %{public}@, arguments: %{public}@", resolvedCommand, arguments.joined(separator: " "))

        // Create new process
        let newProcess = Process()
        newProcess.executableURL = URL(fileURLWithPath: resolvedCommand)
        newProcess.arguments = arguments
        
        // Set working directory if provided
        if let dir = workingDirectory {
            let dirURL = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
            newProcess.currentDirectoryURL = dirURL
            os_log(.debug, log: logger, "Working directory: %{public}@", dirURL.path)
        }
        
        // Set up environment with proper PATH (same list used for executable resolution above).
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchDirectories.joined(separator: ":")
        for (key, value) in additionalEnvironment {
            environment[key] = value
        }
        newProcess.environment = environment
        
        // Set up pipes for stdout and stderr
        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        newProcess.standardOutput = stdoutPipe
        newProcess.standardError = stderrPipe
        
        // Set up stdin pipe for interactive input
        let stdinPipe = Pipe()
        newProcess.standardInput = stdinPipe
        self.inputPipe = stdinPipe
        
        // Store pipes for cleanup
        self.outputPipe = stdoutPipe
        self.errorPipe = stderrPipe
        
        // Decode each stream across read-chunk boundaries. `availableData` can split a multi-byte
        // UTF-8 character; `String(data:encoding:.utf8)` returns nil for that chunk and the whole
        // read used to be dropped (garbled/missing output). Each decoder is captured by exactly one
        // handler and the readability queue is serial per pipe, so it is accessed serially.
        let stdoutDecoder = UTF8StreamDecoder()
        let stderrDecoder = UTF8StreamDecoder()

        // Set up output capture for stdout
        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let string = stdoutDecoder.decode(data)
            guard !string.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.appendOutput(string)
            }
        }

        // Set up output capture for stderr
        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            guard !data.isEmpty else { return }
            let string = stderrDecoder.decode(data)
            guard !string.isEmpty else { return }
            Task { @MainActor [weak self] in
                self?.appendOutput(string)
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

            // Auto-answering is OFF by default (TASK-10). Blindly writing newlines to stdin can
            // confirm destructive defaults on interactive prompts. The user opts in from TerminalView.

            // Add initial output message
            let commandString = ([resolvedCommand] + arguments).joined(separator: " ")
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

        let pid = process.processIdentifier
        os_log(.info, log: logger, "Terminating process tree (root PID: %d)", pid)
        appendOutput("\n[Process terminating...]\n")

        // Capture the full descendant tree BEFORE signalling. Killing only the direct child
        // (e.g. `npm`) orphans grandchildren (e.g. `node`) which keep holding the port (TASK-2).
        // Collecting first avoids missing grandchildren that get reparented to launchd on exit.
        let tree = Self.processTree(rootPID: pid)
        for target in tree {
            kill(target, SIGTERM)
        }

        // Escalate to SIGKILL for anything still alive after a grace period. This runs even if
        // the direct child has already exited, so orphaned grandchildren still get reaped.
        scheduleForceKillEscalation(for: tree)
    }

    func forceKill() {
        guard let process = process else {
            os_log(.info, log: logger, "No process to kill")
            return
        }

        let pid = process.processIdentifier
        os_log(.error, log: logger, "Force killing process tree (root PID: %d)", pid)
        appendOutput("\n[Process force killed]\n")

        // SIGKILL the whole tree, not just the direct child.
        for target in Self.processTree(rootPID: pid) {
            kill(target, SIGKILL)
        }

        forceKillWorkItem?.cancel()
        forceKillWorkItem = nil

        // Clean up immediately
        cleanup()
        isRunning = false
    }

    /// Synchronously kill the whole process tree and block (briefly) until it is gone.
    /// Use this on the app-quit path: the async SIGKILL escalation used by `terminate()` races
    /// app exit and can leave orphaned grandchildren holding the port (TASK-2). This guarantees
    /// the tree is dead before the app process exits.
    func terminateSynchronously(gracePeriod: TimeInterval = 1.5) {
        guard let process = process, isRunning else { return }

        let pid = process.processIdentifier
        os_log(.info, log: logger, "Synchronously terminating process tree (root PID: %d)", pid)

        let tree = Self.processTree(rootPID: pid)
        forceKillWorkItem?.cancel()
        forceKillWorkItem = nil

        for target in tree { kill(target, SIGTERM) }

        // Poll for graceful exit, then SIGKILL anything still alive.
        let deadline = Date().addingTimeInterval(gracePeriod)
        while Date() < deadline {
            if tree.allSatisfy({ kill($0, 0) != 0 }) { break }
            usleep(50_000) // 50ms
        }
        for target in tree where kill(target, 0) == 0 {
            os_log(.error, log: logger, "Process %d still alive at quit, sending SIGKILL", target)
            kill(target, SIGKILL)
        }
        usleep(100_000) // give SIGKILL a moment to take effect before the app exits
    }

    /// After a grace period, SIGKILL any PID in `tree` that is still alive.
    private func scheduleForceKillEscalation(for tree: [pid_t]) {
        forceKillWorkItem?.cancel()

        let work = DispatchWorkItem {
            for target in tree where kill(target, 0) == 0 {
                os_log(.error, log: logger, "Process %d ignored SIGTERM, sending SIGKILL", target)
                kill(target, SIGKILL)
            }
        }
        forceKillWorkItem = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 3.0, execute: work)
    }
    
    func writeInput(_ text: String) {
        guard let pipe = inputPipe, isRunning, !text.isEmpty else { return }
        if let data = (text + "\n").data(using: .utf8) {
            pipe.fileHandleForWriting.write(data)
        }
    }
    
    func startAutoAnswering() {
        guard !isAutoAnswering else { return }
        isAutoAnswering = true
        
        autoAnswerTimer = Timer.scheduledTimer(withTimeInterval: 3.0, repeats: true) { [weak self] _ in
            guard let self = self, self.isAutoAnswering, self.isRunning else { return }
            if let pipe = self.inputPipe, let data = "\n".data(using: .utf8) {
                pipe.fileHandleForWriting.write(data)
            }
        }
    }
    
    func stopAutoAnswering() {
        isAutoAnswering = false
        autoAnswerTimer?.invalidate()
        autoAnswerTimer = nil
    }
    
    // MARK: - Private Methods
    
    private func appendOutput(_ text: String) {
        // Interpret ANSI escapes / control codes and update both the plain and colored renders.
        // The emulator bounds its own buffer by line count, so the retained output stays bounded.
        terminal.feed(text)
        output = terminal.plainText
        attributedOutput = terminal.attributedString()

        // Feed only the new chunk to readiness detection (incremental scan, not full re-scan),
        // with ANSI codes stripped so they can't break ready-signal / port regexes.
        outputChunks.send(ANSITerminal.strip(text))
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
        // Stop auto-answering
        stopAutoAnswering()
        
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
        try? inputPipe?.fileHandleForWriting.close()
        
        outputPipe = nil
        errorPipe = nil
        inputPipe = nil
        
        // Clear process reference
        process = nil
    }

    // MARK: - Executable resolution (TASK-1)

    /// The directories searched (in order) for a bare command name, and used to build the
    /// child PATH. Centralised so resolution and the child environment never disagree.
    static func searchPathDirectories(additional: [String]) -> [String] {
        let homebrewPaths = [
            "/opt/homebrew/bin",      // Apple Silicon Homebrew
            "/usr/local/bin",         // Intel Homebrew
            "/opt/homebrew/sbin",
            "/usr/local/sbin"
        ]
        let systemPaths = [
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        return additional + homebrewPaths + systemPaths
    }

    /// Resolve a command to an absolute executable path.
    /// - Paths containing "/" are used as-is (after an executable check).
    /// - Bare names are looked up over `searchDirectories`, `which`-style.
    /// - Throws `commandNotFound` if nothing executable is found.
    static func resolveExecutable(_ command: String, searchDirectories: [String]) throws -> String {
        if command.contains("/") {
            guard FileManager.default.isExecutableFile(atPath: command) else {
                throw ProcessError.commandNotFound(command)
            }
            return command
        }

        for dir in searchDirectories {
            let candidate = (dir as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate) {
                return candidate
            }
        }
        throw ProcessError.commandNotFound(command)
    }

    // MARK: - Process tree (TASK-2)

    /// Returns `rootPID` plus all of its descendant PIDs, so terminate/forceKill can signal the
    /// entire tree (e.g. `npm` → `node`, or `start.sh` → `uvicorn`) rather than orphaning
    /// grandchildren that hold the port.
    ///
    /// Built from a full `sysctl(KERN_PROC_ALL)` parent map. (We do NOT use `proc_listchildpids`:
    /// its return-value semantics are unreliable — empirically it under-reports children and the
    /// NULL-size query returns a bogus length — which previously caused the walk to find zero
    /// children and leave the real server process orphaned holding the port.)
    static func processTree(rootPID: pid_t) -> [pid_t] {
        var childrenOf: [pid_t: [pid_t]] = [:]
        for entry in processParentPairs() {
            childrenOf[entry.ppid, default: []].append(entry.pid)
        }

        var collected: [pid_t] = [rootPID]
        var queue: [pid_t] = [rootPID]
        while let parent = queue.popLast() {
            for child in childrenOf[parent] ?? [] where !collected.contains(child) {
                collected.append(child)
                queue.append(child)
            }
        }
        return collected
    }

    /// (pid, ppid) for every process on the system, via `sysctl(KERN_PROC_ALL)`.
    private static func processParentPairs() -> [(pid: pid_t, ppid: pid_t)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [] }

        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: length / stride + 1)
        guard sysctl(&mib, UInt32(mib.count), &procs, &length, nil, 0) == 0 else { return [] }

        let count = length / stride
        return procs.prefix(count).map { (pid: $0.kp_proc.p_pid, ppid: $0.kp_eproc.e_ppid) }
    }
}

/// Decodes a byte stream into UTF-8 text across chunk boundaries.
///
/// `FileHandle.availableData` can return a chunk that ends in the middle of a multi-byte UTF-8
/// character (common with box-drawing glyphs, emoji, and spinner runes). `String(data:encoding:)`
/// returns nil for such a chunk, which previously dropped the entire read and produced garbled or
/// missing output. This holds the incomplete trailing bytes until the next read completes them.
///
/// Not internally synchronized: each instance is used by exactly one pipe's serial readability
/// queue, so access is already serialized. Marked `@unchecked Sendable` only to satisfy capture in
/// the `@Sendable` readability handler.
final class UTF8StreamDecoder: @unchecked Sendable {
    private var leftover = Data()

    func decode(_ newData: Data) -> String {
        var data = leftover
        data.append(newData)

        let hold = Self.incompleteTrailingByteCount(data)
        if hold > 0 {
            let split = data.count - hold
            leftover = data.subdata(in: split..<data.count)
            data = data.subdata(in: 0..<split)
        } else {
            leftover = Data()
        }
        // Boundary-correct: any remaining invalid bytes (genuinely malformed, not split) become
        // U+FFFD rather than dropping output.
        return String(decoding: data, as: UTF8.self)
    }

    /// Number of trailing bytes that form an incomplete (not-yet-terminated) UTF-8 sequence and
    /// should be withheld until more bytes arrive. Returns 0 when the data ends on a boundary.
    private static func incompleteTrailingByteCount(_ data: Data) -> Int {
        let bytes = [UInt8](data)
        let n = bytes.count
        guard n > 0 else { return 0 }

        // Walk back over continuation bytes (0b10xxxxxx) to find the last lead byte.
        var i = n - 1
        var continuations = 0
        while i >= 0, (bytes[i] & 0xC0) == 0x80, continuations < 3 {
            continuations += 1
            i -= 1
        }
        guard i >= 0 else { return 0 } // all continuation bytes: malformed, let them be replaced

        let lead = bytes[i]
        let expected: Int
        if lead & 0x80 == 0 { expected = 1 }
        else if lead & 0xE0 == 0xC0 { expected = 2 }
        else if lead & 0xF0 == 0xE0 { expected = 3 }
        else if lead & 0xF8 == 0xF0 { expected = 4 }
        else { return 0 } // invalid lead byte: let it be replaced rather than withheld

        let have = n - i // bytes from the lead byte to the end, inclusive
        return have < expected ? have : 0
    }
}
