import AppKit
import Carbon
import Foundation
import Testing
@testable import iQuit

private func app(
    _ name: String,
    bundleID: String? = nil,
    cpu: Double? = nil,
    memory: UInt64 = 0,
    background: Bool = false,
    frontmost: Bool = false,
    lastUsed: Date = .distantPast,
    windows: Bool = false,
    music: Bool = false
) -> ListedApp {
    ListedApp(
        key: bundleID ?? "pid:\(name.hashValue)",
        name: name,
        bundleID: bundleID,
        bundleURL: nil,
        pids: [1],
        helperPIDs: [],
        isBackground: background,
        isMusic: music,
        cpuPercent: cpu,
        memoryBytes: memory,
        lastUsed: lastUsed,
        isFrontmost: frontmost,
        hasVisibleWindows: windows
    )
}

@Suite("Sorting")
struct SortTests {
    @Test("name sort is case-insensitive and numeric-aware")
    func byName() {
        let sorted = AppSort.name.sorted([app("zed"), app("Alpha"), app("beta"), app("App 10"), app("App 2")])
        #expect(sorted.map(\.name) == ["Alpha", "App 2", "App 10", "beta", "zed"])
    }

    @Test("cpu sort puts heaviest first and unknown last")
    func byCPU() {
        let sorted = AppSort.cpu.sorted([app("a", cpu: 1), app("b", cpu: nil), app("c", cpu: 50), app("d", cpu: 1)])
        #expect(sorted.map(\.name) == ["c", "a", "d", "b"])
    }

    @Test("memory sort descending with name tiebreak")
    func byMemory() {
        let sorted = AppSort.memory.sorted([app("b", memory: 10), app("a", memory: 10), app("c", memory: 99)])
        #expect(sorted.map(\.name) == ["c", "a", "b"])
    }
}

@Suite("Process policy")
struct PolicyTests {
    @Test("regular and accessory apps are listed")
    func listsUIApps() {
        #expect(ProcessPolicy.shouldList(bundleID: "com.example.App", localizedName: "App", policy: .regular))
        #expect(ProcessPolicy.shouldList(bundleID: nil, localizedName: "Tool", policy: .accessory))
    }

