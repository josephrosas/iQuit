import AppKit
import Foundation
import ServiceManagement

enum SelectAllState {
    case none
    case some
    case all
}

enum QuitSource {
    case manual
    case auto
}

enum QuitState: Equatable {
    case quitting
    case stuck
}

struct PendingQuit {
    let name: String
    let bundleURL: URL?
    let startedAt: Date
    let force: Bool
    let relaunch: Bool
    let source: QuitSource
}

/// A group of apps that finished quitting close together; shown as a "Reopen" toast.
struct QuitBatch: Equatable {
    var names: [String]
    var bundleURLs: [URL]
    var completedAt: Date

    var title: String {
        let noun = names.count == 1 ? "app" : "apps"
        return "Quit \(names.count) \(noun)"
    }
}

@Observable
@MainActor
final class AppModel {
    // MARK: Live state

    var apps: [ListedApp] = [] {
        didSet { recomputeDerived() }
    }

    var selectedKeys: Set<String> = [] {
        didSet { if selectedKeys != oldValue { recomputeDerived() } }
    }

    var searchText = "" {
        didSet {
            guard searchText != oldValue else { return }
            recomputeDerived()
            focusedKey = searchText.isEmpty ? nil : shownApps.first?.id
        }
    }

    var optionHeld = false
    var loginItemError: String?
    var confirmingQuitAll = false
    /// Keyboard cursor in the popover list.
    var focusedKey: String?
    /// Row under the mouse. Rows receive this as a plain Bool so only two rows re-render per change.
    private(set) var hoveredKey: String?
    /// Time of the last snapshot; used as "now" for countdowns so rows stay stable between ticks.
    private(set) var lastRefresh = Date()
    /// Bumped each time the popover opens so views can reset focus.
    private(set) var popoverGeneration = 0
    private(set) var isPopoverOpen = false

    // Derived, recomputed once per change instead of on every view access.
    private(set) var regularApps: [ListedApp] = []
    private(set) var backgroundApps: [ListedApp] = []
    private(set) var shownApps: [ListedApp] = []
    private(set) var shownQuitableApps: [ListedApp] = []
    private(set) var quitableApps: [ListedApp] = []
    private(set) var selectedApps: [ListedApp] = []
    private(set) var selectAllState: SelectAllState = .none
    private(set) var regularQuitableCount = 0

    // Quit lifecycle.
    private(set) var pendingQuits: [String: PendingQuit] = [:]
    private(set) var stuckKeys: Set<String> = []
    private(set) var recentBatch: QuitBatch?
    private var autoQuitAttempts: [String: Date] = [:]
    private var pendingAutoNames: [String] = []
    private var pendingAutoURLs: [URL] = []
    private var autoNotifyTask: Task<Void, Never>?

    static let stuckAfter: TimeInterval = 8
    static let pendingExpiry: TimeInterval = 90
    static let batchMergeWindow: TimeInterval = 30

    /// Set by the status item controller so Escape can close the popover.
    var onRequestClose: (() -> Void)?

