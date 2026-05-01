//
//  WebView.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import SwiftUI
import WebKit

/// NSViewRepresentable wrapper for WKWebView
struct WebView: NSViewRepresentable {
    @ObservedObject var viewModel: WebViewModel
    
    // MARK: - NSViewRepresentable
    
    func makeNSView(context: Context) -> WKWebView {
        // Configure WKWebView with proper settings for localhost
        let configuration = WKWebViewConfiguration()
        configuration.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        configuration.setValue(true, forKey: "allowUniversalAccessFromFileURLs")
        
        let webView = WKWebView(frame: .zero, configuration: configuration)
        webView.navigationDelegate = context.coordinator
        
        // Enable developer extras for debugging
        webView.configuration.preferences.setValue(true, forKey: "developerExtrasEnabled")
        
        // Store reference in view model
        DispatchQueue.main.async {
            viewModel.webView = webView
        }
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Don't load URLs here - let the view model handle it directly
        // This prevents reload loops when other @Published properties change
    }
    
    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }
    
    // MARK: - Coordinator
    
    class Coordinator: NSObject, WKNavigationDelegate {
        let viewModel: WebViewModel
        
        init(viewModel: WebViewModel) {
            self.viewModel = viewModel
        }
        
        // MARK: - WKNavigationDelegate
        
        func webView(_ webView: WKWebView, didStartProvisionalNavigation navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.updateNavigationState(from: webView)
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.updateNavigationState(from: webView)
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            
            Task { @MainActor in
                // Ignore cancellation errors (error -999)
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    return
                }
                
                viewModel.error = error
                viewModel.updateNavigationState(from: webView)
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            
            Task { @MainActor in
                // Ignore cancellation errors (error -999)
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    return
                }
                
                viewModel.error = error
                viewModel.updateNavigationState(from: webView)
            }
        }
        
        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            // Allow all navigation
            decisionHandler(.allow)
        }
    }
}
