import AppKit
import SwiftUI

struct SettingsView: View {
    @Environment(AppModel.self) private var appModel

    var body: some View {
        @Bindable var appModel = appModel
        ScrollView {
            VStack(alignment: .leading, spacing: 24) {
                Text("Settings")
                    .font(.system(size: 22, weight: .semibold))

                group("General") {
                    Toggle("Launch at login", isOn: $appModel.launchAtLogin)
                    if let loginItemError = appModel.loginItemError {
                        Text(loginItemError)
                            .font(.caption)
                            .foregroundStyle(.red)
                    }
                    Toggle("Play a sound when quitting", isOn: $appModel.playSound)
                    Toggle("Show CPU and memory", isOn: $appModel.showMetrics)
                    Toggle("Show background apps", isOn: $appModel.showBackgroundApps)

                    Text("Launch at login keeps iQuit in the menu bar. Hold Option in the popover to turn Quit into Force Quit.")
                        .font(.caption)
                        .foregroundStyle(iQuitTheme.muted)
                }

                group("Auto Quit") {
                    Toggle("Quit unused apps automatically", isOn: $appModel.autoQuitEnabled)
                    Picker("After", selection: $appModel.autoQuitDuration) {
                        ForEach(AutoQuitDuration.allCases) { duration in
                            Text(duration.title).tag(duration)
                        }
                    }
                    .disabled(!appModel.autoQuitEnabled)
                    Toggle("Skip apps with windows on screen", isOn: $appModel.autoQuitSkipVisibleWindows)
                        .disabled(!appModel.autoQuitEnabled)
                    Toggle("Notify me when apps are auto-quit", isOn: $appModel.notifyOnAutoQuit)
                        .disabled(!appModel.autoQuitEnabled)
                    Toggle("Never quit music apps", isOn: $appModel.neverQuitMusic)

                    if appModel.neverQuitBundleIDs.isEmpty {
                        Text("Mark an app Never Quit from its ⋯ menu in the popover.")
                            .font(.caption)
                            .foregroundStyle(iQuitTheme.muted)
                    } else {
                        VStack(alignment: .leading, spacing: 6) {
                            Text("Never quit")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(iQuitTheme.muted)
                            ForEach(appModel.neverQuitBundleIDs.sorted(), id: \.self) { bundleID in
                                HStack {
                                    Text(appModel.neverQuitName(for: bundleID))
                                    Spacer()
                                    Button("Remove") {
                                        appModel.removeNeverQuit(bundleID)
                                    }
                                    .controlSize(.small)
                                }
                            }
                        }
                    }

                    Text("Auto Quit only closes regular apps that have not been frontmost for the chosen time. The frontmost app, music apps (if enabled), Never Quit apps, and apps that refuse to quit (for example with unsaved changes) are skipped until you use them again. The popover shows a countdown on each app it applies to.")
                        .font(.caption)
                        .foregroundStyle(iQuitTheme.muted)
                }

                group("Keyboard") {
                    HotkeyRecorder(title: "Quit All", hotkey: appModel.quitAllHotkey) {
                        appModel.quitAllHotkey = $0
                    }
                    HotkeyRecorder(title: "Force Quit All", hotkey: appModel.forceQuitAllHotkey) {
                        appModel.forceQuitAllHotkey = $0
                    }
                    Text("Shortcuts work even when the popover is closed. Pick combinations you will not press by accident.")
                        .font(.caption)
                        .foregroundStyle(iQuitTheme.muted)
                    Text("In the popover: type to search, ↑↓ to move, ↩ to quit, Space to select, ⌘A to select all, ⌘⌫ to quit selected, Esc to clear or close. Hold ⌥ for Force Quit.")
                        .font(.caption)
                        .foregroundStyle(iQuitTheme.muted)
                }

                group("Menu Bar") {
                    Picker("Icon", selection: $appModel.menuBarIconStyle) {
                        ForEach(MenuBarIconStyle.allCases) { style in
                            Text(style.title).tag(style)
                        }
                    }
                    .pickerStyle(.segmented)
                    Toggle("Show number of running apps", isOn: $appModel.showMenuBarCount)
                    Text("Monochrome follows the menu bar's light or dark style. The count includes regular apps iQuit is allowed to quit.")
                        .font(.caption)
                        .foregroundStyle(iQuitTheme.muted)
                }

                group("Appearance") {
                    Picker("Appearance", selection: $appModel.appearance) {
                        ForEach(AppearancePreference.allCases) { option in
                            Label(option.title, systemImage: option.symbol)
                                .tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()

                    Text("Match Mac follows System Settings. Light and Dark stay that way even if you change macOS later.")
                        .font(.caption)
                        .foregroundStyle(iQuitTheme.muted)
                }

                group("About") {
                    HStack(spacing: 14) {
                        BrandLogo(size: 56, shadowed: true)
                        VStack(alignment: .leading, spacing: 4) {
                            Text("iQuit")
                                .font(.title3.weight(.semibold))
                            Text("A fresh start without a restart")
                                .font(.caption)
                                .foregroundStyle(iQuitTheme.muted)
                        }
                    }
                    LabeledContent("Version", value: appModel.versionText)
                    LabeledContent("Control", value: "Menu bar, Shortcuts, or iquit://")
                    Button("Send Feedback…") {
                        NSWorkspace.shared.open(AppIdentity.feedback)
                    }
                    Text("iQuit will not quit Finder, Dock, or other protected system processes, and hides Apple system services from the background list. Helper processes are folded into their parent app's CPU and memory. Some background apps may relaunch themselves. Force quit skips save prompts.")
                        .font(.caption)
                        .foregroundStyle(iQuitTheme.muted)
                }

                R6Footer()
            }
            .padding(28)
            .frame(maxWidth: 560, alignment: .leading)
        }
        .frame(minWidth: 480, minHeight: 560, alignment: .topLeading)
        .background(iQuitTheme.page)
        .preferredColorScheme(appModel.appearance.colorScheme)
        .onAppear {
            BrandAppearance.applyAppIcon()
        }
    }

    private func group(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(title)
                .font(.headline)
            content()
        }
        .padding(16)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(iQuitTheme.fill, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(iQuitTheme.divider))
    }
}

struct HotkeyRecorder: View {
    var title: String
    var hotkey: SavedHotkey?
    var onChange: (SavedHotkey?) -> Void

