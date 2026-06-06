//
//  TestRunManager.swift
//  LocalServerWrapper
//

import Foundation
import Combine
import os.log

private let logger = OSLog(subsystem: "com.localserverwrapper.configmanager", category: "testrun")

@MainActor
class TestRunManager: ObservableObject {
    @Published var output: String = ""
    @Published var isRunning: Bool = false
    @Published var exitCode: Int32?
    @Published var isReady: Bool = false
    @Published var detectedURL: URL?
    @Published var errorMessage: String?

    let configuration: ServerConfiguration

    private var process: Process?
    private var outputPipe: Pipe?
    private var errorPipe: Pipe?
    private var terminationObserver: NSObjectProtocol?

    private var readySignalRegex: NSRegularExpression?
    private var portDetectionRegex: NSRegularExpression?

    init(configuration: ServerConfiguration) {
        self.configuration = configuration

        if let pattern = configuration.readySignalPattern, !pattern.isEmpty {
            readySignalRegex = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive])
        }
        if let pattern = configuration.portDetectionPattern, !pattern.isEmpty {
            portDetectionRegex = try? NSRegularExpression(pattern: pattern, options: [])
        }

        if configuration.readySignalPattern == nil || configuration.readySignalPattern?.isEmpty == true {
            isReady = true
            detectedURL = URL(string: configuration.localhostURL ?? "http://localhost:3000")
        }
    }

    func start() throws {
        guard !isRunning else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [configuration.command] + configuration.arguments

        var environment = ProcessInfo.processInfo.environment
        let paths = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "/opt/homebrew/sbin",
            "/usr/local/sbin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin"
        ]
        environment["PATH"] = paths.joined(separator: ":")
        environment["AUTO_OPEN_BROWSER"] = "false"
        process.environment = environment

        let stdoutPipe = Pipe()
        let stderrPipe = Pipe()
        process.standardOutput = stdoutPipe
        process.standardError = stderrPipe
        self.outputPipe = stdoutPipe
        self.errorPipe = stderrPipe

        stdoutPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let string = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in
                    self?.appendOutput(string)
                }
            }
        }

        stderrPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let data = handle.availableData
            if !data.isEmpty, let string = String(data: data, encoding: .utf8) {
                Task { @MainActor [weak self] in
                    self?.appendOutput(string)
                }
            }
        }

        terminationObserver = NotificationCenter.default.addObserver(
            forName: Process.didTerminateNotification,
            object: process,
            queue: .main
        ) { [weak self] notification in
            guard let self = self, let terminatedProcess = notification.object as? Process else { return }
            Task { @MainActor in
                self.handleTermination(terminatedProcess)
            }
        }

        do {
            try process.run()
            self.process = process
            self.isRunning = true
            self.exitCode = nil

            let cmdString = ([configuration.command] + configuration.arguments).joined(separator: " ")
            appendOutput("$ \(cmdString)\n\n")
        } catch {
            cleanup()
            errorMessage = "Failed to start process: \(error.localizedDescription)"
            throw error
        }
    }

    func terminate() {
        guard let process = process, isRunning else { return }
        appendOutput("\n[Stopping server...]\n")
        process.terminate()
    }

    func forceKill() {
        guard let process = process else { return }
        kill(process.processIdentifier, SIGKILL)
        cleanup()
        isRunning = false
    }

    // MARK: - Private

    private func appendOutput(_ text: String) {
        output += text

        if !isReady {
            checkReadiness(text)
        }
    }

    private func checkReadiness(_ text: String) {
        guard let regex = readySignalRegex else { return }

        let range = NSRange(text.startIndex..., in: text)
        guard regex.firstMatch(in: text, options: [], range: range) != nil else { return }

        isReady = true

        var port: Int?
        if let portRegex = portDetectionRegex {
            let fullRange = NSRange(output.startIndex..., in: output)
            if let match = portRegex.firstMatch(in: output, options: [], range: fullRange),
               match.numberOfRanges > 1 {
                let captureRange = match.range(at: 1)
                if captureRange.location != NSNotFound,
                   let swiftRange = Range(captureRange, in: output) {
                    port = Int(String(output[swiftRange]))
                }
            }
        }

        let baseURL = configuration.localhostURL ?? "http://localhost:3000"
        if let port = port, let base = URL(string: baseURL) {
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
            components?.port = port
            detectedURL = components?.url ?? URL(string: baseURL)
        } else {
            detectedURL = URL(string: baseURL)
        }
    }

    private func handleTermination(_ process: Process) {
        let code = process.terminationStatus
        exitCode = code
        isRunning = false

        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil

        if code == 0 {
            appendOutput("\n[Process exited with code 0]\n")
        } else {
            appendOutput("\n[Process exited with code \(code)]\n")
        }

        cleanup()
    }

    private func cleanup() {
        if let observer = terminationObserver {
            NotificationCenter.default.removeObserver(observer)
            terminationObserver = nil
        }
        outputPipe?.fileHandleForReading.readabilityHandler = nil
        errorPipe?.fileHandleForReading.readabilityHandler = nil
        try? outputPipe?.fileHandleForReading.close()
        try? errorPipe?.fileHandleForReading.close()
        outputPipe = nil
        errorPipe = nil
        process = nil
    }
}
