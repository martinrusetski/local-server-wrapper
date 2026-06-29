//
//  ServerAppBundleApp.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import SwiftUI
import AppKit

// NOTE: No longer `@main`. This type lives in the ServerRuntime framework; the thin launcher stub
// (ServerLauncher/main.swift) is the executable entry point and calls `ServerAppBundleApp.main()`.
// It must be `public` so the stub in the separate launcher module can reference it.
public struct ServerAppBundleApp: App {
    @StateObject private var appState: AppState
    @NSApplicationDelegateAdaptor(AppDelegate.self) var appDelegate

    public init() {
        // Load the embedded configuration
        let configuration = ConfigurationLoader.loadEmbeddedConfigurationWithFallback()
        
        // Initialize app state with the loaded configuration
        let state = AppState(configuration: configuration)
        _appState = StateObject(wrappedValue: state)
    }
    
    public var body: some Scene {
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
            
            // View menu with toolbar and navigation controls
            CommandMenu("View") {
                Toggle("Hide Toolbar", isOn: $appState.isToolbarHidden)
                    .keyboardShortcut("t", modifiers: [.command, .option])
                
                Divider()
                
                Button("Back") {
                    appState.webViewModel.goBack()
                }
                .keyboardShortcut("[", modifiers: .command)
                .disabled(!appState.readinessDetector.isReady || !appState.webViewModel.canGoBack)
                
                Button("Forward") {
                    appState.webViewModel.goForward()
                }
                .keyboardShortcut("]", modifiers: .command)
                .disabled(!appState.readinessDetector.isReady || !appState.webViewModel.canGoForward)
                
                Button("Reload") {
                    appState.webViewModel.reload()
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(!appState.readinessDetector.isReady)
                
                Divider()
                
                Button("Show Terminal") {
                    withAnimation {
                        appState.toggleSidebar()
                    }
                }
                .keyboardShortcut("t", modifiers: [.command, .shift])
                .disabled(!appState.readinessDetector.isReady)
            }
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

        // User already confirmed quit: the server tree was killed synchronously, so allow exit.
        // (Without this the second pass would re-show the dialog while the server was still
        //  shutting down, and the app could orphan the child holding the port — TASK-2.)
        if appState.isQuitting {
            return .terminateNow
        }

        // If process is not running, allow immediate termination
        if !appState.isProcessRunning {
            return .terminateNow
        }

        // If there is no visible window (e.g. the user closed the window with the red ✕), we can't
        // show the confirmation dialog — it would have nowhere to appear and the app would get
        // stuck running headless with the server still holding the port. Just clean up and quit.
        let hasVisibleWindow = sender.windows.contains { $0.isVisible }
        if !hasVisibleWindow {
            appState.prepareForQuit()
            return .terminateNow
        }

        // Window present: ask for confirmation; the user triggers the real quit from the alert.
        Task { @MainActor in
            appState.showCloseConfirmation = true
        }
        return .terminateCancel
    }
    
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        return true
    }

    /// Last-chance, guaranteed cleanup: whenever the app actually terminates (Cmd-Q, Dock → Quit,
    /// confirmed quit, or window close), synchronously kill the server tree so no orphaned child
    /// keeps holding the port. This fires for every graceful exit regardless of which path
    /// triggered it. (A hard Force Quit / SIGKILL can't be intercepted by any process — TASK-2.)
    func applicationWillTerminate(_ notification: Notification) {
        appState?.prepareForQuit()
    }
}
