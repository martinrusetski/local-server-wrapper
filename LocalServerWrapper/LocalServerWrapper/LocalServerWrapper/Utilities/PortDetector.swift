//
//  PortDetector.swift
//  LocalServerWrapper
//

import Foundation
import Darwin

// NOTE: This type is DUPLICATED across both Xcode projects and must be kept byte-identical
// (modulo this file's top header comment):
//   - ServerAppBundle/ServerAppBundle/PortDetector.swift                       (runtime)
//   - LocalServerWrapper/.../LocalServerWrapper/Utilities/PortDetector.swift   (manager)
// Any change here must be mirrored in the runtime's twin implementation.

/// Discovers which TCP ports a process tree is actually listening on by asking the OS, instead of
/// parsing the server's stdout. This is the ground-truth source for the server's port in automatic
/// detection mode: it works even when the server prints nothing useful and when it grabs a dynamic
/// or auto-incremented free port at startup (e.g. Vite bumping 3000 → 3001).
enum PortDetector {

    /// `rootPID` plus all of its descendant PIDs.
    ///
    /// A launch command like `npm run dev` or `start.sh` spawns the real server as a grandchild
    /// (`npm` → `node`, `sh` → `uvicorn`). The listening socket lives on that descendant, so we
    /// must scan the whole tree, not just the direct child.
    ///
    /// Built from a full `sysctl(KERN_PROC_ALL)` parent map (the same approach ProcessManager uses
    /// for termination, and for the same reason: `proc_listchildpids` under-reports children).
    static func processTree(rootPID: pid_t) -> [pid_t] {
        var childrenOf: [pid_t: [pid_t]] = [:]
        for entry in processParentPairs() {
            childrenOf[entry.ppid, default: []].append(entry.pid)
        }

        var collected: [pid_t] = [rootPID]
        var queue: [pid_t] = [rootPID]
        while let parent = queue.popLast() {
            for child in childrenOf[parent] ?? [] where !collected.contains(child) {
                collected.append(child)
                queue.append(child)
            }
        }
        return collected
    }

    /// Convenience: the listening ports held anywhere in `rootPID`'s process tree.
    static func listeningPorts(forTreeOf rootPID: pid_t) -> [Int] {
        listeningPorts(for: processTree(rootPID: rootPID))
    }

    /// The loopback-reachable TCP ports in LISTEN state held by any of `pids`, sorted ascending.
    /// Returns an empty array if none are found (or `lsof` is unavailable).
    static func listeningPorts(for pids: [pid_t]) -> [Int] {
        guard !pids.isEmpty else { return [] }

        let lsofPath = "/usr/sbin/lsof"
        guard FileManager.default.isExecutableFile(atPath: lsofPath) else { return [] }

        let process = Process()
        process.executableURL = URL(fileURLWithPath: lsofPath)
        process.arguments = [
            "-nP",                                              // numeric host/port, no DNS lookups
            "-iTCP",                                            // TCP sockets only…
            "-sTCP:LISTEN",                                     // …in LISTEN state
            "-a",                                               // AND the filters together
            "-p", pids.map(String.init).joined(separator: ","), // restricted to our process tree
            "-F", "n"                                          // machine-readable: name fields, "n"-prefixed
        ]

        let outPipe = Pipe()
        process.standardOutput = outPipe
        process.standardError = Pipe()   // swallow "no listening sockets" diagnostics

        do {
            try process.run()
        } catch {
            return []
        }

        // Read before waiting so a large response can't deadlock the pipe (lsof output is tiny here,
        // but this keeps the contract correct).
        let data = outPipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()

        guard let text = String(data: data, encoding: .utf8) else { return [] }

        var ports = Set<Int>()
        for line in text.split(separator: "\n") {
            // Name lines look like "n*:5173", "n127.0.0.1:5173", "n[::1]:5173". The port is whatever
            // follows the final colon — correct for IPv6 bracket forms too.
            guard line.first == "n", let colon = line.lastIndex(of: ":") else { continue }
            let portString = line[line.index(after: colon)...]
            if let port = Int(portString) { ports.insert(port) }
        }
        return ports.sorted()
    }

    // MARK: - Private

    /// (pid, ppid) for every process on the system, via `sysctl(KERN_PROC_ALL)`.
    private static func processParentPairs() -> [(pid: pid_t, ppid: pid_t)] {
        var mib: [Int32] = [CTL_KERN, KERN_PROC, KERN_PROC_ALL, 0]
        var length = 0
        guard sysctl(&mib, UInt32(mib.count), nil, &length, nil, 0) == 0, length > 0 else { return [] }

        let stride = MemoryLayout<kinfo_proc>.stride
        var procs = [kinfo_proc](repeating: kinfo_proc(), count: length / stride + 1)
        guard sysctl(&mib, UInt32(mib.count), &procs, &length, nil, 0) == 0 else { return [] }

        let count = length / stride
        return procs.prefix(count).map { (pid: $0.kp_proc.p_pid, ppid: $0.kp_eproc.e_ppid) }
    }
}
