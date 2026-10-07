import AppKit
import SwiftUI

@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
    static let shared = SettingsWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        if window == nil {
            let root = SettingsView()
                .environment(AppRuntime.model)
                .tint(iQuitTheme.accent)
                .preferredColorScheme(AppRuntime.model.appearance.colorScheme)

            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "iQuit Preferences"
            window.styleMask = [.titled, .closable, .miniaturizable]
            window.titlebarAppearsTransparent = false
            window.setContentSize(NSSize(width: 520, height: 720))
            window.minSize = NSSize(width: 480, height: 520)
            window.center()
            window.isReleasedWhenClosed = false
            window.delegate = self
            self.window = window
        }

        AppActivation.reveal()
        window?.makeKeyAndOrderFront(nil)
        window?.orderFrontRegardless()
    }

    func windowWillClose(_ notification: Notification) {
        AppActivation.hideIfNoWindows()
    }
}
