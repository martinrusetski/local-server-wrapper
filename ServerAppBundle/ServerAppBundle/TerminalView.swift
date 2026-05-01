//
//  TerminalView.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import SwiftUI

/// A terminal-like view that displays process output with auto-scrolling and text selection
struct TerminalView: View {
    @ObservedObject var processManager: ProcessManager
    @State private var scrollViewID = UUID()
    
    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 0) {
                    Text(processManager.output)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(8)
                        .id("outputText")
                        .accessibilityLabel("Terminal Output")
                        .accessibilityValue(processManager.output.isEmpty ? "No output yet" : processManager.output)
                        .accessibilityHint("Server process output and logs")
                    
                    // Exit code display when process terminates
                    if let exitCode = processManager.exitCode {
                        Divider()
                            .background(exitCode == 0 ? Color.green : Color.red)
                            .padding(.vertical, 4)
                        
                        HStack {
                            Image(systemName: exitCode == 0 ? "checkmark.circle.fill" : "xmark.circle.fill")
                                .foregroundColor(exitCode == 0 ? .green : .red)
                            
                            Text("Process exited with code \(exitCode)")
                                .font(.system(.body, design: .monospaced))
                                .fontWeight(.bold)
                                .foregroundColor(exitCode == 0 ? .green : .red)
                        }
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .id("exitCode")
                        .accessibilityLabel("Process Exit Status")
                        .accessibilityValue("Process exited with code \(exitCode)")
                        .accessibilityAddTraits(exitCode == 0 ? [] : .isStaticText)
                    }
                }
            }
            .background(Color(nsColor: .textBackgroundColor).opacity(0.95))
            .foregroundColor(.white)
            .accessibilityElement(children: .contain)
            .accessibilityLabel("Terminal View")
            .onChange(of: processManager.output) { _ in
                // Auto-scroll to bottom when new output arrives
                withAnimation(.easeOut(duration: 0.1)) {
                    proxy.scrollTo("exitCode", anchor: .bottom)
                    // If no exit code yet, scroll to the output text
                    if processManager.exitCode == nil {
                        proxy.scrollTo("outputText", anchor: .bottom)
                    }
                }
            }
            .onChange(of: processManager.exitCode) { _ in
                // Scroll to exit code when it appears
                if processManager.exitCode != nil {
                    withAnimation(.easeOut(duration: 0.2)) {
                        proxy.scrollTo("exitCode", anchor: .bottom)
                    }
                }
            }
        }
    }
}

#Preview("Terminal View") {
    TerminalView(processManager: ProcessManager())
        .frame(width: 600, height: 400)
}
