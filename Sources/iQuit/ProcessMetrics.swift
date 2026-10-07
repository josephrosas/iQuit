import Darwin
import Foundation

struct ProcessSample: Equatable {
    var cpuPercent: Double?
    var memoryBytes: UInt64
}

/// Per-PID CPU and memory sampling. CPU% is derived from the delta in consumed
/// CPU time between two samples, so the first sample for a PID has no CPU value.
final class ProcessMetrics {
    private struct Snapshot {
        var cpuNanos: UInt64
        var timestamp: TimeInterval
        var cpuPercent: Double?
    }

    private var previous: [pid_t: Snapshot] = [:]
    private let clock: () -> TimeInterval

    /// Minimum spacing between two samples used to compute a new CPU value.
    static let minimumInterval: TimeInterval = 0.05

    init(clock: @escaping () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.clock = clock
    }

    func sample(pid: pid_t) -> ProcessSample {
        var usage = rusage_info_v4()
        let status = withUnsafeMutablePointer(to: &usage) { pointer in
            pointer.withMemoryRebound(to: rusage_info_t?.self, capacity: 1) { rebound in
                proc_pid_rusage(pid, RUSAGE_INFO_V4, rebound)
            }
        }

        guard status == 0 else {
            previous.removeValue(forKey: pid)
            return ProcessSample(cpuPercent: nil, memoryBytes: 0)
        }

        return record(
            pid: pid,
            cpuNanos: usage.ri_user_time + usage.ri_system_time,
            memoryBytes: usage.ri_phys_footprint,
            now: clock()
        )
    }

    /// Pure bookkeeping, split out so the CPU math can be tested without live processes.
    func record(pid: pid_t, cpuNanos: UInt64, memoryBytes: UInt64, now: TimeInterval) -> ProcessSample {
        if let last = previous[pid] {
            let deltaTime = now - last.timestamp
            if deltaTime > Self.minimumInterval {
                // Counters only decrease on PID reuse; treat that as a fresh baseline (0 %).
                let deltaCPU = cpuNanos >= last.cpuNanos ? Double(cpuNanos - last.cpuNanos) : 0
                let cpuPercent = (deltaCPU / (deltaTime * 1_000_000_000)) * 100
                previous[pid] = Snapshot(cpuNanos: cpuNanos, timestamp: now, cpuPercent: cpuPercent)
                return ProcessSample(cpuPercent: cpuPercent, memoryBytes: memoryBytes)
            }
            return ProcessSample(cpuPercent: last.cpuPercent, memoryBytes: memoryBytes)
        }
        previous[pid] = Snapshot(cpuNanos: cpuNanos, timestamp: now, cpuPercent: nil)
        return ProcessSample(cpuPercent: nil, memoryBytes: memoryBytes)
    }

    func discardBaseline() {
        previous.removeAll()
    }

    func prune(keeping pids: Set<pid_t>) {
        previous = previous.filter { pids.contains($0.key) }
    }
}
