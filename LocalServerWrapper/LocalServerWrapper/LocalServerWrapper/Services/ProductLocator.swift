//
//  ProductLocator.swift
//  LocalServerWrapper
//
//  Locates the self-contained launcher template and the separate ServerRuntime.framework retained
//  for compatibility with legacy thin launchers. Both are ServerAppBundle project products.
//
//  Search order (mirrors the original generator logic): embedded-in-manager resource → dev
//  workspace Release build → DerivedData Release build.
//

import Foundation
import os.log

private let logger = OSLog(subsystem: "com.localserverwrapper.configmanager", category: "product-locator")

enum ProductLocator {
    static let launcherTemplateName = "ServerAppBundle.app"
    static let frameworkName = "ServerRuntime.framework"

    /// The directory containing the launcher template (and, alongside it, the runtime framework).
    static func productsDirectory() -> URL? {
        let fm = FileManager.default

        // 1. Shipped inside the manager app (Resources) — the distribution case.
        if let embedded = Bundle.main.url(forResource: "ServerAppBundle", withExtension: "app"),
           fm.fileExists(atPath: embedded.path) {
            return embedded.deletingLastPathComponent()
        }

        // 2. Dev: walk up from the manager executable to the repo root, then the sibling Release dir.
        if let execPath = Bundle.main.executablePath {
            var url = URL(fileURLWithPath: execPath)
            for _ in 0..<12 {
                url = url.deletingLastPathComponent()
                if url.lastPathComponent == "LocalServerWrapper" {
                    let root = url.deletingLastPathComponent()
                    let dir = root.appendingPathComponent("ServerAppBundle/build/Build/Products/Release")
                    if fm.fileExists(atPath: dir.appendingPathComponent(launcherTemplateName).path) {
                        return dir
                    }
                }
            }
        }

        // 3. DerivedData Release build.
        let derivedData = URL(fileURLWithPath: NSHomeDirectory())
            .appendingPathComponent("Library/Developer/Xcode/DerivedData")
        if let entries = try? fm.contentsOfDirectory(
            at: derivedData, includingPropertiesForKeys: nil, options: [.skipsHiddenFiles]
        ) {
            for folder in entries where folder.lastPathComponent.hasPrefix("ServerAppBundle-") {
                let dir = folder.appendingPathComponent("Build/Products/Release")
                if fm.fileExists(atPath: dir.appendingPathComponent(launcherTemplateName).path) {
                    return dir
                }
            }
        }

        os_log(.error, log: logger, "Could not locate ServerAppBundle build products")
        return nil
    }

    /// The self-contained launcher template (ServerAppBundle.app) the generator copies per bundle.
    static func launcherTemplate() -> URL? {
        located(launcherTemplateName)
    }

    /// The compatibility ServerRuntime.framework installed for legacy thin launchers.
    static func runtimeFramework() -> URL? {
        located(frameworkName)
    }

    private static func located(_ name: String) -> URL? {
        guard let dir = productsDirectory() else { return nil }
        let url = dir.appendingPathComponent(name)
        return FileManager.default.fileExists(atPath: url.path) ? url : nil
    }
}
