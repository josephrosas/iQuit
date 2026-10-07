import AppKit
import SwiftUI

enum AppRuntime {
    @MainActor
    static let model = AppModel()

    nonisolated(unsafe) static var pendingCommand: CLICommand?
}

@main
enum iQuitMain {
    static func main() {
        if CLI.handleIfNeeded() {
            return
        }
        iQuitApp.main()
    }
}

struct iQuitApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate

    var body: some Scene {
        Settings {
            SettingsView()
                .environment(AppRuntime.model)
                .tint(iQuitTheme.accent)
                .preferredColorScheme(AppRuntime.model.appearance.colorScheme)
        }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private var statusItem: StatusItemController?

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        BrandAppearance.applyAppIcon()

        if CLI.otherRunningInstance() != nil, AppRuntime.pendingCommand == nil {
            NSApp.terminate(nil)
            return
        }

        let model = AppRuntime.model
        statusItem = StatusItemController(model: model)
        model.start()

        DistributedNotificationCenter.default().addObserver(
            self,
            selector: #selector(handleDistributedCommand(_:)),
            name: AppIdentity.commandNotification,
            object: nil
        )

        if let pending = AppRuntime.pendingCommand {
            AppRuntime.pendingCommand = nil
            _ = model.handleCommand(pending)
        }
    }

    func application(_ application: NSApplication, open urls: [URL]) {
        for url in urls {
            if let command = URLCommand.parse(url) {
                _ = AppRuntime.model.handleCommand(command)
            }
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !flag {
            statusItem?.togglePopover()
        }
        return false
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        false
    }

    func applicationWillTerminate(_ notification: Notification) {
        AppRuntime.model.teardown()
    }

    @objc private func handleDistributedCommand(_ notification: Notification) {
        guard let raw = notification.object as? String else { return }
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        let nonce = parts.count == 2 ? String(parts[0]) : ""
        let encoded = parts.count == 2 ? String(parts[1]) : raw
        guard let command = CLICommand.decode(encoded) else { return }
        let reply = AppRuntime.model.handleCommand(command)
        IPC.writeReply(nonce, reply)
        DistributedNotificationCenter.default().postNotificationName(
            AppIdentity.replyNotification,
            object: IPC.encodeReply(nonce: nonce, text: reply),
            userInfo: nil,
            deliverImmediately: true
        )
    }
}
