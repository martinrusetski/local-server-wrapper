//
//  BrowserOpenInterceptor.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import Foundation
import os.log

private let logger = OSLog(subsystem: "com.localserverwrapper.serverappbundle", category: "browseropen")

/// Intercepts attempts by the spawned server process to open the system browser
/// (e.g. macOS `open <url>` / `xdg-open <url>`) and forwards the URL into the
/// wrapper window instead.
///
/// Mechanism (entirely wrapper-side, nothing outside the app bundle is touched):
/// 1. We write small shim executables named `open` and `xdg-open` into a
///    wrapper-owned directory.
/// 2. `ProcessManager` prepends that directory to the child process `PATH`, so
///    a bare `open`/`xdg-open` call in a launch script resolves to our shim.
/// 3. The shim forwards any `http(s)://` URL into a watched drop directory and
///    swallows the external launch. Any other use falls through to the real
///    `/usr/bin/open` so legitimate file/app opening keeps working.
/// 4. This class watches the drop directory and reports forwarded URLs via
///    `onOpenRequested`.
@MainActor
final class BrowserOpenInterceptor {
    /// Environment variable used to tell the shim where to drop forwarded URLs.
    static let forwardDirEnvKey = "LSW_OPEN_FORWARD_DIR"

    /// Directory containing the `open`/`xdg-open` shims (prepend this to PATH).
    let shimBinDirectory: URL

    /// Directory the shims drop `*.url` request files into.
    let requestsDirectory: URL

    /// Invoked on the main actor when the server process tries to open a URL.
    var onOpenRequested: ((URL) -> Void)?

    private var directorySource: DispatchSourceFileSystemObject?
    private var directoryFD: Int32 = -1
    private let watchQueue = DispatchQueue(label: "com.localserverwrapper.serverappbundle.openshim")

    init() {
        let base: URL
        if let appSupport = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first {
            let bundleID = Bundle.main.bundleIdentifier ?? "com.localserverwrapper.serverappbundle"
            base = appSupport.appendingPathComponent(bundleID, isDirectory: true)
                .appendingPathComponent("open-shim", isDirectory: true)
        } else {
            base = FileManager.default.temporaryDirectory.appendingPathComponent("open-shim", isDirectory: true)
        }
        self.shimBinDirectory = base.appendingPathComponent("bin", isDirectory: true)
        self.requestsDirectory = base.appendingPathComponent("requests", isDirectory: true)
    }

    /// Create directories, (re)write the shim scripts, clear stale requests and
    /// start watching for forwarded URLs. Safe to call more than once.
    func setUp() {
        do {
            try FileManager.default.createDirectory(at: shimBinDirectory, withIntermediateDirectories: true)
            try FileManager.default.createDirectory(at: requestsDirectory, withIntermediateDirectories: true)

            try writeShim(named: "open")
            try writeShim(named: "xdg-open")

            clearStaleRequests()
            startWatching()

            os_log(.info, log: logger, "Browser open interceptor ready (shim: %{public}@)", shimBinDirectory.path)
        } catch {
            os_log(.error, log: logger, "Failed to set up browser open interceptor: %{public}@", error.localizedDescription)
        }
    }

    // MARK: - Shim installation

    private func writeShim(named name: String) throws {
        let script = """
        #!/bin/bash
        # ServerAppBundle browser-open shim. Forwards http(s) URLs into the wrapper
        # window and swallows the external launch; everything else passes through to
        # the real /usr/bin/open so file/app opening keeps working.
        url=""
        for arg in "$@"; do
          case "$arg" in
            http://*|https://*) url="$arg"; break ;;
          esac
        done
        if [ -n "$url" ] && [ -n "$\(Self.forwardDirEnvKey)" ] && [ -d "$\(Self.forwardDirEnvKey)" ]; then
          name="$(date +%s)-$$-$RANDOM"
          tmp="$\(Self.forwardDirEnvKey)/.$name.tmp"
          if printf '%s' "$url" > "$tmp" 2>/dev/null; then
            mv "$tmp" "$\(Self.forwardDirEnvKey)/$name.url" 2>/dev/null
          fi
          exit 0
        fi
        exec /usr/bin/open "$@"
        """

        let url = shimBinDirectory.appendingPathComponent(name)
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
    }

    // MARK: - Request watching

    private func clearStaleRequests() {
        guard let files = try? FileManager.default.contentsOfDirectory(at: requestsDirectory, includingPropertiesForKeys: nil) else {
            return
        }
        for file in files {
            try? FileManager.default.removeItem(at: file)
        }
    }

    private func startWatching() {
        stopWatching()

        directoryFD = open(requestsDirectory.path, O_EVTONLY)
        guard directoryFD >= 0 else {
            os_log(.error, log: logger, "Could not open requests directory for watching")
            return
        }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: directoryFD,
            eventMask: [.write],
            queue: watchQueue
        )
        source.setEventHandler { [weak self] in
            Task { @MainActor in
                self?.processPendingRequests()
            }
        }
        source.setCancelHandler { [weak self] in
            guard let self = self else { return }
            if self.directoryFD >= 0 {
                close(self.directoryFD)
                self.directoryFD = -1
            }
        }
        directorySource = source
        source.resume()

        // Drain anything that may already be present.
        processPendingRequests()
    }

    private func stopWatching() {
        directorySource?.cancel()
        directorySource = nil
    }

    private func processPendingRequests() {
        guard let files = try? FileManager.default.contentsOfDirectory(
            at: requestsDirectory,
            includingPropertiesForKeys: nil
        ) else {
            return
        }

        let requestFiles = files
            .filter { $0.pathExtension == "url" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }

        for file in requestFiles {
            let contents = (try? String(contentsOf: file, encoding: .utf8))?
                .trimmingCharacters(in: .whitespacesAndNewlines)
            try? FileManager.default.removeItem(at: file)

            guard let contents = contents,
                  let url = URL(string: contents),
                  let scheme = url.scheme?.lowercased(),
                  scheme == "http" || scheme == "https" else {
                continue
            }

            os_log(.info, log: logger, "Forwarding intercepted browser open: %{public}@", url.absoluteString)
            onOpenRequested?(url)
        }
    }

    deinit {
        directorySource?.cancel()
    }
}
