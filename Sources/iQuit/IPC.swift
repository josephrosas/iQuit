import Foundation

enum IPC {
    static func encodeReply(nonce: String, text: String) -> String {
        "\(nonce)|\(text)"
    }

    static func decodeReply(_ raw: String, nonce: String) -> String? {
        let parts = raw.split(separator: "|", maxSplits: 1, omittingEmptySubsequences: false)
        guard parts.count == 2, String(parts[0]) == nonce else { return nil }
        return String(parts[1])
    }

    static func writeReply(_ nonce: String, _ text: String) {
        let url = supportDirectory().appendingPathComponent("reply.txt")
        try? FileManager.default.createDirectory(at: supportDirectory(), withIntermediateDirectories: true)
        try? "\(nonce)\t\(text)".write(to: url, atomically: true, encoding: .utf8)
    }

    static func waitForReply(nonce: String, timeout: TimeInterval = 2) -> String? {
        if let reply = readReply(nonce: nonce) {
            return reply
        }

        let box = ReplyBox()
        let center = DistributedNotificationCenter.default()
        let observer = center.addObserver(
            forName: AppIdentity.replyNotification,
            object: nil,
            queue: nil
        ) { notification in
            guard let raw = notification.object as? String,
                  let reply = decodeReply(raw, nonce: nonce)
            else { return }
            box.value = reply
            CFRunLoopStop(CFRunLoopGetMain())
        }
        defer { center.removeObserver(observer) }

        if let reply = readReply(nonce: nonce) {
            return reply
        }

        let deadline = Date().addingTimeInterval(timeout)
        while box.value == nil, Date() < deadline {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { break }
            RunLoop.current.run(mode: .default, before: Date().addingTimeInterval(remaining))
            if box.value == nil, let reply = readReply(nonce: nonce) {
                return reply
            }
        }
        return box.value ?? readReply(nonce: nonce)
    }

    private final class ReplyBox: @unchecked Sendable {
        private let lock = NSLock()
        private var stored: String?

        var value: String? {
            get {
                lock.lock()
                defer { lock.unlock() }
                return stored
            }
            set {
                lock.lock()
                stored = newValue
                lock.unlock()
            }
        }
    }

    private static func readReply(nonce: String) -> String? {
        for url in replyURLs() {
            guard let text = try? String(contentsOf: url, encoding: .utf8) else { continue }
            let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
            let prefix = nonce + "\t"
            if trimmed.hasPrefix(prefix) {
                return String(trimmed.dropFirst(prefix.count))
            }
        }
        return nil
    }

    private static func supportDirectory() -> URL {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("iQuit", isDirectory: true)
    }

    private static func replyURLs() -> [URL] {
        [
            supportDirectory().appendingPathComponent("reply.txt")
        ]
    }
}
