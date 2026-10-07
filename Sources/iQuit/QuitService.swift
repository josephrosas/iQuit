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
        return !ProcessPolicy.isProtected(bundleID: app.bundleIdentifier, localizedName: app.localizedName)
    }

    func reopen(_ urls: [URL]) {
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = false
        for url in urls {
            NSWorkspace.shared.openApplication(at: url, configuration: configuration)
        }
    }

    func revealInFinder(_ url: URL) {
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }
}
