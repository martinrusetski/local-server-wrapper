//
//  TerminalView.swift
//  ServerAppBundle
//
//  Created by Kiro
//

import SwiftUI

/// A terminal-like view that displays process output with ANSI colors, auto-scrolling,
/// and text selection. The colored render comes from `processManager.attributedOutput`,
/// which is produced by an ANSI emulator (see `ANSITerminal` below).
struct TerminalView: View {
    @ObservedObject var processManager: ProcessManager
    @State private var inputText: String = ""

    var body: some View {
        VStack(spacing: 0) {
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: 0) {
                        Text(processManager.attributedOutput)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(10)
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
                                    .font(.system(size: 12, design: .monospaced))
                                    .fontWeight(.bold)
                                    .foregroundColor(exitCode == 0 ? .green : .red)
                            }
                            .padding(10)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .id("exitCode")
                            .accessibilityLabel("Process Exit Status")
                            .accessibilityValue("Process exited with code \(exitCode)")
                            .accessibilityAddTraits(exitCode == 0 ? [] : .isStaticText)
                        }
                    }
                }
                .background(ANSITerminal.defaultBackground)
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

// MARK: - ANSI terminal emulator
//
// A compact, streaming ANSI/VT100 interpreter sufficient for server logs and CLI tooling
// (npm, vite, pip, etc.): SGR colors/styles, carriage-return progress overwrites, tab stops,
// line/screen erase, and basic cursor movement. Unknown escape sequences are consumed rather
// than printed literally, which is what previously made output look garbled. Defined here
// (rather than a new file) to avoid Xcode project/target surgery.

/// A resolved RGB color. Kept as plain components so `TerminalStyle` stays `Equatable`
/// (used to coalesce runs) and independent of any palette object.
struct TerminalColor: Equatable {
    var r: Double
    var g: Double
    var b: Double

    init(_ r: Double, _ g: Double, _ b: Double) {
        self.r = r; self.g = g; self.b = b
    }

    init(rgb255 r: Int, _ g: Int, _ b: Int) {
        self.r = Double(r) / 255.0
        self.g = Double(g) / 255.0
        self.b = Double(b) / 255.0
    }

    var color: Color { Color(red: r, green: g, blue: b) }
}

/// Visual attributes for one cell, derived from ANSI SGR (Select Graphic Rendition) codes.
struct TerminalStyle: Equatable {
    var fg: TerminalColor?
    var bg: TerminalColor?
    var bold = false
    var dim = false
    var italic = false
    var underline = false
    var inverse = false
}

/// A single character plus the style it was written with.
struct TerminalCell {
    var character: Character
    var style: TerminalStyle
}

/// Streaming ANSI terminal emulator. Feed it decoded text chunks; read `plainText` for a
/// stripped log/accessibility string and `attributedString()` for the colored SwiftUI render.
/// Used only from the main actor (by `ProcessManager`), so it is intentionally not synchronized.
final class ANSITerminal {
    static let defaultForeground = Color(red: 0.83, green: 0.84, blue: 0.81) // Tango aluminium
    static let defaultBackground = Color(red: 0.12, green: 0.12, blue: 0.12) // ~#1E1E1E

    private(set) var lines: [[TerminalCell]] = [[]]
    private var cursorRow = 0
    private var cursorCol = 0
    private var style = TerminalStyle()

    /// Hard cap on retained lines so a chatty long-running server can't grow without bound and
    /// each render stays O(maxLines). Oldest lines are dropped from the front.
    private let maxLines = 5000

    // Escape-sequence parser state, preserved across `feed` calls so a sequence split across two
    // read chunks is still interpreted correctly.
    private enum Mode { case normal, escape, csi, osc }
    private var mode: Mode = .normal
    private var csiBuffer = ""
    private var oscSawEsc = false

    // MARK: Feeding

    func feed(_ text: String) {
        for scalar in text.unicodeScalars {
            process(scalar)
        }
    }

