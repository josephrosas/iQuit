import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var localMonitor: Any?
    private var globalMonitor: Any?

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.image = MenuBarIcon.image()
            button.imageScaling = .scaleProportionallyDown
            button.imagePosition = .imageOnly
            button.toolTip = "iQuit"
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
            button.action = #selector(handleClick(_:))
            button.setAccessibilityLabel("iQuit")
        }

        let root = PopoverView()
            .environment(model)
            .tint(iQuitTheme.accent)
            .preferredColorScheme(model.appearance.colorScheme)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: 340, height: 460)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self
    }

    func togglePopover() {
        guard let button = statusItem.button else { return }
        if popover.isShown {
            popover.performClose(nil)
        } else {
            model.syncOptionKey()
            model.refreshApps()
            popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
            popover.contentViewController?.view.window?.makeKey()
        }
    }

    func popoverWillShow(_ notification: Notification) {
        model.startLiveRefresh()
        startOptionMonitors()
    }

    func popoverDidClose(_ notification: Notification) {
        model.stopLiveRefresh()
        stopOptionMonitors()
        model.setOptionHeld(false)
    }

    @objc private func handleClick(_ sender: NSStatusBarButton) {
        if NSApp.currentEvent?.type == .rightMouseUp {
            showStatusMenu(sender)
            return
        }
        togglePopover()
    }

    private func showStatusMenu(_ sender: NSStatusBarButton) {
        let menu = NSMenu()
        menu.addItem(withTitle: "Preferences…", action: #selector(openSettings), keyEquivalent: ",")
        menu.addItem(withTitle: "About iQuit", action: #selector(openAbout), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Send Feedback…", action: #selector(openFeedback), keyEquivalent: "")
        menu.addItem(NSMenuItem.separator())
        menu.addItem(withTitle: "Quit iQuit", action: #selector(quitApp), keyEquivalent: "q")
        for item in menu.items {
            item.target = self
        }
        statusItem.menu = menu
        statusItem.button?.performClick(nil)
        statusItem.menu = nil
        sender.target = self
        sender.action = #selector(handleClick(_:))
    }

    @objc private func openSettings() {
        SettingsWindowController.shared.show()
    }

    @objc private func openAbout() {
        AboutWindowController.shared.show()
    }

    @objc private func openFeedback() {
        NSWorkspace.shared.open(AppIdentity.feedback)
    }

    @objc private func quitApp() {
        NSApp.terminate(nil)
    }

    private func startOptionMonitors() {
        stopOptionMonitors()
        localMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.model.setOptionHeld(event.modifierFlags.contains(.option))
            return event
        }
        globalMonitor = NSEvent.addGlobalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.model.setOptionHeld(event.modifierFlags.contains(.option))
        }
    }

    private func stopOptionMonitors() {
        if let localMonitor {
            NSEvent.removeMonitor(localMonitor)
            self.localMonitor = nil
        }
        if let globalMonitor {
            NSEvent.removeMonitor(globalMonitor)
            self.globalMonitor = nil
        }
    }
}
