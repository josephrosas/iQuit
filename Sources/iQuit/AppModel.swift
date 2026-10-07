import AppKit
import Foundation
import ServiceManagement

@Observable
@MainActor
final class AppModel {
    var apps: [ListedApp] = []
    var selectedKeys: Set<String> = []
    var optionHeld = false
    var loginItemError: String?
    var searchText = ""
    var confirmingQuitAll = false
    var hoveredKey: String?

    var appearance: AppearancePreference {
        didSet {
            UserDefaults.standard.set(appearance.rawValue, forKey: AppDefaults.appearance)
            applyAppearance()
        }
    }

    var launchAtLogin: Bool {
        didSet {
            guard !isSyncingLoginItem else { return }
            UserDefaults.standard.set(launchAtLogin, forKey: AppDefaults.launchAtLogin)
            updateLoginItem()
        }
    }

    var playSound: Bool {
        didSet { UserDefaults.standard.set(playSound, forKey: AppDefaults.playSound) }
    }

    var showMetrics: Bool {
        didSet { UserDefaults.standard.set(showMetrics, forKey: AppDefaults.showMetrics) }
    }

    var showBackgroundApps: Bool {
        didSet {
            UserDefaults.standard.set(showBackgroundApps, forKey: AppDefaults.showBackgroundApps)
            refreshApps()
        }
    }

    var autoQuitEnabled: Bool {
        didSet { UserDefaults.standard.set(autoQuitEnabled, forKey: AppDefaults.autoQuitEnabled) }
    }

    var autoQuitDuration: AutoQuitDuration {
        didSet { UserDefaults.standard.set(autoQuitDuration.rawValue, forKey: AppDefaults.autoQuitMinutes) }
    }

    var neverQuitMusic: Bool {
        didSet { UserDefaults.standard.set(neverQuitMusic, forKey: AppDefaults.neverQuitMusic) }
    }

