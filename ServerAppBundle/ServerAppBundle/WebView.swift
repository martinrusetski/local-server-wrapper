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
            print("🌐 didStartProvisionalNavigation: \(webView.url?.absoluteString ?? "nil")")
            Task { @MainActor in
                viewModel.updateNavigationState(from: webView)
            }
        }
        
        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            print("✅ didFinish navigation: \(webView.url?.absoluteString ?? "nil")")
            Task { @MainActor in
                viewModel.updateNavigationState(from: webView)
            }
        }
        
        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            print("❌ didFail: \(nsError.domain) code: \(nsError.code) - \(error.localizedDescription)")
            
            Task { @MainActor in
                // Ignore cancellation errors (error -999)
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    print("⚠️ Ignoring cancellation error")
                    return
                }
                
                viewModel.error = error
                viewModel.updateNavigationState(from: webView)
            }
        }
        
        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            print("❌ didFailProvisionalNavigation: \(nsError.domain) code: \(nsError.code) - \(error.localizedDescription)")
            
            Task { @MainActor in
                // Ignore cancellation errors (error -999)
                if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled {
                    print("⚠️ Ignoring cancellation error")
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
