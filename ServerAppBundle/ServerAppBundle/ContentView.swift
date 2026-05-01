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
        VStack(spacing: 0) {
            // Toolbar with restart button
            HStack {
                Spacer()
                
                Button(action: {
                    appState.restartServer()
                }) {
                    HStack(spacing: 6) {
                        Image(systemName: "arrow.clockwise")
                        Text("Restart Server")
                    }
                    .font(.system(size: 13))
                }
                .keyboardShortcut("r", modifiers: .command)
                .buttonStyle(.bordered)
                .disabled(appState.processManager.isRunning && appState.processManager.exitCode == nil)
                .help("Restart the server process")
                .accessibilityLabel("Restart Server")
                .accessibilityHint(appState.processManager.isRunning && appState.processManager.exitCode == nil ? "Server is currently running" : "Restarts the server process")
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
            }
            .background(Color(NSColor.windowBackgroundColor))
            .overlay(
                Rectangle()
                    .frame(height: 1)
                    .foregroundColor(Color(NSColor.separatorColor)),
                alignment: .bottom
            )
            
            // Main split view
            HSplitView {
                // Terminal view on the left side
                TerminalView(processManager: appState.processManager)
                    .frame(minWidth: 200)
                    .accessibilityLabel("Terminal Output")
                    .accessibilityHint("Shows server process output and logs")
                
                // Browser view on the right side
                BrowserView(
                    readinessDetector: appState.readinessDetector,
                    webViewModel: appState.webViewModel
                )
                    .frame(minWidth: 400)
                    .accessibilityLabel("Browser View")
                    .accessibilityHint("Displays the web application when server is ready")
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