    var body: some View {
        HStack {
            Text(title)
            Spacer()
            KeyCatcher(hotkey: hotkey, onChange: onChange)
                .frame(minWidth: 168, minHeight: 24)
        }
    }
}

private struct KeyCatcher: NSViewRepresentable {
    var hotkey: SavedHotkey?
    var onChange: (SavedHotkey?) -> Void

    func makeNSView(context: Context) -> CatcherView {
        let view = CatcherView()
        view.onChange = onChange
        view.hotkey = hotkey
        view.refresh()
        return view
    }

    func updateNSView(_ nsView: CatcherView, context: Context) {
        nsView.onChange = onChange
        nsView.hotkey = hotkey
        nsView.refresh()
    }

    final class CatcherView: NSView {
        var hotkey: SavedHotkey?
        var onChange: ((SavedHotkey?) -> Void)?
        private var recording = false
        private let recordButton = NSButton()
        private let clearButton = NSButton()

        override init(frame frameRect: NSRect) {
            super.init(frame: frameRect)
            recordButton.bezelStyle = .rounded
            recordButton.target = self
            recordButton.action = #selector(toggleRecording)
            addSubview(recordButton)

            clearButton.title = "Clear"
            clearButton.bezelStyle = .inline
            clearButton.isBordered = false
            clearButton.target = self
            clearButton.action = #selector(clearHotkey)
            addSubview(clearButton)
        }

        required init?(coder: NSCoder) {
            fatalError("init(coder:) has not been implemented")
        }

        override var acceptsFirstResponder: Bool { true }

        override func layout() {
            super.layout()
            let clearWidth: CGFloat = recording || hotkey == nil ? 0 : 44
            clearButton.frame = NSRect(x: bounds.width - clearWidth, y: 0, width: clearWidth, height: bounds.height)
            recordButton.frame = NSRect(x: 0, y: 0, width: bounds.width - clearWidth - (clearWidth > 0 ? 6 : 0), height: bounds.height)
        }

        func refresh() {
            recordButton.title = recording ? "Type a shortcut…" : (hotkey?.displayString ?? "None")
            clearButton.isHidden = recording || hotkey == nil
            needsLayout = true
        }

        @objc private func toggleRecording() {
            recording.toggle()
            refresh()
            if recording {
                window?.makeFirstResponder(self)
            }
        }

        @objc private func clearHotkey() {
            recording = false
            onChange?(nil)
        }

        override func keyDown(with event: NSEvent) {
            guard recording else {
                super.keyDown(with: event)
                return
            }
            if event.keyCode == UInt16(kVKEscape) {
                recording = false
                refresh()
                return
            }
            if let hotkey = SavedHotkey.from(event: event) {
                recording = false
                onChange?(hotkey)
            }
        }

        override func flagsChanged(with event: NSEvent) {
            guard recording else {
                super.flagsChanged(with: event)
                return
            }
        }
    }
}

private let kVKEscape: Int = 53
