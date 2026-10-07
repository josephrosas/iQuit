import Darwin
import Foundation

/// Parent/child map of every process on the system, used to fold helper processes
/// (Chrome/Electron renderers, Terminal shells, …) into the app that owns them.
struct ProcessTree: Equatable {
    let parent: [pid_t: pid_t]
    private(set) var children: [pid_t: [pid_t]] = [:]

    init(parent: [pid_t: pid_t]) {
        self.parent = parent
        var children: [pid_t: [pid_t]] = [:]
        for (pid, ppid) in parent where pid != ppid {
            children[ppid, default: []].append(pid)
        }
        self.children = children
    }

    /// Snapshot of the live process table. Costs a few milliseconds for ~600 processes.
    static func current() -> ProcessTree {
        var count = proc_listpids(UInt32(PROC_ALL_PIDS), 0, nil, 0)
        guard count > 0 else { return ProcessTree(parent: [:]) }
        var pids = [pid_t](repeating: 0, count: Int(count) / MemoryLayout<pid_t>.size + 64)
        count = pids.withUnsafeMutableBytes { buffer in
            proc_listpids(UInt32(PROC_ALL_PIDS), 0, buffer.baseAddress, Int32(buffer.count))
        }
        let total = Int(count) / MemoryLayout<pid_t>.size
        var parent: [pid_t: pid_t] = [:]
        parent.reserveCapacity(total)
        var info = proc_bsdinfo()
        let size = Int32(MemoryLayout<proc_bsdinfo>.size)
        for pid in pids.prefix(total) where pid > 0 {
            let got = proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &info, size)
            guard got == size else { continue }
            parent[pid] = pid_t(info.pbi_ppid)
        }
        return ProcessTree(parent: parent)
    }

    /// Nearest ancestor of `pid` that is in `anchors`, or nil if we reach the root first.
    func owner(of pid: pid_t, anchors: Set<pid_t>) -> pid_t? {
        var current = pid
        var hops = 0
        while let next = parent[current], next > 1, hops < 64 {
            if anchors.contains(next) { return next }
            current = next
            hops += 1
        }
        return nil
    }

    /// All descendants of `root`, not descending into (or including) any pid in `stopAt`.
    func descendants(of root: pid_t, stoppingAt stopAt: Set<pid_t>) -> [pid_t] {
        var result: [pid_t] = []
        var stack = children[root] ?? []
        var seen: Set<pid_t> = [root]
        while let pid = stack.popLast() {
            guard !seen.contains(pid), !stopAt.contains(pid) else { continue }
            seen.insert(pid)
            result.append(pid)
            if let kids = children[pid] {
                stack.append(contentsOf: kids)
            }
        }
        return result
    }
}
