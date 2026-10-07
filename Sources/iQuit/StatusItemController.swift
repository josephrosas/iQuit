import AppKit
import SwiftUI

@MainActor
final class StatusItemController: NSObject, NSPopoverDelegate {
    private let model: AppModel
    private let statusItem: NSStatusItem
    private let popover = NSPopover()
    private var flagsMonitor: Any?
    private var keyMonitor: Any?

    init(model: AppModel) {
        self.model = model
        self.statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        super.init()

        if let button = statusItem.button {
            button.imageScaling = .scaleProportionallyDown
            button.toolTip = "iQuit"
            button.sendAction(on: [.leftMouseUp, .rightMouseUp])
            button.target = self
            button.action = #selector(handleClick(_:))
            button.setAccessibilityLabel("iQuit")
            button.font = NSFont.monospacedDigitSystemFont(ofSize: 12, weight: .medium)
        }

        let root = PopoverView()
            .environment(model)
            .tint(iQuitTheme.accent)
            .preferredColorScheme(model.appearance.colorScheme)
        popover.contentViewController = NSHostingController(rootView: root)
        popover.contentSize = NSSize(width: 360, height: 460)
        popover.behavior = .transient
        popover.animates = true
        popover.delegate = self

        model.onRequestClose = { [weak self] in
            self?.popover.performClose(nil)
        }
        observeMenuBarState()
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
        startMonitors()
    }

    func popoverDidClose(_ notification: Notification) {
        model.stopLiveRefresh()
        stopMonitors()
        model.setOptionHeld(false)
    }

    // MARK: Menu bar button

    private func observeMenuBarState() {
        withObservationTracking {
            updateButton()
        } onChange: { [weak self] in
            Task { @MainActor in
                self?.observeMenuBarState()
            }
        }
    }

    private func updateButton() {
        guard let button = statusItem.button else { return }
        let style = model.menuBarIconStyle
        let showCount = model.showMenuBarCount
        let count = model.regularQuitableCount
        button.image = MenuBarIcon.image(style: style)
        if showCount {
            button.title = " \(count)"
            button.imagePosition = .imageLeading
        } else {
            button.title = ""
            button.imagePosition = .imageOnly
        }
    }

    // MARK: Clicks and menu

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

    // MARK: Event monitors (popover is key while shown, so local monitors suffice)

    private func startMonitors() {
        stopMonitors()
        flagsMonitor = NSEvent.addLocalMonitorForEvents(matching: .flagsChanged) { [weak self] event in
            self?.model.setOptionHeld(event.modifierFlags.contains(.option))
            return event
        }
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self, self.popover.isShown,
                  event.window === self.popover.contentViewController?.view.window
            else { return event }
            return self.model.handleKey(event) ? nil : event
        }
    }

    private func stopMonitors() {
        if let flagsMonitor {
            NSEvent.removeMonitor(flagsMonitor)
            self.flagsMonitor = nil
        }
        if let keyMonitor {
            NSEvent.removeMonitor(keyMonitor)
            self.keyMonitor = nil
        }
    }
}