    var neverQuitBundleIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(neverQuitBundleIDs).sorted(), forKey: AppDefaults.neverQuitBundleIDs)
        }
    }

    var quitAllHotkey: SavedHotkey? {
        didSet {
            persist(hotkey: quitAllHotkey, keyCode: AppDefaults.quitAllKeyCode, modifiers: AppDefaults.quitAllModifiers)
            registerHotkeys()
        }
    }

    var forceQuitAllHotkey: SavedHotkey? {
        didSet {
            persist(hotkey: forceQuitAllHotkey, keyCode: AppDefaults.forceQuitAllKeyCode, modifiers: AppDefaults.forceQuitAllModifiers)
            registerHotkeys()
        }
    }

    var sort: AppSort {
        didSet { UserDefaults.standard.set(sort.rawValue, forKey: AppDefaults.sort) }
    }

    var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var visibleApps: [ListedApp] {
        apps.filter { showBackgroundApps || !$0.isBackground }
    }

    var shownApps: [ListedApp] {
        let query = searchText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !query.isEmpty else { return visibleApps }
        return visibleApps.filter { $0.name.localizedCaseInsensitiveContains(query) }
    }

    var shownQuitableApps: [ListedApp] {
        shownApps.filter { !isExcluded($0) }
    }

    var quitableApps: [ListedApp] {
        visibleApps.filter { !isExcluded($0) }
    }

    var selectAllState: SelectAllState {
        let ids = Set(shownQuitableApps.map(\.id))
        guard !ids.isEmpty else { return .none }
        let selected = ids.intersection(selectedKeys)
        if selected.isEmpty { return .none }
        if selected.count == ids.count { return .all }
        return .some
    }

    var quitAllConfirmTitle: String {
        let count = shownQuitableApps.count
        let noun = count == 1 ? "app" : "apps"
        if forceMode {
            return "Force quit \(count) \(noun)?"
        }
        return "Quit \(count) \(noun)?"
    }

    var selectedApps: [ListedApp] {
        visibleApps.filter { selectedKeys.contains($0.id) && !isExcluded($0) }
    }

    var forceMode: Bool { optionHeld }

    var quitAllTitle: String {
        forceMode ? "Force Quit All" : "Quit All"
    }

    var quitSelectedTitle: String {
        let count = selectedApps.count
        if forceMode {
            return count == 1 ? "Force Quit Selected" : "Force Quit \(count)"
        }
        return count == 1 ? "Quit Selected" : "Quit \(count)"
    }

    private let running = RunningAppsService()
    private let quitter = QuitService()
    private let autoQuit = AutoQuitService()
    private let hotkeyMonitor = HotkeyMonitor()
    private var isSyncingLoginItem = false
    private var refreshTimer: Timer?

    init() {
        let defaults = UserDefaults.standard
        appearance = AppearancePreference(rawValue: defaults.string(forKey: AppDefaults.appearance) ?? "") ?? .matchMac
        launchAtLogin = defaults.bool(forKey: AppDefaults.launchAtLogin)
        playSound = AppDefaults.bool(forKey: AppDefaults.playSound, default: true)
        showMetrics = AppDefaults.bool(forKey: AppDefaults.showMetrics, default: true)
        showBackgroundApps = defaults.bool(forKey: AppDefaults.showBackgroundApps)
        autoQuitEnabled = defaults.bool(forKey: AppDefaults.autoQuitEnabled)
        autoQuitDuration = AutoQuitDuration.fromStorage(defaults.integer(forKey: AppDefaults.autoQuitMinutes) == 0 ? 15 : defaults.integer(forKey: AppDefaults.autoQuitMinutes))
        neverQuitMusic = defaults.bool(forKey: AppDefaults.neverQuitMusic)
        neverQuitBundleIDs = Set(defaults.stringArray(forKey: AppDefaults.neverQuitBundleIDs) ?? [])
        quitAllHotkey = Self.loadHotkey(keyCode: AppDefaults.quitAllKeyCode, modifiers: AppDefaults.quitAllModifiers)
        forceQuitAllHotkey = Self.loadHotkey(keyCode: AppDefaults.forceQuitAllKeyCode, modifiers: AppDefaults.forceQuitAllModifiers)
        sort = AppSort.fromStorage(defaults.string(forKey: AppDefaults.sort))
    }

    func start() {
        applyAppearance()
        running.start()
        autoQuit.onTick = { [weak self] in
            self?.performAutoQuit()
        }
        autoQuit.start()
        hotkeyMonitor.onQuitAll = { [weak self] in
            self?.quitAll(force: false)
        }
        hotkeyMonitor.onForceQuitAll = { [weak self] in
            self?.quitAll(force: true)
        }
        registerHotkeys()
        if UserDefaults.standard.object(forKey: AppDefaults.launchAtLogin) == nil {
            UserDefaults.standard.set(launchAtLogin, forKey: AppDefaults.launchAtLogin)
        }
        updateLoginItem()
        refreshApps()
    }

    func teardown() {
        running.stop()
        autoQuit.stop()
        hotkeyMonitor.unregister()
        refreshTimer?.invalidate()
        refreshTimer = nil
    }

    func startLiveRefresh() {
        refreshTimer?.invalidate()
        running.discardCPUBaseline()
        refreshApps()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncOptionKey()
                self?.refreshApps()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            guard let self, self.refreshTimer != nil else { return }
            self.refreshApps()
        }
    }

    func stopLiveRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        searchText = ""
        confirmingQuitAll = false
        hoveredKey = nil
    }

    func setHovered(_ id: String, hovering: Bool) {
        if hovering {
            hoveredKey = id
        } else if hoveredKey == id {
            hoveredKey = nil
        }
    }

    func sorted(_ apps: [ListedApp]) -> [ListedApp] {
        apps.sorted { lhs, rhs in
            switch sort {
            case .name:
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            case .cpu:
                switch (lhs.cpuPercent, rhs.cpuPercent) {
                case (nil, nil):
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                case (nil, _):
                    return false
                case (_, nil):
                    return true
                case let (left?, right?):
                    if left != right { return left > right }
                    return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
                }
            case .memory:
                if lhs.memoryBytes != rhs.memoryBytes { return lhs.memoryBytes > rhs.memoryBytes }
                return lhs.name.localizedCaseInsensitiveCompare(rhs.name) == .orderedAscending
            }
        }
    }

    func toggleSelectAll() {
        let ids = Set(shownQuitableApps.map(\.id))
        guard !ids.isEmpty else { return }
        if selectAllState == .all {
            selectedKeys.subtract(ids)
        } else {
            selectedKeys.formUnion(ids)
        }
    }

    func beginQuitAllConfirmation() {
        guard !shownQuitableApps.isEmpty else { return }
        confirmingQuitAll = true
    }

    func cancelQuitAllConfirmation() {
        confirmingQuitAll = false
    }

    func confirmQuitAll() {
        let targets = shownQuitableApps
        confirmingQuitAll = false
        quit(listed: targets, force: forceMode)
        selectedKeys.subtract(targets.map(\.id))
    }

    func refreshApps() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let snapshot = running.snapshot(showBackground: true, frontmostPID: frontmost)
        apps = snapshot
        selectedKeys = selectedKeys.intersection(Set(snapshot.map(\.id)))
    }

    func syncOptionKey() {
        optionHeld = NSEvent.modifierFlags.contains(.option)
    }

    func setOptionHeld(_ held: Bool) {
        optionHeld = held
    }

    func isExcluded(_ app: ListedApp) -> Bool {
        quitter.isExcluded(app, neverQuit: neverQuitBundleIDs, neverQuitMusic: neverQuitMusic)
    }

    func toggleNeverQuit(_ app: ListedApp) {
        guard let bundleID = app.bundleID else { return }
        if neverQuitBundleIDs.contains(bundleID) {
            neverQuitBundleIDs.remove(bundleID)
        } else {
            neverQuitBundleIDs.insert(bundleID)
        }
    }

    func removeNeverQuit(_ bundleID: String) {
        neverQuitBundleIDs.remove(bundleID)
    }

    func neverQuitName(for bundleID: String) -> String {
        apps.first(where: { $0.bundleID == bundleID })?.name ?? bundleID
    }

    func toggleSelected(_ app: ListedApp) {
        if selectedKeys.contains(app.id) {
            selectedKeys.remove(app.id)
        } else {
            selectedKeys.insert(app.id)
        }
    }

    func quit(_ app: ListedApp, force: Bool? = nil) {
        guard !isExcluded(app) else { return }
        _ = quitter.quit(running.runningApplications(for: app), force: force ?? forceMode, playSound: playSound)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshApps()
        }
    }

    func quitSelected(force: Bool? = nil) {
        quit(listed: selectedApps, force: force ?? forceMode)
        selectedKeys.removeAll()
    }

    func quitAll(force: Bool? = nil) {
        quit(listed: quitableApps, force: force ?? forceMode)
        selectedKeys.removeAll()
    }

    func handleCommand(_ command: CLICommand) -> String {
        refreshApps()
        switch command {
        case .quitAll:
            let count = quitableApps.count
            quitAll(force: false)
            return "quit\t\(count)"
        case .quit(let name):
            let matches = quitableApps.filter { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
            guard !matches.isEmpty else { return "missing\t\(name)" }
            quit(listed: matches, force: false)
            return "quit\t\(matches.count)\t\(name)"
        case .forceQuitAll:
            let count = quitableApps.count
            quitAll(force: true)
            return "force-quit\t\(count)"
        case .list:
            return listText()
        case .status:
            return statusLine()
        case .help:
            return CLI.usage
        }
    }

    func statusLine() -> String {
        refreshApps()
        let auto = autoQuitEnabled ? "auto-quit \(autoQuitDuration.title)" : "auto-quit off"
        return "apps\t\(quitableApps.count)\t\(auto)"
    }

    func listText() -> String {
        refreshApps()
        if visibleApps.isEmpty {
            return "No running apps"
        }
        return visibleApps.map { app in
            let flag = isExcluded(app) ? " never-quit" : ""
            return "\(app.name)\t\(app.formattedCPU)\t\(app.formattedMemory)\(flag)"
        }.joined(separator: "\n")
    }

    private func quit(listed: [ListedApp], force: Bool) {
        let runningApps = listed.flatMap { running.runningApplications(for: $0) }
        _ = quitter.quit(runningApps, force: force, playSound: playSound)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.35) { [weak self] in
            self?.refreshApps()
        }
    }

    private func performAutoQuit() {
        guard autoQuitEnabled else { return }
        refreshApps()
        let cutoff = Date().addingTimeInterval(-autoQuitDuration.seconds)
        let stale = apps.filter { app in
            !app.isBackground
                && !app.isFrontmost
                && !isExcluded(app)
                && app.lastUsed < cutoff
        }
        guard !stale.isEmpty else { return }
        quit(listed: stale, force: false)
    }

    private func registerHotkeys() {
        hotkeyMonitor.register(quitAll: quitAllHotkey, forceQuitAll: forceQuitAllHotkey)
    }

    private func persist(hotkey: SavedHotkey?, keyCode: String, modifiers: String) {
        if let hotkey {
            UserDefaults.standard.set(Int(hotkey.keyCode), forKey: keyCode)
            UserDefaults.standard.set(Int(hotkey.modifiers.rawValue), forKey: modifiers)
        } else {
            UserDefaults.standard.removeObject(forKey: keyCode)
            UserDefaults.standard.removeObject(forKey: modifiers)
        }
    }

    private static func loadHotkey(keyCode: String, modifiers: String) -> SavedHotkey? {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: keyCode) != nil else { return nil }
        return SavedHotkey(
            keyCode: UInt32(defaults.integer(forKey: keyCode)),
            modifiers: NSEvent.ModifierFlags(rawValue: UInt(defaults.integer(forKey: modifiers)))
        )
    }

    private func applyAppearance() {
        NSApp.appearance = appearance.nsAppearance
    }

    private func updateLoginItem() {
        do {
            if launchAtLogin {
                try SMAppService.mainApp.register()
            } else if SMAppService.mainApp.status == .enabled {
                try SMAppService.mainApp.unregister()
            }
            loginItemError = nil
        } catch {
            loginItemError = "Could not update login item: \(error.localizedDescription)"
            isSyncingLoginItem = true
            launchAtLogin = SMAppService.mainApp.status == .enabled
            isSyncingLoginItem = false
            UserDefaults.standard.set(launchAtLogin, forKey: AppDefaults.launchAtLogin)
        }
    }
}
