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
        let webView = WKWebView()
        webView.navigationDelegate = context.coordinator
        
        // Store reference in view model
        DispatchQueue.main.async {
            viewModel.webView = webView
        }
        
        return webView
    }
    
    func updateNSView(_ webView: WKWebView, context: Context) {
        // Load URL if it changed and is different from current
        if let url = viewModel.url, webView.url != url {
            webView.load(URLRequest(url: url))
        }
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
            Task { @MainActor in
                viewModel.error = error
                viewModel.updateNavigationState(from: webView)
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
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
