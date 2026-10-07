import AppKit
import SwiftUI

struct AppRowView: View {
    @Environment(AppModel.self) private var appModel
    let app: ListedApp

    var body: some View {
        HStack(spacing: 8) {
            Button {
                appModel.toggleSelected(app)
            } label: {
                Image(systemName: appModel.selectedKeys.contains(app.id) ? "checkmark.square.fill" : "square")
                    .foregroundStyle(appModel.selectedKeys.contains(app.id) ? iQuitTheme.accent : iQuitTheme.muted)
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .disabled(excluded)

            appIcon
                .frame(width: 24, height: 24)

            VStack(alignment: .leading, spacing: 1) {
                Text(app.name)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                if excluded {
                    Text(exclusionLabel)
                        .font(.caption2)
                        .foregroundStyle(iQuitTheme.muted)
                } else if appModel.showMetrics {
                    HStack(spacing: 4) {
                        Text(app.formattedCPU)
                            .foregroundStyle(app.cpuIsHeavy ? iQuitTheme.accentInk : iQuitTheme.muted)
                        Text("·")
                            .foregroundStyle(iQuitTheme.muted)
                        Text(app.formattedMemory)
                            .foregroundStyle(app.memoryIsHeavy ? iQuitTheme.accentInk : iQuitTheme.muted)
                    }
                    .font(.caption2.monospacedDigit())
                }
            }

            Spacer(minLength: 4)

            if !excluded {
                Button(appModel.forceMode ? "Force" : "Quit") {
                    appModel.quit(app)
                }
                .buttonStyle(.bordered)
                .controlSize(.mini)
                .tint(appModel.forceMode ? iQuitTheme.danger : iQuitTheme.accent)
            }

            Menu {
                Button(neverQuitTitle) {
                    appModel.toggleNeverQuit(app)
                }
                .disabled(app.bundleID == nil)
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
        .background(appModel.selectedKeys.contains(app.id) || appModel.hoveredKey == app.id ? iQuitTheme.fill : Color.clear)
        .opacity(excluded ? 0.7 : 1)
        .onHover { appModel.setHovered(app.id, hovering: $0) }
    }

    private var excluded: Bool {
        appModel.isExcluded(app)
    }

    private var neverQuitTitle: String {
        if let bundleID = app.bundleID, appModel.neverQuitBundleIDs.contains(bundleID) {
            return "Allow Quit"
        }
        return "Never Quit"
    }

    private var exclusionLabel: String {
        if let bundleID = app.bundleID, appModel.neverQuitBundleIDs.contains(bundleID) {
            return "Never quit"
        }
        if app.isMusic, appModel.neverQuitMusic {
            return "Music app"
        }
        return "Protected"
    }

    @ViewBuilder
    private var appIcon: some View {
        if let icon = app.icon {
            Image(nsImage: icon)
                .resizable()
                .interpolation(.high)
                .scaledToFit()
        } else {
            Image(systemName: "app")
                .foregroundStyle(iQuitTheme.muted)
        }
    }
}
