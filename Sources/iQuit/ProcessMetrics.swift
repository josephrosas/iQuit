import Darwin
import Foundation

struct ProcessSample {
    var cpuPercent: Double?
    var memoryBytes: UInt64
}

final class ProcessMetrics {
    private struct Snapshot {
        var cpuNanos: UInt64
        var timestamp: TimeInterval
        var cpuPercent: Double?
    }

    private var previous: [pid_t: Snapshot] = [:]

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

        let now = ProcessInfo.processInfo.systemUptime
        let cpuNanos = usage.ri_user_time + usage.ri_system_time
        if let last = previous[pid] {
            let deltaTime = now - last.timestamp
            if deltaTime > 0.05 {
                let deltaCPU = Double(cpuNanos &- last.cpuNanos)
                let percent = (deltaCPU / (deltaTime * 1_000_000_000)) * 100
                let cpuPercent = percent < 0 ? 0 : percent
                previous[pid] = Snapshot(cpuNanos: cpuNanos, timestamp: now, cpuPercent: cpuPercent)
                return ProcessSample(cpuPercent: cpuPercent, memoryBytes: usage.ri_phys_footprint)
            }
            return ProcessSample(cpuPercent: last.cpuPercent, memoryBytes: usage.ri_phys_footprint)
        }
        previous[pid] = Snapshot(cpuNanos: cpuNanos, timestamp: now, cpuPercent: nil)
        return ProcessSample(cpuPercent: nil, memoryBytes: usage.ri_phys_footprint)
    }

    func discardBaseline() {
        previous.removeAll()
    }

    func prune(keeping pids: Set<pid_t>) {
        previous = previous.filter { pids.contains($0.key) }
    }
}
