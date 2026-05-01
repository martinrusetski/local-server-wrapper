//
//  ContentView.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    
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
            
            // Sidebar - Terminal (collapsible, on the right)
            if appState.isSidebarVisible {
                Divider()
                
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
                .frame(width: 350)
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
                    .keyboardShortcut("[", modifiers: .command)
                    .disabled(!appState.webViewModel.canGoBack)
                    .help("Go Back")
                    
                    Button(action: { appState.webViewModel.goForward() }) {
                        Label("Forward", systemImage: "chevron.right")
                    }
                    .keyboardShortcut("]", modifiers: .command)
                    .disabled(!appState.webViewModel.canGoForward)
                    .help("Go Forward")
                    
                    Button(action: { appState.webViewModel.reload() }) {
                        Label("Reload", systemImage: "arrow.clockwise")
                    }
                    .keyboardShortcut("r", modifiers: [.command, .shift])
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
                            Image(systemName: "lock.fill")
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
                        withAnimation {
                            appState.toggleSidebar()
                        }
                    }) {
                        Label("Toggle Terminal", systemImage: "sidebar.right")
                    }
                    .help("Show/hide terminal output")
                    .keyboardShortcut("t", modifiers: [.command, .shift])
                }
            }
        }
        .onAppear {
            // Start the server process when the view appears
            appState.startServer()
        }
        .alert("Server is still running", isPresented: $appState.showCloseConfirmation) {
            Button("Cancel", role: .cancel) {
                appState.showCloseConfirmation = false
            }
            .keyboardShortcut(.escape)
            Button("Quit Anyway", role: .destructive) {
                appState.stopServer()
                // Give the process a moment to terminate
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
                    NSApplication.shared.terminate(nil)
                }
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
