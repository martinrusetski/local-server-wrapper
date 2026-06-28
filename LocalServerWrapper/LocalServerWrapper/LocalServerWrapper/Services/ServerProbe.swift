//
//  ServerProbe.swift
//  LocalServerWrapper
//

import Foundation
import Combine
import Darwin
import os.log

private let logger = OSLog(subsystem: "com.localserverwrapper.configmanager", category: "probe")

/// Launches a configuration's server once, during configuration, purely to discover which URL it
/// serves — then tears it down. This is what powers the editor's "Test launch" button: it answers
/// "how would I know the port without running the server?" by running it for the user and observing
/// the port the OS sees it bind (with a printed-URL scan as a secondary signal).
///
/// It deliberately mirrors how the generated bundle launches a server (same ScriptResolver, same
/// PATH, same OS port observation via PortDetector) so the detected URL matches what the bundle will
/// later load at runtime.
@MainActor
final class ServerProbe: ObservableObject {

    /// Where the probe is in its lifecycle. Drives the editor UI.
    enum Phase: Equatable {
        case idle
        case launching
        case detected(URL)
        case failed(String)
    }

    @Published private(set) var phase: Phase = .idle

    private var process: Process?
    private var rootPID: pid_t?
    private var pollTimer: Timer?
    private var deadlineDate: Date?
    private var outputBuffer = ""
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?

    /// Pseudo-terminal backing the child's stdio in terminal mode (the default). nil in pipe mode.
    private var pty: PseudoTerminal?

    /// How often we ask the OS which port the server is listening on.
    private let pollInterval: TimeInterval = 0.35
    /// How long to wait for a port before giving up.
    private let timeout: TimeInterval = 25

    /// Scheme/host used to present the detected port (taken from the config's fallback URL).
    private var scheme = "http"

    /// Built-in matcher for a loopback URL printed by the server (secondary signal).
    private static let genericURLRegex = try? NSRegularExpression(
        pattern: #"(https?)://(?:localhost|127\.0\.0\.1|0\.0\.0\.0|\[::1\]):(\d+)"#,
        options: [.caseInsensitive]
    )

    var isRunning: Bool { process != nil }

    deinit {
        // Best-effort teardown if the view goes away without calling cancel(). kill() is safe here.
        if let rootPID {
            for pid in PortDetector.processTree(rootPID: rootPID) { kill(pid, SIGKILL) }
        }
        pollTimer?.invalidate()
    }

    // MARK: - Public

    /// Launch the server described by `config` and begin watching for its port.
    func start(config: ServerConfiguration) {
        cancel()  // tear down any previous probe first

        scheme = URL(string: config.localhostURL ?? "")?.scheme ?? "http"
        outputBuffer = ""
        phase = .launching

        let resolved = ScriptResolver.resolve(config)
        let searchDirs = Self.searchPathDirectories()

        let executable: String
        do {
            executable = try Self.resolveExecutable(resolved.command, searchDirectories: searchDirs)
        } catch {
            phase = .failed("Couldn't find the command \"\(resolved.command)\". Check that it's installed and the name or path is correct.")
            return
        }

        let proc = Process()
        proc.executableURL = URL(fileURLWithPath: executable)
        proc.arguments = resolved.arguments

        if let dir = config.workingDirectory, !dir.isEmpty {
            proc.currentDirectoryURL = URL(fileURLWithPath: (dir as NSString).expandingTildeInPath)
        }

        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchDirs.joined(separator: ":")

        // Launch under a pseudo-terminal by default so TTY-gated servers actually start — the test
        // launch must behave identically to the generated bundle (which does the same).
        let activePTY = config.runWithoutTerminal ? nil : PseudoTerminal()
        if let activePTY {
            environment["TERM"] = environment["TERM"] ?? "xterm-256color"
            proc.environment = environment
            proc.standardInput = activePTY.slaveHandle
            proc.standardOutput = activePTY.slaveHandle
            proc.standardError = activePTY.slaveHandle
            self.pty = activePTY
        } else {
            proc.environment = environment
            let outPipe = Pipe()
            let errPipe = Pipe()
            proc.standardOutput = outPipe
            proc.standardError = errPipe
            self.outputPipe = outPipe
            self.errorPipe = errPipe

            let onData: @Sendable (FileHandle) -> Void = { [weak self] handle in
                let data = handle.availableData
                guard !data.isEmpty, let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in self?.appendOutput(text) }
            }
            outPipe.fileHandleForReading.readabilityHandler = onData
            errPipe.fileHandleForReading.readabilityHandler = onData
        }

        proc.terminationHandler = { [weak self] finished in
            Task { @MainActor in self?.handleEarlyExit(status: finished.terminationStatus) }
        }

        do {
            try proc.run()
        } catch {
            phase = .failed("Couldn't launch the server: \(error.localizedDescription)")
            cleanup()
            return
        }

        if let activePTY {
            activePTY.closeSlaveAfterLaunch()
            activePTY.readInBackground(onData: { [weak self] data in
                guard let text = String(data: data, encoding: .utf8) else { return }
                Task { @MainActor in self?.appendOutput(text) }
            }, onEnd: {
                activePTY.closeMaster()
            })
        }

