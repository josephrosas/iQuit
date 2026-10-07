import AppKit

struct ListedApp: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let name: String
    let bundleID: String?
    let pids: [pid_t]
    let icon: NSImage?
    let isBackground: Bool
    let isProtected: Bool
    let isMusic: Bool
    var cpuPercent: Double?
    var memoryBytes: UInt64
    var lastUsed: Date
    var isFrontmost: Bool

    var cpuIsHeavy: Bool { (cpuPercent ?? 0) >= 15 }
    var memoryIsHeavy: Bool { memoryBytes >= (1 << 30) }

    var formattedCPU: String {
        guard let cpuPercent else { return "—" }
        if cpuPercent < 0.05 { return "0%" }
        if cpuPercent < 10 { return String(format: "%.1f%%", cpuPercent) }
        return String(format: "%.0f%%", cpuPercent)
    }

    var formattedMemory: String {
        ByteCountFormatter.string(fromByteCount: Int64(memoryBytes), countStyle: .memory)
    }
}

@MainActor
final class RunningAppsService {
    private let metrics = ProcessMetrics()
    private var lastUsed: [String: Date] = [:]
    private var observers: [NSObjectProtocol] = []

    func start() {
        stop()
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didActivateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.markUsed(app)
            }
        })
        observers.append(workspace.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.markUsed(app)
            }
        })
    }

    func stop() {
        let center = NSWorkspace.shared.notificationCenter
        for observer in observers {
            center.removeObserver(observer)
        }
        observers.removeAll()
    }

    func markUsed(_ app: NSRunningApplication) {
        lastUsed[Self.key(for: app)] = Date()
    }

    func lastUsedDate(for key: String) -> Date? {
        lastUsed[key]
    }

    func discardCPUBaseline() {
        metrics.discardBaseline()
    }

    func snapshot(showBackground: Bool, frontmostPID: pid_t?) -> [ListedApp] {
        let running = NSWorkspace.shared.runningApplications
        let now = Date()
        var groups: [String: [NSRunningApplication]] = [:]

        for app in running {
            if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
                continue
            }
            if app.isTerminated {
                continue
            }
            if app.activationPolicy == .prohibited && !showBackground {
                continue
            }
            if app.activationPolicy == .accessory && !showBackground {
                continue
            }
            groups[Self.key(for: app), default: []].append(app)
        }

        var listed: [ListedApp] = []
        var seenPIDs = Set<pid_t>()

        for (key, instances) in groups {
            let representative = instances.max { lhs, rhs in
                Self.rank(lhs) < Self.rank(rhs)
            } ?? instances[0]

            let bundleID = representative.bundleIdentifier
            let isProtected = ProtectedApps.bundleIDs.contains(bundleID ?? "")
                || representative.localizedName == "Finder"
            if isProtected {
                continue
            }

            let isBackground = instances.allSatisfy { $0.activationPolicy != .regular }
            if isBackground && !showBackground {
                continue
            }

            var cpu = 0.0
            var cpuKnown = true
            var memory: UInt64 = 0
            var pids: [pid_t] = []
            for instance in instances {
                let pid = instance.processIdentifier
                pids.append(pid)
                seenPIDs.insert(pid)
                let sample = metrics.sample(pid: pid)
                if let value = sample.cpuPercent {
                    cpu += value
                } else {
                    cpuKnown = false
                }
                memory += sample.memoryBytes
            }

            if lastUsed[key] == nil {
                lastUsed[key] = now
            }

            listed.append(
                ListedApp(
                    key: key,
                    name: representative.localizedName ?? bundleID ?? "PID \(representative.processIdentifier)",
                    bundleID: bundleID,
                    pids: pids,
                    icon: representative.icon,
                    isBackground: isBackground,
                    isProtected: isProtected || ProtectedApps.bundleIDs.contains(bundleID ?? ""),
                    isMusic: ProtectedApps.musicBundleIDs.contains(bundleID ?? ""),
                    cpuPercent: cpuKnown ? cpu : nil,
                    memoryBytes: memory,
                    lastUsed: lastUsed[key] ?? now,
                    isFrontmost: pids.contains(where: { $0 == frontmostPID })
                )
            )
        }

        metrics.prune(keeping: seenPIDs)
        return listed
    }

    func runningApplications(for listed: ListedApp) -> [NSRunningApplication] {
        listed.pids.compactMap { pid in
            NSRunningApplication(processIdentifier: pid)
        }
    }

    private static func key(for app: NSRunningApplication) -> String {
        if let bundleID = app.bundleIdentifier, !bundleID.isEmpty {
            return bundleID
        }
        return "pid:\(app.processIdentifier)"
    }

    private static func rank(_ app: NSRunningApplication) -> Int {
        switch app.activationPolicy {
        case .regular: return 2
        case .accessory: return 1
        default: return 0
        }
    }
}