    func reset() {
        lines = [[]]
        cursorRow = 0
        cursorCol = 0
        style = TerminalStyle()
        mode = .normal
        csiBuffer = ""
        oscSawEsc = false
    }

    private func process(_ scalar: Unicode.Scalar) {
        switch mode {
        case .normal: handleNormal(scalar)
        case .escape: handleEscape(scalar)
        case .csi: handleCSI(scalar)
        case .osc: handleOSC(scalar)
        }
    }

    private func handleNormal(_ scalar: Unicode.Scalar) {
        switch scalar.value {
        case 0x1B: mode = .escape
        case 0x0A: newline()
        case 0x0D: cursorCol = 0
        case 0x09: tab()
        case 0x08: if cursorCol > 0 { cursorCol -= 1 }
        case 0x00..<0x20: break // bell and other C0 controls: ignore
        default: putChar(Character(scalar))
        }
    }

    private func handleEscape(_ scalar: Unicode.Scalar) {
        switch scalar.value {
        case 0x5B: // '['
            mode = .csi
            csiBuffer = ""
        case 0x5D: // ']'
            mode = .osc
            oscSawEsc = false
        case 0x1B:
            break // stay in escape
        default:
            // Two-character escapes (ESC c, ESC M, ESC =, …): consume and resume.
            mode = .normal
        }
    }

    private func handleCSI(_ scalar: Unicode.Scalar) {
        // Final byte is in 0x40...0x7E; parameter/intermediate bytes precede it.
        if scalar.value >= 0x40 && scalar.value <= 0x7E {
            executeCSI(final: Character(scalar), params: csiBuffer)
            mode = .normal
            csiBuffer = ""
        } else {
            if csiBuffer.count < 64 { // guard against a runaway/garbage sequence
                csiBuffer.append(Character(scalar))
            }
        }
    }

    private func handleOSC(_ scalar: Unicode.Scalar) {
        // OSC ... terminated by BEL (0x07) or ST (ESC backslash). We don't use the payload
        // (window title, hyperlinks, color queries); just swallow it.
        if oscSawEsc {
            mode = .normal
            oscSawEsc = false
        } else if scalar.value == 0x07 {
            mode = .normal
        } else if scalar.value == 0x1B {
            oscSawEsc = true
        }
    }

    // MARK: CSI execution

    private func executeCSI(final: Character, params: String) {
        let nums = params.split(separator: ";", omittingEmptySubsequences: false).map { Int($0) }
        func param(_ index: Int, default def: Int) -> Int {
            guard index < nums.count, let v = nums[index] else { return def }
            return v
        }

        switch final {
        case "m":
            applySGR(nums.map { $0 ?? 0 }, raw: nums)
        case "A": cursorRow = max(0, cursorRow - max(1, param(0, default: 1)))
        case "B":
            cursorRow = min(max(0, lines.count - 1), cursorRow + max(1, param(0, default: 1)))
        case "C": cursorCol += max(1, param(0, default: 1))
        case "D": cursorCol = max(0, cursorCol - max(1, param(0, default: 1)))
        case "G": cursorCol = max(0, param(0, default: 1) - 1)
        case "K": eraseLine(param(0, default: 0))
        case "J": eraseDisplay(param(0, default: 0))
        default:
            break // H/f absolute positioning and other rare ops: ignored (no scrollback model)
        }
    }

    private func applySGR(_ codes: [Int], raw: [Int?]) {
        if codes.isEmpty {
            style = TerminalStyle()
            return
        }
        var i = 0
        while i < codes.count {
            let c = codes[i]
            switch c {
            case 0: style = TerminalStyle()
            case 1: style.bold = true
            case 2: style.dim = true
            case 3: style.italic = true
            case 4: style.underline = true
            case 7: style.inverse = true
            case 22: style.bold = false; style.dim = false
            case 23: style.italic = false
            case 24: style.underline = false
            case 27: style.inverse = false
            case 30...37: style.fg = Self.standardColor(c - 30)
            case 90...97: style.fg = Self.standardColor(c - 90 + 8)
            case 39: style.fg = nil
            case 40...47: style.bg = Self.standardColor(c - 40)
            case 100...107: style.bg = Self.standardColor(c - 100 + 8)
            case 49: style.bg = nil
            case 38:
                if let color = extendedColor(codes, &i) { style.fg = color }
            case 48:
                if let color = extendedColor(codes, &i) { style.bg = color }
            default: break
            }
            i += 1
        }
    }

