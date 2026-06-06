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
    @State private var inputText: String = ""
    
    var body: some View {
        VStack(spacing: 0) {
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
                .background(Color(nsColor: .textBackgroundColor))
                .foregroundColor(Color(nsColor: .textColor))
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
            
            // Input bar for interactive stdin (user-controlled toggle)
            if processManager.isRunning {
                Divider()
                if processManager.isAutoAnswering {
                    HStack(spacing: 8) {
                        Image(systemName: "arrow.trianglehead.2.clockwise")
                            .font(.system(size: 11))
                            .foregroundColor(.secondary)
                        Text("Auto-answering prompts")
                            .font(.system(.callout, design: .monospaced))
                            .foregroundColor(.secondary)
                        Spacer()
                        Button("Enable Input") {
                            processManager.stopAutoAnswering()
                        }
                        .buttonStyle(.bordered)
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                } else {
                    HStack(spacing: 8) {
                        TextField("Send input to process...", text: $inputText)
                            .textFieldStyle(.plain)
                            .font(.system(.body, design: .monospaced))
                            .foregroundColor(.primary)
                            .onSubmit {
                                sendInput()
                            }
                        
                        Button(action: sendInput) {
                            Text("Send")
                                .fontWeight(.semibold)
                        }
                        .buttonStyle(.borderedProminent)
                        .disabled(inputText.isEmpty)
                        
                        Button("Auto") {
                            processManager.startAutoAnswering()
                        }
                        .buttonStyle(.bordered)
                        .help("Switch back to auto-answering mode")
                    }
                    .padding(.horizontal, 12)
                    .padding(.vertical, 10)
                }
            }
        }
    }
    
    private func sendInput() {
        guard !inputText.isEmpty else { return }
        processManager.writeInput(inputText)
        inputText = ""
    }
}

#Preview("Terminal View") {
    TerminalView(processManager: ProcessManager())
        .frame(width: 600, height: 400)
}