    // MARK: Preferences

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
            recomputeDerived()
        }
    }

    var autoQuitEnabled: Bool {
        didSet {
            UserDefaults.standard.set(autoQuitEnabled, forKey: AppDefaults.autoQuitEnabled)
            syncAutoQuitTimer()
            if autoQuitEnabled, notifyOnAutoQuit {
                notifier.requestAuthorization()
            }
        }
    }

    var autoQuitDuration: AutoQuitDuration {
        didSet { UserDefaults.standard.set(autoQuitDuration.rawValue, forKey: AppDefaults.autoQuitMinutes) }
    }

    var autoQuitSkipVisibleWindows: Bool {
        didSet { UserDefaults.standard.set(autoQuitSkipVisibleWindows, forKey: AppDefaults.autoQuitSkipVisibleWindows) }
    }

    var notifyOnAutoQuit: Bool {
        didSet {
            UserDefaults.standard.set(notifyOnAutoQuit, forKey: AppDefaults.notifyOnAutoQuit)
            if notifyOnAutoQuit, autoQuitEnabled {
                notifier.requestAuthorization()
            }
        }
    }

    var neverQuitMusic: Bool {
        didSet {
            UserDefaults.standard.set(neverQuitMusic, forKey: AppDefaults.neverQuitMusic)
            recomputeDerived()
        }
    }

    var neverQuitBundleIDs: Set<String> {
        didSet {
            UserDefaults.standard.set(Array(neverQuitBundleIDs).sorted(), forKey: AppDefaults.neverQuitBundleIDs)
            recomputeDerived()
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
        didSet {
            UserDefaults.standard.set(sort.rawValue, forKey: AppDefaults.sort)
            recomputeDerived()
        }
    }

    var menuBarIconStyle: MenuBarIconStyle {
        didSet { UserDefaults.standard.set(menuBarIconStyle.rawValue, forKey: AppDefaults.menuBarIconStyle) }
    }

    var showMenuBarCount: Bool {
        didSet {
            UserDefaults.standard.set(showMenuBarCount, forKey: AppDefaults.showMenuBarCount)
            if showMenuBarCount { refreshApps() }
        }
    }

    var versionText: String {
        let short = Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "1.0"
        let build = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    // MARK: Titles

    var forceMode: Bool { optionHeld }

    var quitAllTitle: String {
        forceMode ? "Force Quit All" : "Quit All"
    }

    var quitAllConfirmTitle: String {
        let count = shownQuitableApps.count
        let noun = count == 1 ? "app" : "apps"
        return forceMode ? "Force quit \(count) \(noun)?" : "Quit \(count) \(noun)?"
    }

    var quitSelectedTitle: String {
        let count = selectedApps.count
        if forceMode {
            return count == 1 ? "Force Quit Selected" : "Force Quit \(count)"
        }
        return count == 1 ? "Quit Selected" : "Quit \(count)"
    }

    var autoQuitPolicy: AutoQuitPolicy {
        AutoQuitPolicy(
            duration: autoQuitDuration.seconds,
            skipVisibleWindows: autoQuitSkipVisibleWindows,
            neverQuit: neverQuitBundleIDs,
            neverQuitMusic: neverQuitMusic
        )
    }

    // MARK: Services

    private let running = RunningAppsService()
    private let quitter = QuitService()
    private let autoQuit = AutoQuitService()
    private let hotkeyMonitor = HotkeyMonitor()
    private let notifier = AutoQuitNotifier()
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
        let storedMinutes = defaults.integer(forKey: AppDefaults.autoQuitMinutes)
        autoQuitDuration = AutoQuitDuration.fromStorage(storedMinutes == 0 ? 15 : storedMinutes)
        autoQuitSkipVisibleWindows = AppDefaults.bool(forKey: AppDefaults.autoQuitSkipVisibleWindows, default: true)
        notifyOnAutoQuit = AppDefaults.bool(forKey: AppDefaults.notifyOnAutoQuit, default: true)
        neverQuitMusic = defaults.bool(forKey: AppDefaults.neverQuitMusic)
        neverQuitBundleIDs = Set(defaults.stringArray(forKey: AppDefaults.neverQuitBundleIDs) ?? [])
        quitAllHotkey = Self.loadHotkey(keyCode: AppDefaults.quitAllKeyCode, modifiers: AppDefaults.quitAllModifiers)
        forceQuitAllHotkey = Self.loadHotkey(keyCode: AppDefaults.forceQuitAllKeyCode, modifiers: AppDefaults.forceQuitAllModifiers)
        sort = AppSort.fromStorage(defaults.string(forKey: AppDefaults.sort))
        menuBarIconStyle = MenuBarIconStyle.fromStorage(defaults.string(forKey: AppDefaults.menuBarIconStyle))
        showMenuBarCount = defaults.bool(forKey: AppDefaults.showMenuBarCount)
    }

    func start() {
        applyAppearance()
        running.onActivate = { [weak self] key in
            self?.appActivated(key)
        }
        running.onRunningAppsChanged = { [weak self] in
            guard let self, self.showMenuBarCount || self.isPopoverOpen || !self.pendingQuits.isEmpty else { return }
            self.refreshApps()
        }
        running.start()
        autoQuit.onTick = { [weak self] in
            self?.performAutoQuit()
        }
        syncAutoQuitTimer()
        hotkeyMonitor.onQuitAll = { [weak self] in
            self?.quitAll(force: false)
        }
        hotkeyMonitor.onForceQuitAll = { [weak self] in
            self?.quitAll(force: true)
        }
        registerHotkeys()
        notifier.onReopen = { [weak self] urls in
            self?.quitter.reopen(urls)
        }
        notifier.configure()
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
        autoNotifyTask?.cancel()
    }

    // MARK: Popover lifecycle

    func startLiveRefresh() {
        refreshTimer?.invalidate()
        isPopoverOpen = true
        popoverGeneration += 1
        refreshApps()
        let timer = Timer(timeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                self?.syncOptionKey()
                self?.refreshApps()
            }
        }
        timer.tolerance = 0.2
        RunLoop.main.add(timer, forMode: .common)
        refreshTimer = timer
        // A second quick sample gives CPU values for processes with no baseline yet.
        scheduleRefresh(after: 0.4)
    }

    func stopLiveRefresh() {
        refreshTimer?.invalidate()
        refreshTimer = nil
        isPopoverOpen = false
        searchText = ""
        confirmingQuitAll = false
        focusedKey = nil
        hoveredKey = nil
        recentBatch = nil
    }

    private func scheduleRefresh(after delay: TimeInterval) {
        DispatchQueue.main.asyncAfter(deadline: .now() + delay) { [weak self] in
            self?.refreshApps()
        }
    }

    // MARK: Derived state

    private func recomputeDerived() {
        let visible = apps.filter { showBackgroundApps || !$0.isBackground }
        let matching = visible.filter { ProcessPolicy.matches($0, query: searchText) }
        regularApps = sort.sorted(matching.filter { !$0.isBackground })
        backgroundApps = sort.sorted(matching.filter(\.isBackground))
        shownApps = regularApps + backgroundApps
        shownQuitableApps = shownApps.filter { !isExcluded($0) }
        quitableApps = visible.filter { !isExcluded($0) }
        selectedApps = quitableApps.filter { selectedKeys.contains($0.id) }
        regularQuitableCount = apps.filter { !$0.isBackground && !isExcluded($0) }.count

        let ids = Set(shownQuitableApps.map(\.id))
        if ids.isEmpty {
            selectAllState = .none
        } else {
            let selected = ids.intersection(selectedKeys)
            selectAllState = selected.isEmpty ? .none : (selected.count == ids.count ? .all : .some)
        }

        if let focusedKey, !shownApps.contains(where: { $0.id == focusedKey }) {
            self.focusedKey = nil
        }
    }

    func icon(for app: ListedApp) -> NSImage? {
        running.icons.icon(for: app.key)
    }

    func isExcluded(_ app: ListedApp) -> Bool {
        ProcessPolicy.isExcluded(app, neverQuit: neverQuitBundleIDs, neverQuitMusic: neverQuitMusic)
    }

    func exclusionLabel(for app: ListedApp) -> String? {
        if let bundleID = app.bundleID, neverQuitBundleIDs.contains(bundleID) { return "Never quit" }
        if app.isMusic, neverQuitMusic { return "Music app" }
        return nil
    }

    func quitState(for app: ListedApp) -> QuitState? {
        guard pendingQuits[app.key] != nil else { return nil }
        return stuckKeys.contains(app.key) ? .stuck : .quitting
    }

    /// Seconds until Auto Quit would close this app, or nil when it does not apply.
    func autoQuitRemaining(for app: ListedApp, now: Date = Date()) -> TimeInterval? {
        guard autoQuitEnabled else { return nil }
        return autoQuitPolicy.remaining(for: app, now: now)
    }

    // MARK: Selection and focus

    func toggleSelectAll() {
        let ids = Set(shownQuitableApps.map(\.id))
        guard !ids.isEmpty else { return }
        if selectAllState == .all {
            selectedKeys.subtract(ids)
        } else {
            selectedKeys.formUnion(ids)
        }
    }

    func toggleSelected(_ app: ListedApp) {
        guard !isExcluded(app) else { return }
        if selectedKeys.contains(app.id) {
            selectedKeys.remove(app.id)
        } else {
            selectedKeys.insert(app.id)
        }
    }

    func setHovered(_ id: String, hovering: Bool) {
        if hovering {
            if hoveredKey != id { hoveredKey = id }
        } else if hoveredKey == id {
            hoveredKey = nil
        }
    }

    var focusedApp: ListedApp? {
        guard let focusedKey else { return nil }
        return shownApps.first { $0.id == focusedKey }
    }

    func moveFocus(by delta: Int) {
        guard !shownApps.isEmpty else { return }
        guard let focusedKey, let index = shownApps.firstIndex(where: { $0.id == focusedKey }) else {
            self.focusedKey = delta >= 0 ? shownApps.first?.id : shownApps.last?.id
            return
        }
        let next = min(max(index + delta, 0), shownApps.count - 1)
        self.focusedKey = shownApps[next].id
    }

    /// Returns true when the key event was consumed.
    func handleKey(_ event: NSEvent) -> Bool {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        let command = flags.contains(.command)
        let chars = event.charactersIgnoringModifiers?.lowercased() ?? ""

        switch event.keyCode {
        case 125: // down
            moveFocus(by: 1)
            return true
        case 126: // up
            moveFocus(by: -1)
            return true
        case 36, 76: // return, keypad enter
            if confirmingQuitAll {
                confirmQuitAll()
                return true
            }
            if let app = focusedApp, !isExcluded(app) {
                quit(app)
                return true
            }
            return false
        case 53: // escape
            if confirmingQuitAll {
                cancelQuitAllConfirmation()
            } else if !searchText.isEmpty {
                searchText = ""
            } else {
                onRequestClose?()
            }
            return true
        case 49 where searchText.isEmpty: // space
            guard let app = focusedApp else { return false }
            toggleSelected(app)
            return true
        case 51 where command: // ⌘⌫
            if !selectedApps.isEmpty {
                quitSelected()
            } else if let app = focusedApp {
                quit(app)
            }
            return true
        default:
            if command, chars == "a" {
                toggleSelectAll()
                return true
            }
            return false
        }
    }

    // MARK: Quit All confirmation

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

    // MARK: Refresh

    func refreshApps() {
        let frontmost = NSWorkspace.shared.frontmostApplication?.processIdentifier
        let snapshot = running.snapshot(frontmostPID: frontmost)
        lastRefresh = Date()
        apps = snapshot
        let keys = Set(snapshot.map(\.id))
        let keptSelection = selectedKeys.intersection(keys)
        if keptSelection != selectedKeys {
            selectedKeys = keptSelection
        }
        autoQuitAttempts = autoQuitAttempts.filter { keys.contains($0.key) }
        resolvePendingQuits(present: keys)
    }

    func syncOptionKey() {
        optionHeld = NSEvent.modifierFlags.contains(.option)
    }

    func setOptionHeld(_ held: Bool) {
        optionHeld = held
    }

    private func appActivated(_ key: String) {
        autoQuitAttempts.removeValue(forKey: key)
        // The user went back to an app we asked to quit; it is no longer "quitting".
        if pendingQuits[key] != nil {
            pendingQuits.removeValue(forKey: key)
            stuckKeys.remove(key)
        }
    }

    // MARK: Never Quit

    func toggleNeverQuit(_ app: ListedApp) {
        guard let bundleID = app.bundleID else { return }
        if neverQuitBundleIDs.contains(bundleID) {
            neverQuitBundleIDs.remove(bundleID)
        } else {
            neverQuitBundleIDs.insert(bundleID)
            selectedKeys.remove(app.id)
        }
    }

    func removeNeverQuit(_ bundleID: String) {
        neverQuitBundleIDs.remove(bundleID)
    }

    func neverQuitName(for bundleID: String) -> String {
        apps.first(where: { $0.bundleID == bundleID })?.name ?? bundleID
    }

    // MARK: Quitting

    func quit(_ app: ListedApp, force: Bool? = nil) {
        guard !isExcluded(app) else { return }
        quit(listed: [app], force: force ?? forceMode)
        selectedKeys.remove(app.id)
    }

    func forceQuit(_ app: ListedApp) {
        quit(app, force: true)
    }

    func quitSelected(force: Bool? = nil) {
        quit(listed: selectedApps, force: force ?? forceMode)
        selectedKeys.removeAll()
    }

    func quitAll(force: Bool? = nil) {
        quit(listed: quitableApps, force: force ?? forceMode)
        selectedKeys.removeAll()
    }

    func relaunch(_ app: ListedApp) {
        guard !isExcluded(app), app.bundleURL != nil else { return }
        quit(listed: [app], force: false, relaunch: true)
    }

    func revealInFinder(_ app: ListedApp) {
        guard let url = app.bundleURL else { return }
        quitter.revealInFinder(url)
    }

    func reopenRecentBatch() {
        guard let batch = recentBatch else { return }
        recentBatch = nil
        quitter.reopen(batch.bundleURLs)
    }

    func dismissRecentBatch() {
        recentBatch = nil
    }

    private func quit(listed: [ListedApp], force: Bool, relaunch: Bool = false, source: QuitSource = .manual) {
        guard !listed.isEmpty else { return }
        let now = Date()
        for app in listed {
            pendingQuits[app.key] = PendingQuit(
                name: app.name,
                bundleURL: app.bundleURL,
                startedAt: now,
                force: force,
                relaunch: relaunch,
                source: source
            )
            stuckKeys.remove(app.key)
        }
        let runningApps = listed.flatMap { running.runningApplications(for: $0) }
        quitter.quit(runningApps, force: force, playSound: playSound)
        scheduleRefresh(after: 0.35)
        scheduleRefresh(after: 2.0)
        scheduleRefresh(after: Self.stuckAfter + 0.3)
    }

    private func resolvePendingQuits(present: Set<String>) {
        guard !pendingQuits.isEmpty else {
            if !stuckKeys.isEmpty { stuckKeys = [] }
            return
        }
        let now = Date()
        var completed: [PendingQuit] = []
        var stuck: Set<String> = []

        for (key, pending) in pendingQuits {
            if !present.contains(key) {
                pendingQuits.removeValue(forKey: key)
                if pending.relaunch, let url = pending.bundleURL {
                    quitter.reopen([url])
                } else {
                    completed.append(pending)
                }
            } else if now.timeIntervalSince(pending.startedAt) > Self.pendingExpiry {
                pendingQuits.removeValue(forKey: key)
            } else if now.timeIntervalSince(pending.startedAt) > Self.stuckAfter {
                stuck.insert(key)
            }
        }

        if stuck != stuckKeys {
            stuckKeys = stuck
        }
        guard !completed.isEmpty else { return }

        let urls = completed.compactMap(\.bundleURL)
        let names = completed.map(\.name)
        if var batch = recentBatch, now.timeIntervalSince(batch.completedAt) < Self.batchMergeWindow {
            batch.names.append(contentsOf: names)
            batch.bundleURLs.append(contentsOf: urls)
            batch.completedAt = now
            recentBatch = batch
        } else {
            recentBatch = QuitBatch(names: names, bundleURLs: urls, completedAt: now)
        }

        let auto = completed.filter { $0.source == .auto }
        if !auto.isEmpty, notifyOnAutoQuit {
            pendingAutoNames.append(contentsOf: auto.map(\.name))
            pendingAutoURLs.append(contentsOf: auto.compactMap(\.bundleURL))
            autoNotifyTask?.cancel()
            autoNotifyTask = Task { [weak self] in
                try? await Task.sleep(for: .seconds(2))
                guard !Task.isCancelled, let self else { return }
                self.notifier.notify(names: self.pendingAutoNames, bundleURLs: self.pendingAutoURLs)
                self.pendingAutoNames.removeAll()
                self.pendingAutoURLs.removeAll()
            }
        }
    }

    // MARK: Commands (CLI, URL scheme, Shortcuts)

    func handleCommand(_ command: CLICommand) -> String {
        refreshApps()
        switch command {
        case .quitAll:
            let count = quitableApps.count
            quitAll(force: false)
            return "quit\t\(count)"
        case .quit(let name):
            let matches = ProcessPolicy.commandTargets(quitableApps, name: name)
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
        let visible = apps.filter { showBackgroundApps || !$0.isBackground }
        if visible.isEmpty {
            return "No running apps"
        }
        return sort.sorted(visible).map { app in
            let flag = isExcluded(app) ? " never-quit" : ""
            return "\(app.name)\t\(app.formattedCPU)\t\(app.formattedMemory)\(flag)"
        }.joined(separator: "\n")
    }

    // MARK: Auto Quit

    private func syncAutoQuitTimer() {
        if autoQuitEnabled {
            if !autoQuit.isRunning { autoQuit.start() }
        } else {
            autoQuit.stop()
        }
    }

    private func performAutoQuit() {
        guard autoQuitEnabled else { return }
        refreshApps()
        let now = Date()
        let policy = autoQuitPolicy
        let stale = apps.filter { app in
            pendingQuits[app.key] == nil
                && policy.shouldQuit(app, now: now, lastAttempt: autoQuitAttempts[app.key])
        }
        guard !stale.isEmpty else { return }
        for app in stale {
            autoQuitAttempts[app.key] = now
        }
        quit(listed: stale, force: false, source: .auto)
    }

    // MARK: Hotkeys, appearance, login item

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
