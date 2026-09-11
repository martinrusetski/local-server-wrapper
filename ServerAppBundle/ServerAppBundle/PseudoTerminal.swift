//
//  PseudoTerminal.swift
//  ServerAppBundle
//

import Foundation
import Darwin

// NOTE: This type is DUPLICATED across both Xcode projects and must be kept byte-identical
// (modulo this file's top header comment):
//   - ServerAppBundle/ServerAppBundle/PseudoTerminal.swift                       (runtime)
//   - LocalServerWrapper/.../LocalServerWrapper/Utilities/PseudoTerminal.swift   (manager)
// Any change here must be mirrored in the manager's twin implementation.

/// A pseudo-terminal (PTY) for launching a server so it believes it's attached to a real interactive
/// terminal. Many launch scripts gate behaviour on `isatty(stdout)` / `[[ -t 1 ]]` — they only start
/// the server, stream output live, or print their URL when they think a human is watching. Capturing
/// output through an ordinary pipe fails that check, so those servers behave differently (or don't
/// start at all). Wiring the child's stdio to a PTY slave makes `isatty` return true, so the server
/// runs exactly as it would if the user had launched it in Terminal.app.
///
/// Usage: set a Process's standard in/out/err to `slaveHandle`, run it, then call
/// `closeSlaveAfterLaunch()` and `readInBackground(...)`. Input is sent with `write(_:)`.
final class PseudoTerminal {

    /// The master side — what we read the child's output from and write its input to.
    let masterFD: Int32

    /// FileHandle wrapping the slave side. Assign this to a Process's standardInput/Output/Error.
    let slaveHandle: FileHandle

    private let slaveFD: Int32
    private var masterClosed = false
    private let closeLock = NSLock()

    /// Create a PTY pair sized like a typical terminal window. Returns nil if the OS can't allocate
    /// one (extremely rare), in which case callers fall back to ordinary pipes.
    init?(columns: UInt16 = 120, rows: UInt16 = 40) {
        var master: Int32 = 0
        var slave: Int32 = 0
        var size = winsize(ws_row: rows, ws_col: columns, ws_xpixel: 0, ws_ypixel: 0)
        guard openpty(&master, &slave, nil, nil, &size) == 0 else { return nil }
        self.masterFD = master
        self.slaveFD = slave
        self.slaveHandle = FileHandle(fileDescriptor: slave, closeOnDealloc: false)
    }

    /// Close the parent's copy of the slave fd right after `Process.run()`. Required so the master
    /// reports EOF once the child (which holds its own dup of the slave) exits.
    func closeSlaveAfterLaunch() {
        close(slaveFD)
    }

    /// Read the child's output on a background thread until the stream closes, delivering raw chunks
    /// via `onData` and calling `onEnd` exactly once at EOF. Callbacks run on a background queue.
    ///
    /// Uses a blocking `read()` loop rather than FileHandle's readability handler: on macOS, reading
    /// a PTY master after the child exits returns EIO, which FileHandle surfaces as a thrown
    /// exception (a crash). A raw `read()` simply returns ≤ 0, which we treat as end-of-stream.
    func readInBackground(onData: @escaping (Data) -> Void, onEnd: @escaping () -> Void) {
        DispatchQueue.global(qos: .userInitiated).async { [masterFD] in
            var buffer = [UInt8](repeating: 0, count: 8192)
            while true {
                let count = read(masterFD, &buffer, buffer.count)
                if count > 0 {
                    onData(Data(bytes: buffer, count: count))
                } else {
                    break   // 0 = EOF; < 0 = EIO after the child closed the slave
                }
            }
            onEnd()
        }
    }

    /// Send bytes to the child's stdin (through the terminal).
    func write(_ data: Data) {
        guard !data.isEmpty else { return }
        data.withUnsafeBytes { raw in
            if let base = raw.baseAddress { _ = Darwin.write(masterFD, base, raw.count) }
        }
    }

    /// Close the master fd. Also unblocks the background reader. Idempotent.
    func closeMaster() {
        closeLock.lock(); defer { closeLock.unlock() }
        guard !masterClosed else { return }
        masterClosed = true
        close(masterFD)
    }
}
