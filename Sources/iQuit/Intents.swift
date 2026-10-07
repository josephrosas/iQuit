import AppIntents
import Foundation

struct QuitAllAppsIntent: AppIntent {
    static let title: LocalizedStringResource = "Quit All Apps"
    static let description = IntentDescription("Ask every unprotected app to quit, giving them a chance to save.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = AppRuntime.model.quitableApps.count
        AppRuntime.model.quitAll(force: false)
        return .result(dialog: "Asked \(count) apps to quit.")
    }
}

struct ForceQuitAllAppsIntent: AppIntent {
    static let title: LocalizedStringResource = "Force Quit All Apps"
    static let description = IntentDescription("Force quit every unprotected app without waiting for save prompts.")

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let count = AppRuntime.model.quitableApps.count
        AppRuntime.model.quitAll(force: true)
        return .result(dialog: "Force quit \(count) apps.")
    }
}

struct iQuitStatusIntent: AppIntent {
    static let title: LocalizedStringResource = "iQuit Status"
    static let description = IntentDescription("Report how many apps iQuit can quit right now.")

    @MainActor
    func perform() async throws -> some IntentResult & ReturnsValue<String> & ProvidesDialog {
        let line = AppRuntime.model.statusLine()
        return .result(value: line, dialog: "\(line)")
    }
}

struct iQuitShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: QuitAllAppsIntent(),
            phrases: [
                "Quit all apps with \(.applicationName)",
                "Clear my Mac with \(.applicationName)"
            ],
            shortTitle: "Quit All",
            systemImageName: "power"
        )
        AppShortcut(
            intent: ForceQuitAllAppsIntent(),
            phrases: [
                "Force quit all apps with \(.applicationName)"
            ],
            shortTitle: "Force Quit All",
            systemImageName: "exclamationmark.octagon"
        )
        AppShortcut(
            intent: iQuitStatusIntent(),
            phrases: [
                "How many apps can \(.applicationName) quit"
            ],
            shortTitle: "Status",
            systemImageName: "info.circle"
        )
    }
}