    @Test("Apple daemons, agents and bundle-less prohibited processes are hidden")
    func hidesSystemProcesses() {
        #expect(!ProcessPolicy.shouldList(bundleID: "com.apple.sharingd", localizedName: "sharingd", policy: .prohibited))
        #expect(!ProcessPolicy.shouldList(bundleID: nil, localizedName: "universalaccessd", policy: .prohibited))
        #expect(!ProcessPolicy.shouldList(bundleID: "", localizedName: "x", policy: .prohibited))
        #expect(ProcessPolicy.shouldList(bundleID: "com.nordvpn.helper", localizedName: "helper", policy: .prohibited))
        // Apple accessory agents live under /System and must not appear as quittable background apps.
        #expect(!ProcessPolicy.shouldList(bundleID: "com.apple.WindowManager", localizedName: "WindowManager", policy: .accessory))
        #expect(!ProcessPolicy.shouldList(
            bundleID: nil, localizedName: "coreautha", policy: .accessory,
            executablePath: "/System/Library/Frameworks/LocalAuthentication.framework/Support/coreautha.bundle/Contents/MacOS/coreautha"
        ))
        #expect(ProcessPolicy.shouldList(
            bundleID: "com.surteesstudios.Bartender", localizedName: "Bartender", policy: .accessory,
            executablePath: "/Applications/Bartender.app/Contents/MacOS/Bartender"
        ))
        // Apple's regular apps stay listed even though they live under /System.
        #expect(ProcessPolicy.shouldList(
            bundleID: "com.apple.Safari", localizedName: "Safari", policy: .regular,
            executablePath: "/System/Applications/Safari.app/Contents/MacOS/Safari"
        ))
    }

    @Test("helpers are UI processes whose executable is inside the owner's bundle")
    func helperDetection() {
        let cursor = "/Applications/Cursor.app"
        #expect(ProcessPolicy.isHelper(
            executablePath: "/Applications/Cursor.app/Contents/Frameworks/Cursor Helper (Plugin).app/Contents/MacOS/Cursor Helper (Plugin)",
            ofBundleAt: cursor
        ))
        #expect(!ProcessPolicy.isHelper(executablePath: "/Applications/TextEdit.app/Contents/MacOS/TextEdit", ofBundleAt: "/Applications/Utilities/Terminal.app"))
        #expect(!ProcessPolicy.isHelper(executablePath: "/Applications/Cursor.app/Contents/MacOS/Cursor", ofBundleAt: nil))
        #expect(!ProcessPolicy.isHelper(executablePath: "/Applications/Cursor.app2/x", ofBundleAt: cursor))
    }

    @Test("protected apps are never listed")
    func protectedApps() {
        #expect(!ProcessPolicy.shouldList(bundleID: "com.apple.finder", localizedName: "Finder", policy: .regular))
        #expect(!ProcessPolicy.shouldList(bundleID: "com.apple.dock", localizedName: "Dock", policy: .prohibited))
        #expect(!ProcessPolicy.shouldList(bundleID: nil, localizedName: "Finder", policy: .regular))
        #expect(ProcessPolicy.isProtected(bundleID: "com.unga.iQuit", localizedName: nil))
    }

    @Test("exclusions honour never-quit and music")
    func exclusions() {
        let music = app("Music", bundleID: "com.apple.Music", music: true)
        let other = app("Notes", bundleID: "com.apple.Notes")
        #expect(ProcessPolicy.isExcluded(music, neverQuit: [], neverQuitMusic: true))
        #expect(!ProcessPolicy.isExcluded(music, neverQuit: [], neverQuitMusic: false))
        #expect(ProcessPolicy.isExcluded(other, neverQuit: ["com.apple.Notes"], neverQuitMusic: false))
        #expect(!ProcessPolicy.isExcluded(other, neverQuit: [], neverQuitMusic: true))
    }

    @Test("search matches name or bundle id")
    func search() {
        let notes = app("Notes", bundleID: "com.apple.Notes")
        #expect(ProcessPolicy.matches(notes, query: ""))
        #expect(ProcessPolicy.matches(notes, query: "  not "))
        #expect(ProcessPolicy.matches(notes, query: "apple.no"))
        #expect(!ProcessPolicy.matches(notes, query: "safari"))
    }

    @Test("command targets: exact name, then bundle id, then unique prefix")
    func commandTargets() {
        let apps = [app("TextEdit", bundleID: "com.apple.TextEdit"), app("Terminal", bundleID: "com.apple.Terminal"), app("Tex", bundleID: "x.tex")]
        #expect(ProcessPolicy.commandTargets(apps, name: "textedit").map(\.name) == ["TextEdit"])
        #expect(ProcessPolicy.commandTargets(apps, name: "com.apple.terminal").map(\.name) == ["Terminal"])
        #expect(ProcessPolicy.commandTargets(apps, name: "Term").map(\.name) == ["Terminal"])
        #expect(ProcessPolicy.commandTargets(apps, name: "Te").isEmpty)
        #expect(ProcessPolicy.commandTargets(apps, name: "Nope").isEmpty)
    }
}

@Suite("Auto quit policy")
struct AutoQuitPolicyTests {
    let now = Date(timeIntervalSinceReferenceDate: 1_000_000)
    var policy: AutoQuitPolicy {
        AutoQuitPolicy(duration: 900, skipVisibleWindows: true, neverQuit: ["com.keep"], neverQuitMusic: true)
    }

