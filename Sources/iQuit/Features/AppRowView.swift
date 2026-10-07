import AppKit
import SwiftUI

/// One list row. Everything it displays arrives as plain values and the view is
/// Equatable, so SwiftUI only re-renders a row when its own inputs change.
/// (`@State` is unavailable here: the Command Line Tools toolchain lacks SwiftUIMacros.)
struct AppRowView: View, Equatable {
    @Environment(AppModel.self) private var appModel

    let app: ListedApp
    let icon: NSImage?
    let isSelected: Bool
    let isFocused: Bool
    let isHovered: Bool
    let exclusionLabel: String?
    let quitState: QuitState?
    let autoQuitRemaining: TimeInterval?
    let showMetrics: Bool
    let forceMode: Bool

    nonisolated static func == (lhs: AppRowView, rhs: AppRowView) -> Bool {
        lhs.app == rhs.app
            && lhs.icon === rhs.icon
            && lhs.isSelected == rhs.isSelected
            && lhs.isFocused == rhs.isFocused
            && lhs.isHovered == rhs.isHovered
            && lhs.exclusionLabel == rhs.exclusionLabel
            && lhs.quitState == rhs.quitState
            && lhs.autoQuitRemaining == rhs.autoQuitRemaining
            && lhs.showMetrics == rhs.showMetrics
            && lhs.forceMode == rhs.forceMode
    }

    private var excluded: Bool { exclusionLabel != nil }

    var body: some View {
        HStack(spacing: 8) {
            Button {
                appModel.toggleSelected(app)
            } label: {
                Image(systemName: isSelected ? "checkmark.square.fill" : "square")
                    .foregroundStyle(isSelected ? iQuitTheme.accent : iQuitTheme.muted)
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(excluded)
            .accessibilityLabel(isSelected ? "Deselect \(app.name)" : "Select \(app.name)")

            appIcon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                subtitle
            }

            Spacer(minLength: 4)

            trailingControls

            Menu {
                Button(excluded && exclusionLabel == "Never quit" ? "Allow Quit" : "Never Quit") {
                    appModel.toggleNeverQuit(app)
                }
                .disabled(app.bundleID == nil)
                Button("Quit & Reopen") {
                    appModel.relaunch(app)
                }
                .disabled(excluded || app.bundleURL == nil || quitState != nil)
                Divider()
                Button("Reveal in Finder") {
                    appModel.revealInFinder(app)
                }
                .disabled(app.bundleURL == nil)
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(iQuitTheme.muted)
                    .frame(width: 18, height: 18)
            }
            .menuStyle(.borderlessButton)
            .menuIndicator(.hidden)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 7)
        .background(isSelected || isHovered ? iQuitTheme.fill : Color.clear)
        .overlay(alignment: .leading) {
            if isFocused {
                RoundedRectangle(cornerRadius: 1.5)
                    .fill(iQuitTheme.accent)
                    .frame(width: 3)
                    .padding(.vertical, 4)
                    .padding(.leading, 4)
            }
        }
        .opacity(excluded ? 0.7 : 1)
        .onHover { appModel.setHovered(app.id, hovering: $0) }
        .help(helpText)
        .accessibilityElement(children: .contain)
        .accessibilityLabel(app.name)
    }

    @ViewBuilder
    private var subtitle: some View {
        if let quitState {
            HStack(spacing: 4) {
                if quitState == .quitting {
                    ProgressView()
                        .controlSize(.mini)
                }
                Text(quitState == .stuck ? "Still running" : "Quitting…")
                    .foregroundStyle(quitState == .stuck ? iQuitTheme.danger : iQuitTheme.muted)
            }
            .font(.caption2)
        } else if let exclusionLabel {
            Text(exclusionLabel)
                .font(.caption2)
                .foregroundStyle(iQuitTheme.muted)
        } else {
            HStack(spacing: 4) {
                if showMetrics {
                    Text(app.formattedCPU)
                        .foregroundStyle(app.cpuIsHeavy ? iQuitTheme.accentInk : iQuitTheme.muted)
                    Text("·")
                        .foregroundStyle(iQuitTheme.muted)
                    Text(app.formattedMemory)
                        .foregroundStyle(app.memoryIsHeavy ? iQuitTheme.accentInk : iQuitTheme.muted)
                }
                if let autoQuitRemaining {
                    if showMetrics {
                        Text("·")
                            .foregroundStyle(iQuitTheme.muted)
                    }
                    Text(Self.countdownText(autoQuitRemaining))
                        .foregroundStyle(autoQuitRemaining < 60 ? iQuitTheme.accentInk : iQuitTheme.muted)
                }
            }
            .font(.caption2.monospacedDigit())
        }
    }

    @ViewBuilder
    private var trailingControls: some View {
        if !excluded {
            if quitState == .stuck {
                Button("Force") {
                    appModel.forceQuit(app)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.mini)
                .tint(iQuitTheme.danger)
            } else {
                Button(forceMode ? "Force" : "Quit") {
                    appModel.quit(app)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(forceMode ? iQuitTheme.danger : iQuitTheme.accent)
                .disabled(quitState == .quitting && !forceMode)
            }
        }
    }

    private var helpText: String {
        var parts: [String] = []
        if let bundleID = app.bundleID { parts.append(bundleID) }
        if !app.helperPIDs.isEmpty {
            let noun = app.helperPIDs.count == 1 ? "helper process" : "helper processes"
            parts.append("Includes \(app.helperPIDs.count) \(noun)")
        }
        if app.hasVisibleWindows { parts.append("Has windows on screen") }
        return parts.joined(separator: "\n")
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "app")
                .foregroundStyle(iQuitTheme.muted)
        }
    }

    nonisolated static func countdownText(_ remaining: TimeInterval) -> String {
        let seconds = Int(remaining.rounded(.up))
        if seconds <= 0 { return "auto-quits now" }
        if seconds < 60 { return "auto-quits in \(seconds)s" }
        let minutes = Int((remaining / 60).rounded(.up))
        if minutes < 60 { return "auto-quits in \(minutes)m" }
        let hours = minutes / 60
        let rest = minutes % 60
        return rest == 0 ? "auto-quits in \(hours)h" : "auto-quits in \(hours)h \(rest)m"
    }
}
