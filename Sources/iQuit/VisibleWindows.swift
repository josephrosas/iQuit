import CoreGraphics
import Foundation

/// Owner PIDs of windows currently on screen. Reads only owner PID, layer and bounds,
/// which need no Screen Recording permission (window titles would).
enum VisibleWindows {
    static func ownerPIDs() -> Set<pid_t> {
        let options: CGWindowListOption = [.optionOnScreenOnly, .excludeDesktopElements]
        guard let list = CGWindowListCopyWindowInfo(options, kCGNullWindowID) as? [[String: Any]] else {
            return []
        }
        var owners: Set<pid_t> = []
        for window in list {
            guard let layer = window[kCGWindowLayer as String] as? Int, layer == 0 else { continue }
            guard let pid = window[kCGWindowOwnerPID as String] as? pid_t else { continue }
            if let bounds = window[kCGWindowBounds as String] as? [String: CGFloat],
               let width = bounds["Width"], let height = bounds["Height"],
               width < 40 || height < 40 {
                continue
            }
            owners.insert(pid)
        }
        return owners
    }
}
