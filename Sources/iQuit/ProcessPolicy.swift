import AppKit
import Foundation

/// Pure rules for which processes are listed, protected, excluded, or stale.
enum ProcessPolicy {
    /// Protected apps are never listed or quit.
    static func isProtected(bundleID: String?, localizedName: String?) -> Bool {
        if let bundleID, ProtectedApps.bundleIDs.contains(bundleID) { return true }
        return localizedName == "Finder"
    }

    private static let systemExecutablePrefixes = ["/System/", "/usr/", "/Library/Apple/", "/sbin/", "/bin/"]

    /// Whether a process from `runningApplications` is a candidate for the list at all.
    /// Regular apps are always listed. Accessory (menu bar) and prohibited (UI-less) processes
    /// are listed only when they are third-party: Apple agents, daemons, XPC services and
    /// widgets are hidden so "Quit All" with background apps shown cannot touch them.
    static func shouldList(
        bundleID: String?,
        localizedName: String?,
        policy: NSApplication.ActivationPolicy,
        executablePath: String? = nil
    ) -> Bool {
        if isProtected(bundleID: bundleID, localizedName: localizedName) { return false }
        switch policy {
        case .regular:
            return true
        case .accessory, .prohibited:
            if let bundleID, bundleID.hasPrefix("com.apple.") { return false }
            if let executablePath, systemExecutablePrefixes.contains(where: executablePath.hasPrefix) { return false }
            if policy == .prohibited {
                guard let bundleID, !bundleID.isEmpty else { return false }
            }
            return true
        @unknown default:
            return false
        }
    }

    /// A UI-policy process is a helper of an ancestor app when its executable lives inside
    /// that app's bundle (Electron/Chromium helpers are `LSUIElement` apps nested in the parent).
    static func isHelper(executablePath: String?, ofBundleAt bundlePath: String?) -> Bool {
        guard let executablePath, let bundlePath, !bundlePath.isEmpty else { return false }
        let prefix = bundlePath.hasSuffix("/") ? bundlePath : bundlePath + "/"
        return executablePath.hasPrefix(prefix)
    }

    static func isExcluded(_ app: ListedApp, neverQuit: Set<String>, neverQuitMusic: Bool) -> Bool {
        if let bundleID = app.bundleID, neverQuit.contains(bundleID) { return true }
        if neverQuitMusic, app.isMusic { return true }
        return false
    }

    static func matches(_ app: ListedApp, query: String) -> Bool {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        if trimmed.isEmpty { return true }
        if app.name.localizedCaseInsensitiveContains(trimmed) { return true }
        if let bundleID = app.bundleID, bundleID.localizedCaseInsensitiveContains(trimmed) { return true }
        return false
    }

    /// Matching for `--quit <name>` / `iquit://quit?name=`: exact name, bundle ID, then unique prefix.
    static func commandTargets(_ apps: [ListedApp], name: String) -> [ListedApp] {
        let exact = apps.filter { $0.name.localizedCaseInsensitiveCompare(name) == .orderedSame }
        if !exact.isEmpty { return exact }
        let byBundle = apps.filter { $0.bundleID?.caseInsensitiveCompare(name) == .orderedSame }
        if !byBundle.isEmpty { return byBundle }
        let prefixed = apps.filter { $0.name.lowercased().hasPrefix(name.lowercased()) }
        return prefixed.count == 1 ? prefixed : []
    }
}

struct AutoQuitPolicy: Equatable {
    var duration: TimeInterval
    var skipVisibleWindows: Bool
    var neverQuit: Set<String>
    var neverQuitMusic: Bool

    /// Apps the policy may ever quit: regular, not frontmost, not excluded, not showing windows (if enabled).
    func isCandidate(_ app: ListedApp) -> Bool {
        if app.isBackground || app.isFrontmost { return false }
        if ProcessPolicy.isExcluded(app, neverQuit: neverQuit, neverQuitMusic: neverQuitMusic) { return false }
        if skipVisibleWindows, app.hasVisibleWindows { return false }
        return true
    }

    /// Seconds until the app would be auto-quit, or nil if it is not a candidate.
    func remaining(for app: ListedApp, now: Date) -> TimeInterval? {
        guard isCandidate(app) else { return nil }
        return max(0, duration - now.timeIntervalSince(app.lastUsed))
    }

    /// Whether to send a quit request now. `lastAttempt` is the previous time this app was asked and
    /// refused (for example because it showed a save dialog); we back off for a full duration.
    func shouldQuit(_ app: ListedApp, now: Date, lastAttempt: Date?) -> Bool {
        guard let remaining = remaining(for: app, now: now), remaining <= 0 else { return false }
        if let lastAttempt, now.timeIntervalSince(lastAttempt) < duration { return false }
        return true
    }
}
