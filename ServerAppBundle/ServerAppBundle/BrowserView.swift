//
//  BrowserView.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import SwiftUI

/// Browser view with web content
struct BrowserView: View {
    @ObservedObject var readinessDetector: ReadinessDetector
    @ObservedObject var webViewModel: WebViewModel
    
    var body: some View {
        ZStack {
            // WebView is always present so it can receive load commands
            WebView(viewModel: webViewModel)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .onAppear {
                    // If we have a URL but haven't loaded it yet, load it now
                    if let url = webViewModel.url, let webView = webViewModel.webView {
                        webView.load(URLRequest(url: url))
                    } else if let url = webViewModel.url {
                        // WebView might not be set yet, try again shortly
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) {
                            if let webView = webViewModel.webView {
                                webView.load(URLRequest(url: url))
                            }
                        }
                    }
                }
            
            // Waiting overlay when server is not ready
            if !readinessDetector.isReady {
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
            
            // Error overlay when page fails to load
            if let error = webViewModel.error {
                ErrorView(
                    message: webViewModel.userFriendlyErrorMessage(for: error),
                    onRetry: {
                        webViewModel.retry()
                    }
                )
            }
        }
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
    BrowserView(
        readinessDetector: ReadinessDetector(
            readySignalPattern: nil,
            portDetectionPattern: nil,
            baseURL: "http://localhost:3000"
        ),
        webViewModel: WebViewModel()
    )
    .frame(width: 800, height: 600)
}
