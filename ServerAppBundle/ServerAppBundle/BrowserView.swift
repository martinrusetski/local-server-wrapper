//
//  BrowserView.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import SwiftUI

/// Browser view with toolbar and web content
struct BrowserView: View {
    @ObservedObject var readinessDetector: ReadinessDetector
    @StateObject private var webViewModel = WebViewModel()
    
    var body: some View {
        VStack(spacing: 0) {
            // Browser toolbar
            BrowserToolbar(viewModel: webViewModel)
            
            // Web content
            if readinessDetector.isReady, let url = readinessDetector.detectedURL {
                ZStack {
                    WebView(viewModel: webViewModel)
                        .onAppear {
                            webViewModel.load(url: url)
                        }
                        .onChange(of: readinessDetector.detectedURL) { newURL in
                            if let newURL = newURL {
                                webViewModel.load(url: newURL)
                            }
                        }
                    
                    // Error overlay
                    if let error = webViewModel.error {
                        ErrorView(
                            message: webViewModel.userFriendlyErrorMessage(for: error),
                            onRetry: {
                                webViewModel.retry()
                            }
                        )
                    }
                }
            } else {
                // Show waiting message
                VStack(spacing: 16) {
                    ProgressView()
                        .scaleEffect(1.5)
                        .accessibilityLabel("Loading")
                    
                    Text("Waiting for server to be ready...")
                        .font(.title3)
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Status")
                        .accessibilityValue("Waiting for server to be ready")
                    
                    if let baseURL = readinessDetector.detectedURL?.absoluteString {
                        Text("Will load: \(baseURL)")
                            .font(.caption)
                            .foregroundColor(.secondary)
                            .accessibilityLabel("Target URL")
                            .accessibilityValue(baseURL)
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .background(Color(NSColor.controlBackgroundColor))
                .accessibilityElement(children: .contain)
            }
        }
    }
}

/// Browser toolbar with navigation controls
struct BrowserToolbar: View {
    @ObservedObject var viewModel: WebViewModel
    
    var body: some View {
        HStack(spacing: 12) {
            // Back button
            Button(action: { viewModel.goBack() }) {
                Image(systemName: "chevron.left")
                    .font(.system(size: 14, weight: .medium))
            }
            .keyboardShortcut("[", modifiers: .command)
            .disabled(!viewModel.canGoBack)
            .buttonStyle(.borderless)
            .help("Go Back")
            .accessibilityLabel("Go Back")
            .accessibilityHint(viewModel.canGoBack ? "Navigate to previous page" : "No previous page available")
            
            // Forward button
            Button(action: { viewModel.goForward() }) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 14, weight: .medium))
            }
            .keyboardShortcut("]", modifiers: .command)
            .disabled(!viewModel.canGoForward)
            .buttonStyle(.borderless)
            .help("Go Forward")
            .accessibilityLabel("Go Forward")
            .accessibilityHint(viewModel.canGoForward ? "Navigate to next page" : "No next page available")
            
            // Reload button
            Button(action: { viewModel.reload() }) {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 14, weight: .medium))
            }
            .keyboardShortcut("r", modifiers: [.command, .shift])
            .buttonStyle(.borderless)
            .help("Reload")
            .accessibilityLabel("Reload Page")
            .accessibilityHint("Reloads the current page")
            
            // URL display
            HStack(spacing: 8) {
                if viewModel.isLoading {
                    ProgressView()
                        .scaleEffect(0.6)
                        .frame(width: 16, height: 16)
                        .accessibilityLabel("Loading")
                } else {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 12))
                        .foregroundColor(.secondary)
                        .accessibilityLabel("Secure Connection")
                }
                
                Text(viewModel.currentURL)
                    .font(.system(size: 13))
                    .foregroundColor(.primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                    .accessibilityLabel("Current URL")
                    .accessibilityValue(viewModel.currentURL)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(Color(NSColor.controlBackgroundColor))
            .cornerRadius(6)
            .frame(maxWidth: .infinity)
            .accessibilityElement(children: .combine)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color(NSColor.windowBackgroundColor))
        .overlay(
            Rectangle()
                .frame(height: 1)
                .foregroundColor(Color(NSColor.separatorColor)),
            alignment: .bottom
        )
    }
}

/// Error view displayed when web content fails to load
struct ErrorView: View {
    let message: String
    let onRetry: () -> Void
    
    var body: some View {
        VStack(spacing: 20) {
            // Error icon
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundColor(.orange)
            
            // Error message
            VStack(spacing: 8) {
                Text("Unable to Load Page")
                    .font(.title2)
                    .fontWeight(.semibold)
                
                Text(message)
                    .font(.body)
                    .foregroundColor(.secondary)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 40)
            }
            
            // Retry button
            Button(action: onRetry) {
                HStack(spacing: 8) {
                    Image(systemName: "arrow.clockwise")
                    Text("Retry")
                }
                .font(.system(size: 15, weight: .medium))
                .padding(.horizontal, 24)
                .padding(.vertical, 10)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityLabel("Retry Loading Page")
            .accessibilityHint("Attempts to reload the page that failed to load")
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(NSColor.controlBackgroundColor).opacity(0.95))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("Error View")
    }
}

#Preview {
    BrowserView(readinessDetector: ReadinessDetector(
        readySignalPattern: nil,
        portDetectionPattern: nil,
        baseURL: "http://localhost:3000"
    ))
    .frame(width: 800, height: 600)
}