    @Test("candidates exclude background, frontmost, excluded, and windowed apps")
    func candidates() {
        #expect(policy.isCandidate(app("a")))
        #expect(!policy.isCandidate(app("bg", background: true)))
        #expect(!policy.isCandidate(app("front", frontmost: true)))
        #expect(!policy.isCandidate(app("keep", bundleID: "com.keep")))
        #expect(!policy.isCandidate(app("music", music: true)))
        #expect(!policy.isCandidate(app("windowed", windows: true)))

        var lenient = policy
        lenient.skipVisibleWindows = false
        #expect(lenient.isCandidate(app("windowed", windows: true)))
    }

    @Test("remaining counts down from last use")
    func remaining() {
        let fresh = app("a", lastUsed: now.addingTimeInterval(-300))
        #expect(policy.remaining(for: fresh, now: now) == 600)
        let old = app("b", lastUsed: now.addingTimeInterval(-5000))
        #expect(policy.remaining(for: old, now: now) == 0)
        #expect(policy.remaining(for: app("bg", background: true), now: now) == nil)
    }

    @Test("stale apps quit once, then back off for a full duration")
    func backoff() {
        let stale = app("a", lastUsed: now.addingTimeInterval(-1000))
        #expect(policy.shouldQuit(stale, now: now, lastAttempt: nil))
        #expect(!policy.shouldQuit(stale, now: now, lastAttempt: now.addingTimeInterval(-20)))
        #expect(!policy.shouldQuit(stale, now: now, lastAttempt: now.addingTimeInterval(-899)))
        #expect(policy.shouldQuit(stale, now: now, lastAttempt: now.addingTimeInterval(-901)))
        let fresh = app("b", lastUsed: now.addingTimeInterval(-10))
        #expect(!policy.shouldQuit(fresh, now: now, lastAttempt: nil))
    }
}

@Suite("CPU metrics")
struct MetricsTests {
    @Test("first sample has no CPU, second sample derives percent from deltas")
    func cpuPercent() {
        let metrics = ProcessMetrics(clock: { 0 })
        let first = metrics.record(pid: 7, cpuNanos: 1_000_000_000, memoryBytes: 10, now: 10)
        #expect(first.cpuPercent == nil)
        #expect(first.memoryBytes == 10)
        // 0.5 s of CPU over 1 s of wall time → 50 %.
        let second = metrics.record(pid: 7, cpuNanos: 1_500_000_000, memoryBytes: 12, now: 11)
        #expect(second.cpuPercent == 50)
        #expect(second.memoryBytes == 12)
    }

    @Test("samples closer than the minimum interval reuse the previous percent")
    func tooSoon() {
        let metrics = ProcessMetrics(clock: { 0 })
        _ = metrics.record(pid: 1, cpuNanos: 0, memoryBytes: 1, now: 0)
        let second = metrics.record(pid: 1, cpuNanos: 2_000_000_000, memoryBytes: 1, now: 1)
        #expect(second.cpuPercent == 200)
        let third = metrics.record(pid: 1, cpuNanos: 9_000_000_000, memoryBytes: 1, now: 1.01)
        #expect(third.cpuPercent == 200)
    }

    @Test("multi-core processes can exceed 100 % and never go negative")
    func bounds() {
        let metrics = ProcessMetrics(clock: { 0 })
        _ = metrics.record(pid: 1, cpuNanos: 5_000_000_000, memoryBytes: 0, now: 0)
        let wrapped = metrics.record(pid: 1, cpuNanos: 4_000_000_000, memoryBytes: 0, now: 1)
        #expect(wrapped.cpuPercent == 0)
        _ = metrics.record(pid: 2, cpuNanos: 0, memoryBytes: 0, now: 0)
        let multi = metrics.record(pid: 2, cpuNanos: 4_000_000_000, memoryBytes: 0, now: 1)
        #expect(multi.cpuPercent == 400)
    }

