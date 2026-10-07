import AppKit

/// One row in the list: an app (grouped by bundle ID) plus the live metrics of it and its helpers.
/// Icons live in `IconCache` so this stays a cheap value type whose equality is meaningful.
struct ListedApp: Identifiable, Hashable {
    var id: String { key }
    let key: String
    let name: String
    let bundleID: String?
    let bundleURL: URL?
    /// PIDs of the NSRunningApplication instances; these are the quit targets.
    let pids: [pid_t]
    /// Child processes folded into this row for CPU/memory accounting.
    let helperPIDs: [pid_t]
    let isBackground: Bool
    let isMusic: Bool
    var cpuPercent: Double?
    var memoryBytes: UInt64
    var lastUsed: Date
    var isFrontmost: Bool
    var hasVisibleWindows: Bool

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
final class IconCache {
    private var icons: [String: NSImage] = [:]

    func icon(for key: String) -> NSImage? {
        icons[key]
    }

    func store(_ icon: NSImage?, for key: String) {
        guard icons[key] == nil, let icon else { return }
        icons[key] = icon
    }

    func prune(keeping keys: Set<String>) {
        icons = icons.filter { keys.contains($0.key) }
    }
}

@MainActor
final class RunningAppsService {
    let icons = IconCache()
    private let metrics = ProcessMetrics()
    private var lastUsed: [String: Date] = [:]
    private var observers: [NSObjectProtocol] = []

    /// Called when an app is activated or launched, with its list key.
    var onActivate: ((String) -> Void)?
    /// Called when the set of running apps changes (launch or terminate).
    var onRunningAppsChanged: (() -> Void)?

    func start() {
        stop()
        let center = NSWorkspace.shared.notificationCenter
        observers.append(center.addObserver(
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
        observers.append(center.addObserver(
            forName: NSWorkspace.didLaunchApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else {
                return
            }
            Task { @MainActor in
                self?.markUsed(app)
                self?.onRunningAppsChanged?()
            }
        })
        observers.append(center.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            Task { @MainActor in
                self?.onRunningAppsChanged?()
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
        let key = Self.key(for: app)
        lastUsed[key] = Date()
        onActivate?(key)
    }

    func discardCPUBaseline() {
        metrics.discardBaseline()
    }

    func snapshot(frontmostPID: pid_t?) -> [ListedApp] {
        let now = Date()
        let selfPID = ProcessInfo.processInfo.processIdentifier
        let tree = ProcessTree.current()
        let windowOwners = VisibleWindows.ownerPIDs()

        // 1. Candidates: everything we are allowed to show.
        var candidates: [NSRunningApplication] = []
        var byPID: [pid_t: NSRunningApplication] = [:]
        var uiPIDs: Set<pid_t> = []
        for app in NSWorkspace.shared.runningApplications {
            if app.processIdentifier == selfPID || app.isTerminated { continue }
            guard ProcessPolicy.shouldList(
                bundleID: app.bundleIdentifier,
                localizedName: app.localizedName,
                policy: app.activationPolicy,
                executablePath: app.executableURL?.path
            ) else { continue }
            candidates.append(app)
            byPID[app.processIdentifier] = app
            if app.activationPolicy != .prohibited {
                uiPIDs.insert(app.processIdentifier)
            }
        }

        // 2. Anchors are UI apps that are not helpers nested inside an ancestor app's bundle
        //    (Electron helpers are LSUIElement apps living in Parent.app/Contents/Frameworks).
        var anchors = uiPIDs
        for pid in uiPIDs {
            guard let app = byPID[pid],
                  let ownerPID = tree.owner(of: pid, anchors: uiPIDs.subtracting([pid])),
                  let owner = byPID[ownerPID],
                  ProcessPolicy.isHelper(executablePath: app.executableURL?.path, ofBundleAt: owner.bundleURL?.path)
            else { continue }
            anchors.remove(pid)
        }

        // 3. Fold helpers: everything that descends from an anchor (stopping at other anchors)
        //    is accounted to that anchor and hidden as a separate row.
        var helpersByAnchor: [pid_t: [pid_t]] = [:]
        var foldedPIDs: Set<pid_t> = []
        for anchor in anchors {
            let helpers = tree.descendants(of: anchor, stoppingAt: anchors)
            if !helpers.isEmpty {
                helpersByAnchor[anchor] = helpers
                foldedPIDs.formUnion(helpers)
            }
        }

        var groups: [String: [NSRunningApplication]] = [:]
        for app in candidates where !foldedPIDs.contains(app.processIdentifier) {
            groups[Self.key(for: app), default: []].append(app)
        }

        // 4. Build rows.
        var listed: [ListedApp] = []
        listed.reserveCapacity(groups.count)
        var seenPIDs = Set<pid_t>()
        var seenKeys = Set<String>()

        for (key, instances) in groups {
            let representative = instances.max { Self.rank($0) < Self.rank($1) } ?? instances[0]
            let bundleID = representative.bundleIdentifier
            let isBackground = instances.allSatisfy { $0.activationPolicy != .regular }

            var cpu = 0.0
            var cpuKnown = true
            var memory: UInt64 = 0
            var pids: [pid_t] = []
            var helperPIDs: [pid_t] = []
            for instance in instances {
                let pid = instance.processIdentifier
                pids.append(pid)
                if let helpers = helpersByAnchor[pid] {
                    helperPIDs.append(contentsOf: helpers)
                }
            }
            for pid in pids {
                seenPIDs.insert(pid)
                let sample = metrics.sample(pid: pid)
                if let value = sample.cpuPercent { cpu += value } else { cpuKnown = false }
                memory += sample.memoryBytes
            }
            for pid in helperPIDs {
                seenPIDs.insert(pid)
                let sample = metrics.sample(pid: pid)
                // Helpers come and go; an unknown helper CPU should not blank the whole row.
                cpu += sample.cpuPercent ?? 0
                memory += sample.memoryBytes
            }

            if lastUsed[key] == nil {
                lastUsed[key] = now
            }
            seenKeys.insert(key)
            icons.store(representative.icon, for: key)

            listed.append(
                ListedApp(
                    key: key,
                    name: representative.localizedName ?? bundleID ?? "PID \(representative.processIdentifier)",
                    bundleID: bundleID,
                    bundleURL: representative.bundleURL,
                    pids: pids,
                    helperPIDs: helperPIDs,
                    isBackground: isBackground,
                    isMusic: ProtectedApps.musicBundleIDs.contains(bundleID ?? ""),
                    cpuPercent: cpuKnown ? cpu : nil,
                    memoryBytes: memory,
                    lastUsed: lastUsed[key] ?? now,
                    isFrontmost: pids.contains(where: { $0 == frontmostPID }),
                    hasVisibleWindows: pids.contains(where: windowOwners.contains)
                        || helperPIDs.contains(where: windowOwners.contains)
                )
            )
        }

        metrics.prune(keeping: seenPIDs)
        icons.prune(keeping: seenKeys)
        lastUsed = lastUsed.filter { seenKeys.contains($0.key) }
        return listed
    }

    func runningApplications(for listed: ListedApp) -> [NSRunningApplication] {
        listed.pids.compactMap { NSRunningApplication(processIdentifier: $0) }
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
