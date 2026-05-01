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
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 800, minHeight: 600)
        }
        .commands {
            // Remove the "New Window" command since we only want one window
            CommandGroup(replacing: .newItem) { }
        }
    }
}

class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Activate the app and bring windows to front
        NSApp.activate(ignoringOtherApps: true)
        
        // Ensure the main window is visible
        if let window = NSApp.windows.first {
            window.makeKeyAndOrderFront(nil)
        }
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
