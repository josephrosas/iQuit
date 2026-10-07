import AppKit
import AudioToolbox

@MainActor
final class QuitService {
    @discardableResult
    func quit(
        _ apps: [NSRunningApplication],
        force: Bool,
        playSound: Bool
    ) -> Int {
        var count = 0
        for app in apps {
            guard canQuit(app) else { continue }
            let ok = force ? app.forceTerminate() : app.terminate()
            if ok {
                count += 1
            }
        }
        if playSound, count > 0 {
            AudioServicesPlaySystemSound(1057)
        }
        return count
    }

    func canQuit(_ app: NSRunningApplication) -> Bool {
        if app.processIdentifier == ProcessInfo.processInfo.processIdentifier {
            return false
        }
        if let bundleID = app.bundleIdentifier, ProtectedApps.bundleIDs.contains(bundleID) {
            return false
        }
        return true
    }

    func isExcluded(
        _ listed: ListedApp,
        neverQuit: Set<String>,
        neverQuitMusic: Bool
    ) -> Bool {
        if listed.isProtected { return true }
        if let bundleID = listed.bundleID, neverQuit.contains(bundleID) { return true }
        if neverQuitMusic, listed.isMusic { return true }
        return false
    }
}
