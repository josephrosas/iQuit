import AppKit
import Foundation

enum CLICommand: Equatable {
    case quitAll
    case forceQuitAll
    case quit(String)
    case list
    case status
    case help

    var encoded: String {
        switch self {
        case .quitAll: return "quit-all"
        case .forceQuitAll: return "force-quit-all"
        case .quit(let name): return "quit:\(name)"
        case .list: return "list"
        case .status: return "status"
        case .help: return "help"
        }
    }

    static func decode(_ raw: String) -> CLICommand? {
        switch raw {
        case "quit-all": return .quitAll
        case "force-quit-all": return .forceQuitAll
        case "list": return .list
        case "status": return .status
        case "help": return .help
        default:
            if raw.hasPrefix("quit:") {
                return .quit(String(raw.dropFirst("quit:".count)))
            }
            return nil
        }
    }
}

enum CLI {
    static let usage = """
    iQuit — a fresh start without a restart

    Usage:
      iQuit --quit-all
      iQuit --force-quit-all
      iQuit --quit <name>
      iQuit --list
      iQuit --status
      iQuit --help

    URL scheme:
      iquit://quit-all
      iquit://force-quit-all
      iquit://quit?name=TextEdit
      iquit://list
    """

    static func parse(_ arguments: [String]) -> CLICommand? {
        let args = arguments.dropFirst()
        guard let first = args.first else { return nil }

        switch first {
        case "--help", "-h", "help":
            return .help
        case "--status", "status":
            return .status
        case "--list", "list":
            return .list
        case "--quit-all", "quit-all":
            return .quitAll
        case "--force-quit-all", "force-quit-all":
            return .forceQuitAll
        case "--quit", "quit":
            guard let name = args.dropFirst().first, !name.isEmpty else { return .help }
            return .quit(name)
        default:
            if first.hasPrefix("-") {
                return .help
            }
            return nil
        }
    }

    /// Returns true when this process should exit without opening the GUI.
    static func handleIfNeeded() -> Bool {
        guard let command = parse(CommandLine.arguments) else {
            return false
        }

        if command == .help {
            FileHandle.standardOutput.write(Data((usage + "\n").utf8))
            return true
        }

        if let existing = otherRunningInstance() {
            _ = existing
            if let reply = send(command) {
                FileHandle.standardOutput.write(Data((reply + "\n").utf8))
                return true
            }
            FileHandle.standardError.write(Data("iQuit is running but did not reply.\n".utf8))
            return true
        }

        switch command {
        case .quitAll, .forceQuitAll, .quit:
            AppRuntime.pendingCommand = command
            return false
        case .list, .status:
            FileHandle.standardOutput.write(Data("iQuit is not running.\n".utf8))
            return true
        case .help:
            FileHandle.standardOutput.write(Data((usage + "\n").utf8))
            return true
        }
    }

    static func otherRunningInstance() -> NSRunningApplication? {
        NSRunningApplication.runningApplications(withBundleIdentifier: AppIdentity.bundleID)
            .first { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }
    }

    static func send(_ command: CLICommand) -> String? {
        let nonce = UUID().uuidString
        DistributedNotificationCenter.default().postNotificationName(
            AppIdentity.commandNotification,
            object: "\(nonce)|\(command.encoded)",
            userInfo: nil,
            deliverImmediately: true
        )
        return IPC.waitForReply(nonce: nonce)
    }
}

enum URLCommand {
    static func parse(_ url: URL) -> CLICommand? {
        guard url.scheme?.lowercased() == "iquit" else { return nil }
        let host = (url.host ?? url.path).trimmingCharacters(in: CharacterSet(charactersIn: "/")).lowercased()
        switch host {
        case "quit-all":
            return .quitAll
        case "force-quit-all":
            return .forceQuitAll
        case "quit":
            let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems ?? []
            if let name = items.first(where: { $0.name == "name" })?.value, !name.isEmpty {
                return .quit(name)
            }
            return nil
        case "list":
            return .list
        case "status":
            return .status
        default:
            return nil
        }
    }
}
