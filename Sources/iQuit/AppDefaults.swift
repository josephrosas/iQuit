import Foundation

enum AppIdentity {
    static let name = "iQuit"
    static let bundleID = "com.unga.iQuit"
    static let website = URL(string: "https://r6.ai")!
    static let feedback = URL(string: "mailto:hi@r6.ai?subject=iQuit%20Feedback")!
    static let commandNotification = Notification.Name("com.unga.iQuit.command")
    static let replyNotification = Notification.Name("com.unga.iQuit.reply")
}

enum AppDefaults {
    static let launchAtLogin = "iquit.launchAtLogin"
    static let appearance = "iquit.appearance"
    static let playSound = "iquit.playSound"
    static let showMetrics = "iquit.showMetrics"
    static let showBackgroundApps = "iquit.showBackgroundApps"
    static let autoQuitEnabled = "iquit.autoQuitEnabled"
    static let autoQuitMinutes = "iquit.autoQuitMinutes"
    static let neverQuitMusic = "iquit.neverQuitMusic"
    static let neverQuitBundleIDs = "iquit.neverQuitBundleIDs"
    static let quitAllKeyCode = "iquit.quitAllKeyCode"
    static let quitAllModifiers = "iquit.quitAllModifiers"
    static let forceQuitAllKeyCode = "iquit.forceQuitAllKeyCode"
    static let forceQuitAllModifiers = "iquit.forceQuitAllModifiers"
    static let sort = "iquit.sort"

    static func bool(forKey key: String, default defaultValue: Bool) -> Bool {
        let defaults = UserDefaults.standard
        guard defaults.object(forKey: key) != nil else { return defaultValue }
        return defaults.bool(forKey: key)
    }
}

enum ProtectedApps {
    static let bundleIDs: Set<String> = [
        "com.unga.iQuit",
        "com.apple.finder",
        "com.apple.dock",
        "com.apple.loginwindow",
        "com.apple.WindowServer",
        "com.apple.systemuiserver",
        "com.apple.controlcenter",
        "com.apple.notificationcenterui",
        "com.apple.Spotlight",
        "com.apple.UserNotificationCenter",
        "com.apple.coreservices.uiagent",
        "com.apple.ControlCenter",
        "com.apple.wallpaper.agent",
        "com.apple.dock.extra"
    ]

    static let musicBundleIDs: Set<String> = [
        "com.apple.Music",
        "com.apple.iTunes",
        "com.apple.podcasts",
        "com.apple.TV",
        "com.apple.Radio",
        "com.spotify.client",
        "com.apple.Music.Mac",
        "com.tidal.desktop",
        "com.amazon.aiv.AIVApp",
        "com.amazon.music",
        "com.apple.AMPLibraryAgent",
        "tv.plex.desktop",
        "com.apple.garageband10",
        "com.apple.logic10"
    ]
}

enum AppSort: String, CaseIterable, Identifiable {
    case name
    case cpu
    case memory

    var id: String { rawValue }

    var title: String {
        switch self {
        case .name: return "Name"
        case .cpu: return "CPU"
        case .memory: return "Memory"
        }
    }

    static func fromStorage(_ value: String?) -> AppSort {
        AppSort(rawValue: value ?? "") ?? .name
    }
}

enum AutoQuitDuration: Int, CaseIterable, Identifiable {
    case minutes5 = 5
    case minutes15 = 15
    case minutes30 = 30
    case minutes60 = 60

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .minutes5: return "5 minutes"
        case .minutes15: return "15 minutes"
        case .minutes30: return "30 minutes"
        case .minutes60: return "1 hour"
        }
    }

    var seconds: TimeInterval { TimeInterval(rawValue * 60) }

    static func fromStorage(_ value: Int) -> AutoQuitDuration {
        AutoQuitDuration(rawValue: value) ?? .minutes15
    }
}
