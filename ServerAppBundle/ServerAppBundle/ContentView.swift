//
//  ContentView.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import SwiftUI
import AppKit

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    @State private var sidebarWidth: CGFloat = 650
    @State private var hostingWindow: NSWindow?
    
    var body: some View {
        HStack(spacing: 0) {
            // Main content area
            if appState.readinessDetector.isReady {
                // Browser view when ready
                BrowserView(
                    readinessDetector: appState.readinessDetector,
                    webViewModel: appState.webViewModel
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityLabel("Browser View")
                .accessibilityHint("Displays the web application when server is ready")
            } else {
                // Terminal view before ready
                VStack(spacing: 0) {
                    // Simple toolbar
                    HStack {
                        Spacer()
                        Text("Starting Server...")
                            .font(.headline)
                        Spacer()
                    }
                    .padding()
                    .background(Color(NSColor.windowBackgroundColor))
                    
                    Divider()
                    
                    // Terminal output
                    TerminalView(processManager: appState.processManager)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            
            // Sidebar - Terminal (collapsible, resizable, on the right)
            if appState.isSidebarVisible {
                // Drag handle for resizing
                Rectangle()
                    .fill(Color.secondary.opacity(0.2))
                    .frame(width: 5)
                    .gesture(
                        DragGesture()
                            .onChanged { value in
                                let newWidth = max(200, min(800, sidebarWidth - value.translation.width))
                                sidebarWidth = newWidth
                            }
                    )
                    .onHover { inside in
                        if inside {
                            NSCursor.resizeLeftRight.push()
                        } else {
                            NSCursor.pop()
                        }
                    }
                
                VStack(spacing: 0) {
                    // Sidebar header with restart button
                    HStack {
                        Text("Terminal")
                            .font(.headline)
                        
                        Spacer()
                        
                        Button(action: {
                            appState.restartServer()
                        }) {
                            Label("Restart Server", systemImage: "arrow.clockwise")
                        }
                        .buttonStyle(.borderless)
                        .keyboardShortcut("r", modifiers: .command)
                        .help("Restart the server process")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)
                    .background(Color(NSColor.windowBackgroundColor))
                    
                    Divider()
                    
                    TerminalView(processManager: appState.processManager)
                }
                .frame(width: sidebarWidth)
                .accessibilityLabel("Terminal Output")
                .accessibilityHint("Shows server process output and logs")
            }
        }
        .toolbar {
            ToolbarItemGroup(placement: .navigation) {
                if appState.readinessDetector.isReady {
                    // Browser navigation controls
                    Button(action: { appState.webViewModel.goBack() }) {
                        Label("Back", systemImage: "chevron.left")
                    }
                    .disabled(!appState.webViewModel.canGoBack)
                    .help("Go Back")
                    
                    Button(action: { appState.webViewModel.goForward() }) {
                        Label("Forward", systemImage: "chevron.right")
                    }
                    .disabled(!appState.webViewModel.canGoForward)
                    .help("Go Forward")
                    
                    Button(action: { appState.webViewModel.reload() }) {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .help("Reload Page")
                }
            }
            
            ToolbarItem(placement: .principal) {
                if appState.readinessDetector.isReady {
                    // URL display - centered
                    HStack(spacing: 8) {
                        if appState.webViewModel.isLoading {
                            ProgressView()
                                .scaleEffect(0.6)
                                .frame(width: 16, height: 16)
                        } else {
                            // Neutral indicator — this is plain http://localhost, not TLS,
                            // so a padlock would be misleading (TASK-12).
                            Image(systemName: "globe")
                                .font(.system(size: 11))
                                .foregroundColor(.secondary)
                        }
                        
                        Text(appState.webViewModel.currentURL)
                            .font(.system(size: 12))
                            .foregroundColor(.secondary)
                            .lineLimit(1)
                            .truncationMode(.middle)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
                    .background(Color(NSColor.controlBackgroundColor))
                    .cornerRadius(6)
                    .frame(maxWidth: 500)
                } else {
                    EmptyView()
                }
            }
            
            ToolbarItemGroup(placement: .automatic) {
                if appState.readinessDetector.isReady {
                    Button(action: {
                        appState.showCredentialManager = true
                    }) {
                        Label("Saved Logins", systemImage: "key")
                    }
                    .help("View and delete saved logins")

                    Button(action: {
                        withAnimation {
                            appState.toggleSidebar()
                        }
                    }) {
                        Label("Toggle Terminal", systemImage: "apple.terminal")
                    }
                    .help("Show/hide terminal output")
                }
            }
        }
        .background(WindowAccessor(window: $hostingWindow))
        .onAppear {
            // Start the server process when the view appears
            appState.startServer()
            // Apply initial window appearance state
            DispatchQueue.main.async {
                guard let window = hostingWindow else { return }
                window.title = appState.configuration.name
                applyToolbarState(to: window, hidden: appState.isToolbarHidden)
            }
        }
        .onChange(of: appState.isToolbarHidden) { hidden in
            guard let window = hostingWindow else { return }
            applyToolbarState(to: window, hidden: hidden)
        }
        .alert("Server is still running", isPresented: $appState.showCloseConfirmation) {
            Button("Cancel", role: .cancel) {
                appState.showCloseConfirmation = false
            }
            .keyboardShortcut(.escape)
            Button("Quit Anyway", role: .destructive) {
                // Synchronously kill the server tree, then quit — no orphaned port-holder (TASK-2).
                appState.confirmQuitAndTerminate()
            }
            .keyboardShortcut(.return)
        } message: {
            Text("The server process is still running. Are you sure you want to quit?")
        }
        .alert("Server Error", isPresented: $appState.showErrorAlert) {
            Button("OK", role: .cancel) {
                appState.showErrorAlert = false
            }
            Button("Retry") {
                appState.showErrorAlert = false
                appState.restartServer()
            }
        } message: {
            Text(appState.errorMessage ?? "An unknown error occurred.")
        }
        .alert("Server Ready Signal Timeout", isPresented: $appState.showTimeoutAlert) {
            Button("Keep Waiting", role: .cancel) {
                appState.showTimeoutAlert = false
            }
            Button("Open Browser Manually") {
                appState.manuallyOpenBrowser()
            }
        } message: {
            Text("The server has been running for 30 seconds but the ready signal has not been detected. You can keep waiting or manually open the browser.")
        }
        .alert("Server Didn't Start", isPresented: $appState.showStartupFailureAlert) {
            Button("OK", role: .cancel) {
                appState.showStartupFailureAlert = false
            }
            Button("Retry") {
                appState.showStartupFailureAlert = false
                appState.restartServer()
            }
        } message: {
            Text(appState.startupFailureMessage ?? "The server process exited before it became ready.")
        }
        .alert("Save Credentials?", isPresented: $appState.showCredentialSavePrompt) {
            Button("Save") {
                if let cred = appState.pendingCredential {
                    appState.saveCredential(cred)
                }
            }
            .keyboardShortcut(.return)
            Button("Not Now", role: .cancel) {
                appState.pendingCredential = nil
            }
        } message: {
            if let cred = appState.pendingCredential {
                Text("Save login for \"\(cred.username)\" on this page? Your credentials will be stored securely.")
            }
        }
        .sheet(isPresented: $appState.showCredentialManager) {
            CredentialManagerView()
                .environmentObject(appState)
        }
    }
    
    private func applyToolbarState(to window: NSWindow, hidden: Bool) {
        window.toolbar?.isVisible = !hidden
        if hidden {
            window.titlebarAppearsTransparent = false
            window.titleVisibility = .visible
        } else {
            window.titlebarAppearsTransparent = true
            window.titleVisibility = .hidden
        }
    }
}

#Preview {
    ContentView()
        .environmentObject(AppState(configuration: ServerConfiguration(
            name: "Test Server",
            command: "npm",
            arguments: ["run", "dev"],
            localhostURL: "http://localhost:3000"
        )))
}

/// Minimal management UI for saved logins: lists usernames + origin and allows deletion (TASK-12).
/// Defined here (rather than a new file) to avoid Xcode project/target surgery.
struct CredentialManagerView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(spacing: 0) {
            HStack {
                Text("Saved Logins")
                    .font(.headline)
                Spacer()
                Button("Done") { dismiss() }
                    .keyboardShortcut(.defaultAction)
            }
            .padding()

            Divider()

            if appState.credentials.isEmpty {
                VStack(spacing: 8) {
                    Image(systemName: "key.slash")
                        .font(.system(size: 28))
                        .foregroundColor(.secondary)
                    Text("No saved logins")
                        .foregroundColor(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .padding()
            } else {
                List {
                    ForEach(appState.credentials) { credential in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text(credential.username)
                                    .fontWeight(.medium)
                                Text(credential.origin ?? "Unknown origin")
                                    .font(.caption)
                                    .foregroundColor(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                appState.deleteCredential(id: credential.id)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                            .help("Delete this saved login")
                        }
                        .padding(.vertical, 2)
                    }
                }
            }
        }
        .frame(width: 380, height: 320)
    }
}

private struct WindowAccessor: NSViewRepresentable {
    @Binding var window: NSWindow?
    
    func makeNSView(context: Context) -> NSView {
        let view = NSView()
        DispatchQueue.main.async {
            window = view.window
        }
        return view
    }
    
    func updateNSView(_ nsView: NSView, context: Context) {}
}
