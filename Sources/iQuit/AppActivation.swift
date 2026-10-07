import AppKit

@MainActor
enum AppActivation {
    static func reveal() {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    static func hideIfNoWindows() {
        DispatchQueue.main.async {
            let settingsOpen = SettingsWindowController.shared.isVisible
            let aboutOpen = AboutWindowController.shared.isVisible
            if !settingsOpen && !aboutOpen {
                NSApp.setActivationPolicy(.accessory)
            }
        }
    }
}
