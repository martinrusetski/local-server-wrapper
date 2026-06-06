//
//  LocalServerWrapperApp.swift
//  LocalServerWrapper
//
//  Created by Kiro
//

import SwiftUI
import AppKit

@main
struct LocalServerWrapperApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    @StateObject private var configurationManager = ConfigurationManager()

    var body: some Scene {
        WindowGroup {
            ContentView(configurationManager: configurationManager)
                .frame(minWidth: 800, minHeight: 600)
                .environmentObject(configurationManager)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }
        }

        WindowGroup(for: UUID.self) { $configId in
            if let configId = configId,
               let config = configurationManager.getConfiguration(id: configId) {
                TestRunView(configuration: config)
            } else {
                Text("Configuration not found")
                    .padding()
            }
        }
        .defaultSize(width: 1000, height: 700)
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.activate(ignoringOtherApps: true)

        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
