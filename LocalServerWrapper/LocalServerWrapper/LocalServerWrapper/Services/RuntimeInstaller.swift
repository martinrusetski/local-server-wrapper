//
//  RuntimeInstaller.swift
//  LocalServerWrapper
//
//  Keeps ~/Library/Frameworks/ServerRuntime.framework in sync with the build the manager knows
//  about (located via ProductLocator). Generated launcher bundles load the framework from there via
//  the absolute rpath baked into the launcher template, so refreshing it here propagates a new
//  runtime to every generated server on its next launch — the point of Step 2.
//
//  Call installIfNeeded() at app launch and before generating a bundle.
//

import Foundation
import os.log

private let logger = OSLog(subsystem: "com.localserverwrapper.configmanager", category: "runtime-install")

enum RuntimeInstaller {
    static let frameworkName = ProductLocator.frameworkName

    /// Per-user install dir; no admin required, stable across app moves.
    static var installDirectory: URL {
        FileManager.default.urls(for: .libraryDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("Frameworks", isDirectory: true)
    }

    static var installedFrameworkURL: URL {
        installDirectory.appendingPathComponent(frameworkName)
    }

    /// Ensure a current shared runtime is installed.
    /// - Returns: true if a usable framework is present afterward (freshly installed or already current).
    @discardableResult
    static func installIfNeeded() -> Bool {
        let fm = FileManager.default
        let dest = installedFrameworkURL

        guard let source = ProductLocator.runtimeFramework() else {
            // No source to (re)install from — only OK if a copy is already in place.
            let present = fm.fileExists(atPath: dest.path)
            if !present {
                os_log(.error, log: logger, "ServerRuntime.framework not found in build products and none installed")
            }
            return present
        }

        if !needsInstall(source: source, dest: dest) {
            return true
        }

        do {
            try fm.createDirectory(at: installDirectory, withIntermediateDirectories: true)
            if fm.fileExists(atPath: dest.path) { try fm.removeItem(at: dest) }
            try fm.copyItem(at: source, to: dest)
            // copyItem preserves extended attributes, so a quarantine flag on a downloaded manager's
            // embedded framework would ride along to here. Clear it so generated bundles don't load a
            // quarantined framework on the user's machine.
            QuarantineRemover.removeRecursively(at: dest)
            os_log(.info, log: logger, "Installed shared runtime to %{public}@", dest.path)
            return true
        } catch {
            os_log(.error, log: logger, "Failed to install shared runtime: %{public}@", error.localizedDescription)
            // A stale copy is better than none.
            return fm.fileExists(atPath: dest.path)
        }
    }

    /// Reinstall if the destination is missing or older than the source. Compares the framework
    /// binary's modification date (CFBundleVersion is constant in dev, so it can't detect rebuilds).
    private static func needsInstall(source: URL, dest: URL) -> Bool {
        let fm = FileManager.default
        guard fm.fileExists(atPath: dest.path) else { return true }
        let rel = "Versions/A/ServerRuntime"
        let sDate = modDate(source.appendingPathComponent(rel))
        let dDate = modDate(dest.appendingPathComponent(rel))
        guard let s = sDate, let d = dDate else { return true }
        return s > d
    }

    private static func modDate(_ url: URL) -> Date? {
        (try? FileManager.default.attributesOfItem(atPath: url.path))?[.modificationDate] as? Date
    }
}