    /// Parse a `38`/`48` extended-color operand: `5;n` (256-color) or `2;r;g;b` (truecolor).
    /// Advances `i` past the consumed operands.
    private func extendedColor(_ codes: [Int], _ i: inout Int) -> TerminalColor? {
        guard i + 1 < codes.count else { return nil }
        let kind = codes[i + 1]
        if kind == 5, i + 2 < codes.count {
            let color = Self.xterm256(codes[i + 2])
            i += 2
            return color
        } else if kind == 2, i + 4 < codes.count {
            let color = TerminalColor(rgb255: codes[i + 2], codes[i + 3], codes[i + 4])
            i += 4
            return color
        }
        return nil
    }

    // MARK: Buffer editing

    private func putChar(_ character: Character) {
        ensureCursorRow()
        padCurrentLine(to: cursorCol)
        let cell = TerminalCell(character: character, style: style)
        if cursorCol < lines[cursorRow].count {
            lines[cursorRow][cursorCol] = cell
        } else {
            lines[cursorRow].append(cell)
        }
        cursorCol += 1
    }

    private func newline() {
        cursorRow += 1
        cursorCol = 0
        if cursorRow >= lines.count {
            lines.append([])
        }
        trimIfNeeded()
    }

    private func tab() {
        let next = ((cursorCol / 8) + 1) * 8
        ensureCursorRow()
        padCurrentLine(to: next)
        cursorCol = next
    }

    private func eraseLine(_ kind: Int) {
        ensureCursorRow()
        switch kind {
        case 0: // cursor to end
            if cursorCol < lines[cursorRow].count {
                lines[cursorRow].removeSubrange(cursorCol...)
            }
        case 1: // start to cursor
            let end = min(cursorCol, lines[cursorRow].count - 1)
            if end >= 0 {
                for j in 0...end {
                    lines[cursorRow][j] = TerminalCell(character: " ", style: TerminalStyle())
                }
            }
        default: // 2: whole line
            lines[cursorRow] = []
        }
    }

    private func eraseDisplay(_ kind: Int) {
        switch kind {
        case 0: // cursor to end of screen
            ensureCursorRow()
            if cursorCol < lines[cursorRow].count {
                lines[cursorRow].removeSubrange(cursorCol...)
            }
            if cursorRow + 1 < lines.count {
                lines.removeSubrange((cursorRow + 1)...)
            }
        default: // 2 / 3: whole display
            reset()
        }
    }

    private func ensureCursorRow() {
        while cursorRow >= lines.count {
            lines.append([])
        }
    }

    private func padCurrentLine(to count: Int) {
        while lines[cursorRow].count < count {
            lines[cursorRow].append(TerminalCell(character: " ", style: TerminalStyle()))
        }
    }

    private func trimIfNeeded() {
        guard lines.count > maxLines else { return }
        let remove = lines.count - maxLines
        lines.removeFirst(remove)
        cursorRow = max(0, cursorRow - remove)
    }

    // MARK: Rendering

    /// Plain text (no escape codes), trailing blanks trimmed per line. Used for the log buffer,
    /// accessibility, and tests.
    var plainText: String {
        lines.map { cells in
            var s = String(cells.map { $0.character })
            while s.hasSuffix(" ") { s.removeLast() }
            return s
        }.joined(separator: "\n")
    }

    /// Colored render for SwiftUI. Consecutive cells with identical styling are coalesced into
    /// one attributed run.
    func attributedString() -> AttributedString {
        var result = AttributedString()
        for (index, cells) in lines.enumerated() {
            appendLine(cells, to: &result)
            if index < lines.count - 1 {
                result.append(AttributedString("\n"))
            }
        }
        return result
    }

