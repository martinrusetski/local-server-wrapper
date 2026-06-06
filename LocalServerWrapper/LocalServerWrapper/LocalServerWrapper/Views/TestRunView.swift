//
//  TestRunView.swift
//  LocalServerWrapper
//

import SwiftUI
import WebKit
import AppKit
import Combine

struct TestRunView: View {
    @StateObject private var manager: TestRunManager
    @StateObject private var webViewModel = TestRunWebViewModel()
    @State private var showTerminal = true

    init(configuration: ServerConfiguration) {
        _manager = StateObject(wrappedValue: TestRunManager(configuration: configuration))
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbarSection
            Divider()
            contentSection
        }
        .task {
            try? manager.start()
        }
        .onDisappear {
            manager.terminate()
        }
    }

    // MARK: - Toolbar

    private var toolbarSection: some View {
        HStack(spacing: 12) {
            Text(manager.configuration.name)
                .font(.headline)
                .lineLimit(1)

            statusBadge

            Spacer()

            if manager.isReady, let url = manager.detectedURL {
                Button(action: { webViewModel.load(url: url) }) {
                    Image(systemName: "arrow.clockwise")
                }
                .help("Reload browser")

                Button(action: { NSWorkspace.shared.open(url) }) {
                    Image(systemName: "safari")
                }
                .help("Open in default browser")
            }

            Button(action: { showTerminal.toggle() }) {
                Image(systemName: "sidebar.trailing")
                    .symbolVariant(showTerminal ? .fill : .none)
            }
            .help(showTerminal ? "Hide terminal" : "Show terminal")

            if manager.isRunning {
                Button("Stop") {
                    manager.terminate()
                }
                .buttonStyle(.bordered)
                .tint(.red)
                .controlSize(.small)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var statusBadge: some View {
        HStack(spacing: 4) {
            Circle()
                .fill(statusColor)
                .frame(width: 8, height: 8)
            Text(statusText)
                .font(.caption)
                .foregroundColor(.secondary)
        }
    }

    private var statusColor: Color {
        if !manager.isRunning {
            return manager.exitCode == 0 ? .green : .red
        }
        return manager.isReady ? .green : .yellow
    }

    private var statusText: String {
        if let code = manager.exitCode {
            return "Exited (\(code))"
        }
        if !manager.isRunning {
            return "Stopped"
        }
        return manager.isReady ? "Ready" : "Starting..."
    }

    // MARK: - Content

    private var contentSection: some View {
        Group {
            if manager.isReady, let url = manager.detectedURL {
                HSplitView {
                    TestRunWebView(viewModel: webViewModel)
                        .onAppear {
                            webViewModel.load(url: url)
                        }

                    if showTerminal {
                        TestRunTerminalView(
                            output: manager.output,
                            exitCode: manager.exitCode
                        )
                        .frame(minWidth: 250, idealWidth: 350)
                    }
                }
            } else {
                ZStack {
                    TestRunTerminalView(
                        output: manager.output,
                        exitCode: manager.exitCode
                    )

                    if let error = manager.errorMessage {
                        VStack(spacing: 12) {
                            Image(systemName: "exclamationmark.triangle.fill")
                                .font(.largeTitle)
                                .foregroundColor(.red)
                            Text(error)
                                .font(.headline)
                                .multilineTextAlignment(.center)
                        }
                        .padding(24)
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                    }
                }
            }
        }
    }
}

// MARK: - Terminal View

struct TestRunTerminalView: View {
    let output: String
    let exitCode: Int32?

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(output)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id("output")

                    if let code = exitCode {
                        Divider()
                            .background(code == 0 ? Color.green : Color.red)
                            .padding(.vertical, 4)

                        HStack(spacing: 6) {
                            Image(systemName: code == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(code == 0 ? .green : .red)
                            Text("Process exited with code \(code)")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(code == 0 ? .green : .red)
                        }
                        .padding(8)
                        .id("exitCode")
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor))
            .foregroundColor(Color(nsColor: .textColor))
            .onChange(of: output) { _ in
                withAnimation {
                    proxy.scrollTo(exitCode != nil ? "exitCode" : "output", anchor: .bottom)
                }
            }
            .onChange(of: exitCode) { _ in
                if exitCode != nil {
                    withAnimation {
                        proxy.scrollTo("exitCode", anchor: .bottom)
                    }
                }
            }
        }
    }
}

// MARK: - Web View Model

@MainActor
class TestRunWebViewModel: ObservableObject {
    @Published var url: URL?
    @Published var canGoBack = false
    @Published var canGoForward = false
    @Published var isLoading = false
    @Published var currentURL = ""
    @Published var error: Error?

    weak var webView: WKWebView? {
        didSet {
            if let webView = webView, let url = url {
                webView.load(URLRequest(url: url))
            }
        }
    }

    func load(url: URL) {
        guard self.url != url || self.error != nil else { return }
        self.url = url
        self.currentURL = url.absoluteString
        self.error = nil
        if let webView = webView {
            webView.load(URLRequest(url: url))
        }
    }
}

// MARK: - Web View NSViewRepresentable

struct TestRunWebView: NSViewRepresentable {
    @ObservedObject var viewModel: TestRunWebViewModel

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "developerExtrasEnabled")
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        config.setValue(true, forKey: "allowUniversalAccessFromFileURLs")

        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.uiDelegate = context.coordinator

        DispatchQueue.main.async {
            viewModel.webView = webView
        }
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {}

    func makeCoordinator() -> Coordinator {
        Coordinator(viewModel: viewModel)
    }

    class Coordinator: NSObject, WKNavigationDelegate, WKUIDelegate {
        let viewModel: TestRunWebViewModel

        init(viewModel: TestRunWebViewModel) {
            self.viewModel = viewModel
        }

        func webView(_ webView: WKWebView, didFinish navigation: WKNavigation!) {
            Task { @MainActor in
                viewModel.canGoBack = webView.canGoBack
                viewModel.canGoForward = webView.canGoForward
                viewModel.isLoading = webView.isLoading
                if let url = webView.url {
                    viewModel.currentURL = url.absoluteString
                }
            }
        }

        func webView(_ webView: WKWebView, didFail navigation: WKNavigation!, withError error: Error) {
            Task { @MainActor in
                viewModel.error = error
                viewModel.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, didFailProvisionalNavigation navigation: WKNavigation!, withError error: Error) {
            let nsError = error as NSError
            if nsError.domain == NSURLErrorDomain && nsError.code == NSURLErrorCancelled { return }
            Task { @MainActor in
                viewModel.error = error
                viewModel.isLoading = false
            }
        }

        func webView(_ webView: WKWebView, runOpenPanelWith parameters: WKOpenPanelParameters, initiatedByFrame frame: WKFrameInfo, completionHandler: @escaping ([URL]?) -> Void) {
            let panel = NSOpenPanel()
            panel.allowsMultipleSelection = parameters.allowsMultipleSelection
            panel.canChooseDirectories = parameters.allowsDirectories
            panel.canChooseFiles = true
            panel.begin { response in
                completionHandler(response == .OK ? panel.urls : nil)
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor navigationAction: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            decisionHandler(.allow)
        }
    }
}