        self.process = proc
        self.rootPID = proc.processIdentifier
        self.deadlineDate = Date().addingTimeInterval(timeout)
        os_log(.info, log: logger, "Probe launched (PID %d): %{public}@", proc.processIdentifier, executable)

        startPolling()
    }

    /// Stop the probe and kill the launched server tree. Safe to call repeatedly.
    func cancel() {
        pollTimer?.invalidate()
        pollTimer = nil
        killTree()
        cleanup()
        if case .launching = phase { phase = .idle }
    }

    /// Reset back to idle (e.g. after the user dismisses a detected/failed result).
    func reset() {
        cancel()
        phase = .idle
    }

    // MARK: - Polling

    private func startPolling() {
        pollTimer = Timer.scheduledTimer(withTimeInterval: pollInterval, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.poll() }
        }
    }

    private func poll() {
        guard isRunning, let rootPID else { return }

        // Secondary signal: a URL printed to the server's own output.
        if let url = Self.extractURL(from: outputBuffer, scheme: scheme) {
            succeed(with: url)
            return
        }

        // Timed out?
        if let deadline = deadlineDate, Date() >= deadline {
            fail(with: "Couldn't detect a server port within \(Int(timeout)) seconds. The server may take longer to start, or it may not open a TCP port.")
            return
        }

        // Primary signal: ask the OS which port the tree is listening on (off the main actor).
        let tree = PortDetector.processTree(rootPID: rootPID)
        Task.detached(priority: .utility) { [weak self] in
            let ports = PortDetector.listeningPorts(for: tree)
            guard let port = ports.first else { return }
            await MainActor.run {
                guard let self, self.isRunning else { return }
                if let url = URL(string: "\(self.scheme)://localhost:\(port)") {
                    self.succeed(with: url)
                }
            }
        }
    }

    private func succeed(with url: URL) {
        os_log(.info, log: logger, "Probe detected URL: %{public}@", url.absoluteString)
        pollTimer?.invalidate()
        pollTimer = nil
        killTree()
        cleanup()
        phase = .detected(url)
    }

    private func fail(with message: String) {
        pollTimer?.invalidate()
        pollTimer = nil
        killTree()
        cleanup()
        phase = .failed(message)
    }

    private func handleEarlyExit(status: Int32) {
        // If we already resolved, ignore (we kill the tree on success).
        guard isRunning else { return }
        let tail = outputBuffer.suffix(400).trimmingCharacters(in: .whitespacesAndNewlines)
        let detail = tail.isEmpty ? "" : "\n\n\(tail)"
        fail(with: "The server exited (code \(status)) before opening a port.\(detail)")
    }

    // MARK: - Output

    private func appendOutput(_ text: String) {
        outputBuffer += text
        // Bound the retained buffer; we only need a recent window for URL scanning + the error tail.
        if outputBuffer.count > 16384 {
            outputBuffer = String(outputBuffer.suffix(16384))
        }
    }

    // MARK: - Teardown

    private func killTree() {
        guard let rootPID else { return }
        let tree = PortDetector.processTree(rootPID: rootPID)
        for pid in tree where kill(pid, 0) == 0 { kill(pid, SIGTERM) }
        // Brief escalation so a stubborn child can't keep holding the port after a test.
        let deadline = Date().addingTimeInterval(1.0)
        while Date() < deadline {
            if tree.allSatisfy({ kill($0, 0) != 0 }) { break }
            usleep(40_000)
        }
        for pid in tree where kill(pid, 0) == 0 { kill(pid, SIGKILL) }
        self.rootPID = nil
    }

    private func cleanup() {
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()
        outputPipe = nil
        errorPipe = nil
        // Drop our reference; the background reader holds its own and closes the master at EOF (which
        // arrives once killTree has stopped the child).
        pty = nil
        process = nil
    }

    // MARK: - Helpers (mirror ProcessManager so the probe matches runtime launch)

    private static func searchPathDirectories() -> [String] {
        [
            "/opt/homebrew/bin", "/usr/local/bin", "/opt/homebrew/sbin", "/usr/local/sbin",
            "/usr/bin", "/bin", "/usr/sbin", "/sbin"
        ]
    }

    private static func resolveExecutable(_ command: String, searchDirectories: [String]) throws -> String {
        struct NotFound: Error {}
        if command.contains("/") {
            guard FileManager.default.isExecutableFile(atPath: command) else { throw NotFound() }
            return command
        }
        for dir in searchDirectories {
            let candidate = (dir as NSString).appendingPathComponent(command)
            if FileManager.default.isExecutableFile(atPath: candidate) { return candidate }
        }
        throw NotFound()
    }

    /// Extract a loopback URL from output, normalizing the host to localhost and keeping the printed
    /// scheme. Falls back to the supplied `scheme` only when building the final URL string.
    private static func extractURL(from output: String, scheme: String) -> URL? {
        guard let regex = genericURLRegex else { return nil }
        let range = NSRange(output.startIndex..., in: output)
        guard let match = regex.firstMatch(in: output, options: [], range: range),
              match.numberOfRanges > 2,
              let schemeRange = Range(match.range(at: 1), in: output),
              let portRange = Range(match.range(at: 2), in: output),
              let port = Int(output[portRange]) else {
            return nil
        }
        let printedScheme = output[schemeRange].lowercased()
        return URL(string: "\(printedScheme)://localhost:\(port)")
    }
}