    private func appendLine(_ cells: [TerminalCell], to result: inout AttributedString) {
        // Drop trailing default-styled blanks (padding artifacts) so lines don't carry dead width.
        var cells = cells
        while let last = cells.last, last.character == " ", last.style == TerminalStyle() {
            cells.removeLast()
        }

        var i = 0
        while i < cells.count {
            let runStyle = cells[i].style
            var text = ""
            var j = i
            while j < cells.count && cells[j].style == runStyle {
                text.append(cells[j].character)
                j += 1
            }
            var run = AttributedString(text)
            apply(runStyle, to: &run)
            result.append(run)
            i = j
        }
    }

    private func apply(_ style: TerminalStyle, to run: inout AttributedString) {
        var font = Font.system(size: 12, weight: style.bold ? .bold : .regular, design: .monospaced)
        if style.italic { font = font.italic() }
        run.font = font

        var fg = style.fg?.color ?? Self.defaultForeground
        var bg = style.bg?.color
        if style.inverse {
            let newFg = bg ?? Self.defaultBackground
            bg = fg
            fg = newFg
        }
        if style.dim { fg = fg.opacity(0.6) }
        run.foregroundColor = fg
        if let bg { run.backgroundColor = bg }
        if style.underline { run.underlineStyle = .single }
    }

    // MARK: Palette

    /// The 16 base ANSI colors (Tango palette — high contrast on a dark background).
    static func standardColor(_ index: Int) -> TerminalColor {
        switch index {
        case 0: return TerminalColor(rgb255: 0, 0, 0)
        case 1: return TerminalColor(rgb255: 204, 0, 0)
        case 2: return TerminalColor(rgb255: 78, 154, 6)
        case 3: return TerminalColor(rgb255: 196, 160, 0)
        case 4: return TerminalColor(rgb255: 52, 101, 164)
        case 5: return TerminalColor(rgb255: 117, 80, 123)
        case 6: return TerminalColor(rgb255: 6, 152, 154)
        case 7: return TerminalColor(rgb255: 211, 215, 207)
        case 8: return TerminalColor(rgb255: 85, 87, 83)
        case 9: return TerminalColor(rgb255: 239, 41, 41)
        case 10: return TerminalColor(rgb255: 138, 226, 52)
        case 11: return TerminalColor(rgb255: 252, 233, 79)
        case 12: return TerminalColor(rgb255: 114, 159, 207)
        case 13: return TerminalColor(rgb255: 173, 127, 168)
        case 14: return TerminalColor(rgb255: 52, 226, 226)
        default: return TerminalColor(rgb255: 238, 238, 236)
        }
    }

    /// Map an xterm 256-color index to RGB (16 base + 6×6×6 cube + 24 grayscale).
    static func xterm256(_ n: Int) -> TerminalColor {
        if n < 16 { return standardColor(n) }
        if n >= 232 {
            let v = 8 + (n - 232) * 10
            return TerminalColor(rgb255: v, v, v)
        }
        let c = n - 16
        let r = c / 36
        let g = (c % 36) / 6
        let b = c % 6
        func component(_ value: Int) -> Int { value == 0 ? 0 : 55 + value * 40 }
        return TerminalColor(rgb255: component(r), component(g), component(b))
    }

    // MARK: Stripping (for non-visual consumers)

    private static let ansiRegex = try? NSRegularExpression(
        pattern: "\u{1B}\\[[0-9;?]*[ -/]*[@-~]|\u{1B}\\][^\u{07}]*(?:\u{07}|\u{1B}\\\\)|\u{1B}.",
        options: []
    )

    /// Remove ANSI escape sequences from a string. Used to feed readiness detection clean text so
    /// color codes can't break ready-signal / port regexes.
    static func strip(_ text: String) -> String {
        guard let regex = ansiRegex else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, options: [], range: range, withTemplate: "")
    }
}
