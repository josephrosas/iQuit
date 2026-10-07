import AppKit
import SwiftUI

struct PopoverView: View {
    @Environment(AppModel.self) private var appModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            if appModel.forceMode {
                forceBanner
            }
            searchRow
            Divider()
            if appModel.shownApps.isEmpty {
                emptyState
            } else {
                appList
            }
            if let batch = appModel.recentBatch {
                Divider()
                reopenToast(batch)
            }
            Divider()
            footer
        }
        .frame(width: 360)
        .frame(minHeight: 320, maxHeight: 520)
        .background(iQuitTheme.page)
        .preferredColorScheme(appModel.appearance.colorScheme)
        .onAppear { searchFocused = true }
        .onChange(of: appModel.popoverGeneration) { _, _ in
            searchFocused = true
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 10) {
                BrandLogo(size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text("iQuit")
                        .font(.headline)
                    if !appModel.forceMode, !appModel.confirmingQuitAll {
                        Text(subtitle)
                            .font(.caption)
                            .foregroundStyle(iQuitTheme.muted)
                    }
                }
                Spacer(minLength: 8)
                if !appModel.confirmingQuitAll {
                    Button(appModel.quitAllTitle) {
                        appModel.beginQuitAllConfirmation()
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(appModel.forceMode ? iQuitTheme.danger : iQuitTheme.accent)
                    .disabled(appModel.shownQuitableApps.isEmpty)
                }
            }
            if appModel.confirmingQuitAll {
                confirmation
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
    }

    private var confirmation: some View {
        HStack(spacing: 8) {
            Text(appModel.quitAllConfirmTitle)
                .font(.callout.weight(.semibold))
            Spacer(minLength: 8)
            Button("Cancel") {
                appModel.cancelQuitAllConfirmation()
            }
            .controlSize(.small)
            Button(appModel.forceMode ? "Force Quit" : "Quit") {
                appModel.confirmQuitAll()
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.small)
            .tint(appModel.forceMode ? iQuitTheme.danger : iQuitTheme.accent)
        }
    }

    private var subtitle: String {
        let count = appModel.shownApps.count
        if count == 0 { return "Nothing to quit" }
        return count == 1 ? "1 app" : "\(count) apps"
    }

    private var forceBanner: some View {
        Text("Force Quit — unsaved work will not be saved.")
            .font(.caption.weight(.semibold))
            .foregroundStyle(.white)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(iQuitTheme.danger)
    }

    private var searchRow: some View {
        @Bindable var appModel = appModel
        return HStack(spacing: 8) {
            Image(systemName: "magnifyingglass")
                .foregroundStyle(iQuitTheme.muted)
            TextField("Search apps", text: $appModel.searchText)
                .textFieldStyle(.plain)
                .focused($searchFocused)
            if !appModel.searchText.isEmpty {
                Button {
                    appModel.searchText = ""
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(iQuitTheme.muted)
                }
                .buttonStyle(.plain)
            }
            Picker("Sort", selection: $appModel.sort) {
                ForEach(AppSort.allCases) { option in
                    Text(option.title).tag(option)
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
            .fixedSize()
        }
        .padding(.horizontal, 14)
        .padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 8) {
            Image(systemName: appModel.searchText.isEmpty ? "checkmark.circle" : "magnifyingglass")
                .font(.system(size: 28, weight: .regular))
                .foregroundStyle(iQuitTheme.accent)
            Text(appModel.searchText.isEmpty ? "All clear" : "No matches")
                .font(.headline)
            Text(appModel.searchText.isEmpty ? "No running apps to quit." : "Nothing matches that search.")
                .font(.caption)
                .foregroundStyle(iQuitTheme.muted)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private var appList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(spacing: 0) {
                    if !appModel.shownQuitableApps.isEmpty {
                        selectAllRow
                    }
                    ForEach(appModel.regularApps) { app in
                        row(app)
                    }
                    if appModel.showBackgroundApps, !appModel.backgroundApps.isEmpty {
                        HStack {
                            Text("Background")
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(iQuitTheme.muted)
                                .textCase(.uppercase)
                            Spacer()
                        }
                        .padding(.horizontal, 14)
                        .padding(.top, 10)
                        .padding(.bottom, 4)
                        ForEach(appModel.backgroundApps) { app in
                            row(app)
                        }
                    }
                }
            }
            .onChange(of: appModel.focusedKey) { _, key in
                guard let key else { return }
                withAnimation(.easeOut(duration: 0.12)) {
                    proxy.scrollTo(key, anchor: .center)
                }
            }
        }
    }

    private func row(_ app: ListedApp) -> some View {
        let now = appModel.lastRefresh
        return AppRowView(
            app: app,
            icon: appModel.icon(for: app),
            isSelected: appModel.selectedKeys.contains(app.id),
            isFocused: appModel.focusedKey == app.id,
            isHovered: appModel.hoveredKey == app.id,
            exclusionLabel: appModel.exclusionLabel(for: app),
            quitState: appModel.quitState(for: app),
            autoQuitRemaining: appModel.autoQuitRemaining(for: app, now: now),
            showMetrics: appModel.showMetrics,
            forceMode: appModel.forceMode
        )
        .equatable()
        .id(app.id)
    }

    private var selectAllRow: some View {
        HStack(spacing: 8) {
            Button {
                appModel.toggleSelectAll()
            } label: {
                Image(systemName: selectSymbol)
                    .foregroundStyle(appModel.selectAllState == .none ? iQuitTheme.muted : iQuitTheme.accent)
                    .font(.system(size: 14, weight: .medium))
            }
            .buttonStyle(.plain)
            .accessibilityLabel(appModel.selectAllState == .all ? "Deselect all" : "Select all")
            Text(appModel.selectAllState == .all ? "Deselect all" : "Select all")
                .font(.caption)
                .foregroundStyle(iQuitTheme.muted)
            Spacer()
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 2)
    }

    private var selectSymbol: String {
        switch appModel.selectAllState {
        case .all: return "checkmark.square.fill"
        case .some: return "minus.square.fill"
        case .none: return "square"
        }
    }

    private func reopenToast(_ batch: QuitBatch) -> some View {
        HStack(spacing: 8) {
            Image(systemName: "checkmark.circle.fill")
                .foregroundStyle(iQuitTheme.accent)
            VStack(alignment: .leading, spacing: 1) {
                Text(batch.title)
                    .font(.caption.weight(.semibold))
                Text(batch.names.joined(separator: ", "))
                    .font(.caption2)
                    .foregroundStyle(iQuitTheme.muted)
                    .lineLimit(1)
            }
            Spacer(minLength: 8)
            if !batch.bundleURLs.isEmpty {
                Button("Reopen") {
                    appModel.reopenRecentBatch()
                }
                .controlSize(.small)
            }
            Button {
                appModel.dismissRecentBatch()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(iQuitTheme.muted)
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Dismiss")
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 8)
        .background(iQuitTheme.fill)
    }

    private var footer: some View {
        VStack(spacing: 6) {
            HStack(spacing: 8) {
                Toggle("Show background apps", isOn: Bindable(appModel).showBackgroundApps)
                    .toggleStyle(.checkbox)
                    .font(.caption)

                Spacer()

                if !appModel.selectedApps.isEmpty {
                    Button(appModel.quitSelectedTitle) {
                        appModel.quitSelected()
                    }
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .tint(appModel.forceMode ? iQuitTheme.danger : iQuitTheme.accent)
                }

                Menu {
                    Button("Preferences…") {
                        SettingsWindowController.shared.show()
                    }
                    Button("About iQuit") {
                        AboutWindowController.shared.show()
                    }
                    Divider()
                    Button("Quit iQuit") {
                        NSApp.terminate(nil)
                    }
                } label: {
                    Image(systemName: "gearshape")
                }
                .menuStyle(.borderlessButton)
                .menuIndicator(.hidden)
                .fixedSize()
                .help("Preferences, About, Quit iQuit")
            }
            HStack {
                Text("↑↓ move · ↩ quit · space select · ⌘⌫ quit selected · ⌥ force")
                    .font(.system(size: 10))
                    .foregroundStyle(iQuitTheme.muted)
                    .lineLimit(1)
                Spacer()
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
    }
}