    @Test("prune forgets unlisted pids")
    func prune() {
        let metrics = ProcessMetrics(clock: { 0 })
        _ = metrics.record(pid: 1, cpuNanos: 0, memoryBytes: 0, now: 0)
        metrics.prune(keeping: [])
        let again = metrics.record(pid: 1, cpuNanos: 1_000_000_000, memoryBytes: 0, now: 1)
        #expect(again.cpuPercent == nil)
    }
}

@Suite("Process tree")
struct ProcessTreeTests {
    // launchd(1) → Chrome(100) → helpers 101, 102 → 103 (grandchild)
    //           → Terminal(200) → zsh(201) → TextEdit(300, an app launched from the shell) → 301
    let tree = ProcessTree(parent: [
        100: 1, 101: 100, 102: 100, 103: 101,
        200: 1, 201: 200, 300: 201, 301: 300,
        400: 1
    ])

    @Test("descendants fold helpers but stop at other anchors")
    func descendants() {
        let anchors: Set<pid_t> = [100, 200, 300]
        #expect(Set(tree.descendants(of: 100, stoppingAt: anchors)) == [101, 102, 103])
        #expect(Set(tree.descendants(of: 200, stoppingAt: anchors)) == [201])
        #expect(Set(tree.descendants(of: 300, stoppingAt: anchors)) == [301])
        #expect(tree.descendants(of: 400, stoppingAt: anchors).isEmpty)
    }

    @Test("owner walks up to the nearest anchor")
    func owner() {
        let anchors: Set<pid_t> = [100, 200, 300]
        #expect(tree.owner(of: 103, anchors: anchors) == 100)
        #expect(tree.owner(of: 301, anchors: anchors) == 300)
        #expect(tree.owner(of: 201, anchors: anchors) == 200)
        #expect(tree.owner(of: 400, anchors: anchors) == nil)
    }

    @Test("cycles and self-parenting do not loop")
    func cycles() {
        let weird = ProcessTree(parent: [5: 5, 6: 7, 7: 6])
        #expect(weird.descendants(of: 6, stoppingAt: []) == [7])
        #expect(weird.owner(of: 6, anchors: [99]) == nil)
    }

    @Test("live tree includes this process with a parent")
    func live() {
        let live = ProcessTree.current()
        let me = ProcessInfo.processInfo.processIdentifier
        #expect(live.parent[me] != nil)
    }
}

@Suite("Hotkey display")
struct HotkeyTests {
    @Test("named keys and modifier order")
    func display() {
        let hotkey = SavedHotkey(keyCode: 49, modifiers: [.command, .shift, .option, .control])
        #expect(hotkey.displayString == "⌃⌥⇧⌘Space")
        #expect(SavedHotkey(keyCode: 36, modifiers: [.command]).displayString == "⌘↩")
        #expect(SavedHotkey(keyCode: 53, modifiers: [.option]).displayString == "⌥⎋")
    }

    @Test("carbon modifier bits")
    func carbon() {
        let hotkey = SavedHotkey(keyCode: 0, modifiers: [.command, .shift])
        #expect(hotkey.carbonModifiers == UInt32(cmdKey) | UInt32(shiftKey))
    }
}

@Suite("Row formatting")
struct FormattingTests {
    @Test("countdown text")
    func countdown() {
        #expect(AppRowView.countdownText(0) == "auto-quits now")
        #expect(AppRowView.countdownText(30) == "auto-quits in 30s")
        #expect(AppRowView.countdownText(61) == "auto-quits in 2m")
        #expect(AppRowView.countdownText(3600) == "auto-quits in 1h")
        #expect(AppRowView.countdownText(3660) == "auto-quits in 1h 1m")
    }

    @Test("cpu formatting")
    func cpu() {
        #expect(app("a", cpu: nil).formattedCPU == "—")
        #expect(app("a", cpu: 0.01).formattedCPU == "0%")
        #expect(app("a", cpu: 3.14).formattedCPU == "3.1%")
        #expect(app("a", cpu: 42.6).formattedCPU == "43%")
    }
}
