import AppKit
import Foundation
import UserNotifications

/// Posts a "closed N idle apps" notification with a Reopen action.
/// UNUserNotificationCenter aborts when the process is not a real .app bundle,
/// so everything is guarded on `isAvailable`.
@MainActor
final class AutoQuitNotifier: NSObject, UNUserNotificationCenterDelegate {
    nonisolated static let categoryID = "iquit.autoquit"
    nonisolated static let reopenActionID = "iquit.reopen"
    private nonisolated static let bundleURLsKey = "bundleURLs"

    var onReopen: (([URL]) -> Void)?

    static let isAvailable: Bool = {
        Bundle.main.bundleURL.pathExtension == "app" && Bundle.main.bundleIdentifier != nil
    }()

    private var configured = false

    func configure() {
        guard Self.isAvailable, !configured else { return }
        configured = true
        let center = UNUserNotificationCenter.current()
        center.delegate = self
        let reopen = UNNotificationAction(identifier: Self.reopenActionID, title: "Reopen", options: [])
        let category = UNNotificationCategory(
            identifier: Self.categoryID,
            actions: [reopen],
            intentIdentifiers: [],
            options: []
        )
        center.setNotificationCategories([category])
    }

    func requestAuthorization() {
        guard Self.isAvailable else { return }
        configure()
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound]) { _, _ in }
    }

    func notify(names: [String], bundleURLs: [URL]) {
        guard Self.isAvailable, !names.isEmpty else { return }
        configure()
        let content = UNMutableNotificationContent()
        let noun = names.count == 1 ? "idle app" : "idle apps"
        content.title = "iQuit closed \(names.count) \(noun)"
        content.body = names.joined(separator: ", ")
        content.categoryIdentifier = Self.categoryID
        content.userInfo = [Self.bundleURLsKey: bundleURLs.map(\.path)]
        let request = UNNotificationRequest(identifier: UUID().uuidString, content: content, trigger: nil)
        UNUserNotificationCenter.current().add(request)
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let userInfo = response.notification.request.content.userInfo
        let paths = userInfo[Self.bundleURLsKey] as? [String] ?? []
        let action = response.actionIdentifier
        if action == Self.reopenActionID || action == UNNotificationDefaultActionIdentifier {
            Task { @MainActor in
                self.onReopen?(paths.map { URL(fileURLWithPath: $0) })
            }
        }
        completionHandler()
    }

    nonisolated func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        completionHandler([.banner, .sound])
    }
}
