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
