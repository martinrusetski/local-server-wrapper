//
//  WebViewModel.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import Foundation
import WebKit

/// View model for managing web view state and navigation
@MainActor
class WebViewModel: ObservableObject {
    // MARK: - Published Properties
    
    /// The current URL to load
    @Published var url: URL?
    
    /// Whether the back button should be enabled
    @Published var canGoBack: Bool = false
    
    /// Whether the forward button should be enabled
    @Published var canGoForward: Bool = false
    
    /// Whether the page is currently loading
    @Published var isLoading: Bool = false
    
    /// The current URL as a string for display
    @Published var currentURL: String = ""
    
    /// The current error, if any
    @Published var error: Error?
    
    // MARK: - Internal Properties
    
    /// Reference to the web view (set by WebView)
    weak var webView: WKWebView?
    
    /// Credential detector for form submission detection
    var credentialDetector: CredentialDetector?
    
    /// Callback invoked when a page finishes loading, receives the WKWebView
    var onPageLoaded: ((WKWebView) -> Void)?
    
    // MARK: - Public Methods
    
    /// Load a URL in the web view
    /// - Parameter url: The URL to load
    func load(url: URL) {
        // Only load if URL actually changed or if we have an error to clear
        guard self.url != url || self.error != nil else {
            return
        }
        
        self.url = url
        self.currentURL = url.absoluteString
        self.error = nil // Clear any previous errors
        
        // Load directly in the web view
        if let webView = webView {
            let request = URLRequest(url: url)
            webView.load(request)
        }
    }
    
    /// Navigate back in history
    func goBack() {
        webView?.goBack()
    }
    
    /// Navigate forward in history
    func goForward() {
        webView?.goForward()
    }
    
    /// Reload the current page
    func reload() {
        self.error = nil // Clear error on retry
        webView?.reload()
    }
    
    /// Retry loading the current URL (clears error and reloads)
    func retry() {
        self.error = nil
        if let url = self.url {
            webView?.load(URLRequest(url: url))
        } else {
            webView?.reload()
        }
    }
    
    /// Get a user-friendly error message
    /// - Parameter error: The error to convert
    /// - Returns: A user-friendly error message
    func userFriendlyErrorMessage(for error: Error) -> String {
        let nsError = error as NSError
        
        // Handle common network errors
        switch nsError.code {
        case NSURLErrorCannotConnectToHost, NSURLErrorCannotFindHost:
            return "Cannot connect to server. Make sure the server is running."
        case NSURLErrorTimedOut:
            return "Connection timed out. The server may be slow to respond."
        case NSURLErrorNetworkConnectionLost:
            return "Network connection lost. Check your internet connection."
        case NSURLErrorNotConnectedToInternet:
            return "No internet connection available."
        case NSURLErrorBadURL:
            return "Invalid URL. Check the server configuration."
        case NSURLErrorSecureConnectionFailed:
            return "Secure connection failed. The server may have SSL/TLS issues."
        default:
            // Return a generic message with the error description
            return "Failed to load page: \(nsError.localizedDescription)"
        }
    }
    
    // MARK: - Internal Methods
    
    /// Update navigation state from web view
    /// - Parameter webView: The web view to read state from
    func updateNavigationState(from webView: WKWebView) {
        self.canGoBack = webView.canGoBack
        self.canGoForward = webView.canGoForward
        self.isLoading = webView.isLoading
        
        if let url = webView.url {
            self.currentURL = url.absoluteString
        }
    }
}
