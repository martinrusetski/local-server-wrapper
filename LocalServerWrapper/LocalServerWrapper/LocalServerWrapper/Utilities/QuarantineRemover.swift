//
//  QuarantineRemover.swift
//  LocalServerWrapper
//

import Foundation
import os.log

private let logger = OSLog(subsystem: "com.localserverwrapper.configmanager", category: "quarantine")

/// Strips the `com.apple.quarantine` extended attribute from items the manager copies into place.
///
/// Why this is needed: on the dev machine nothing is quarantined (everything is built locally), but
/// when a user *downloads* the manager app, macOS tags it — and the resources embedded inside it —
/// with `com.apple.quarantine`. `FileManager` copies preserve extended attributes, so that flag rides
/// along into the legacy compatibility runtime and into each generated launcher bundle
/// (which is copied from the embedded template). A generated bundle that then loads a
/// quarantined framework can trip Gatekeeper/dyld on the user's machine even though it launches fine
/// on the dev machine. Clearing the attribute after each copy restores that dev/user parity.
///
/// The manager is unsandboxed, so it can clear the attribute directly via `/usr/bin/xattr`.
enum QuarantineRemover {
    /// Recursively remove `com.apple.quarantine` from the item at `url`.
    ///
    /// Best-effort: failures are logged, not thrown — a present-but-quarantined file is still better
    /// than aborting the copy that produced it. `xattr -dr` exits 0 whether or not the attribute is
    /// present, so a nonzero status is a genuine failure worth logging.
    static func removeRecursively(at url: URL) {
        guard FileManager.default.fileExists(atPath: url.path) else { return }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/xattr")
        process.arguments = ["-dr", "com.apple.quarantine", url.path]

        let errorPipe = Pipe()
        process.standardError = errorPipe

        do {
            try process.run()
            process.waitUntilExit()

            if process.terminationStatus != 0 {
                let errorData = errorPipe.fileHandleForReading.readDataToEndOfFile()
                let errorOutput = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                os_log(.error, log: logger, "Quarantine removal failed for %{public}@ (status %d): %{public}@",
                       url.path, process.terminationStatus, errorOutput)
            } else {
                os_log(.debug, log: logger, "Cleared quarantine attribute from %{public}@", url.path)
            }
        } catch {
            os_log(.error, log: logger, "Failed to run xattr on %{public}@: %{public}@",
                   url.path, error.localizedDescription)
        }
    }
}
