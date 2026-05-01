//
//  ServerAppBundleApp.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import SwiftUI
import AppKit

@main
struct ServerAppBundleApp: App {
    @StateObject private var appState: AppState
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate
    
    init() {
        // Load the embedded configuration
        let configuration = ConfigurationLoader.loadEmbeddedConfigurationWithFallback()
        
        // Initialize app state with the loaded configuration
        let state = AppState(configuration: configuration)
        _appState = StateObject(wrappedValue: state)
    }
    
    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 800, minHeight: 600)
                .onAppear {
                    // Share app state with the delegate
                    appDelegate.appState = appState
                }
        }
        .commands {
            // Remove "New Window" command since we only want one window per bundle
            CommandGroup(replacing: .newItem) { }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
    }
}

/// Application delegate to handle window lifecycle events
class AppDelegate: NSObject, NSApplicationDelegate {
    var appState: AppState?
    
    func applicationDidFinishLaunching(_ notification: Notification) {
        // Nothing needed here for now
    }
    
    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply {
        guard let appState = appState else {
            return .terminateNow
        }
        
        // If process is not running, allow immediate termination
        if !appState.isProcessRunning {
            return .terminateNow
        }
        
        // If process is running, show confirmation dialog
        Task { @MainActor in
            appState.showCloseConfirmation = true
        }
        
        // Cancel termination - the user will trigger it from the alert
        return .terminateCancel
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }
}
