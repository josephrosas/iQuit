import AppKit
import SwiftUI

@MainActor
final class AboutWindowController: NSObject, NSWindowDelegate {
    static let shared = AboutWindowController()

    private var window: NSWindow?

    var isVisible: Bool { window?.isVisible == true }

    func show() {
        if window == nil {
            let root = AboutView()
                .environment(AppRuntime.model)
                .tint(iQuitTheme.accent)

            let hosting = NSHostingController(rootView: root)
            let window = NSWindow(contentViewController: hosting)
            window.title = "About iQuit"
            window.styleMask = [.titled, .closable]
            window.setContentSize(NSSize(width: 420, height: 320))
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
