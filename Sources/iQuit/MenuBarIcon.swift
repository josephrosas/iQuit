import AppKit

enum MenuBarIcon {
    static func image() -> NSImage {
        let image = loadedLogo() ?? fallback()
        let side = max(18, NSStatusBar.system.thickness - 2)
        image.size = NSSize(width: side, height: side)
        image.isTemplate = false
        return image
    }

    private static func loadedLogo() -> NSImage? {
        guard let url = Bundle.main.url(forResource: "AppLogo", withExtension: "png")
            ?? Bundle.main.url(forResource: "AppIcon", withExtension: "png")
        else {
            return nil
        }
        return NSImage(contentsOf: url)
    }

    private static func fallback() -> NSImage {
        let side: CGFloat = 20
        let image = NSImage(size: NSSize(width: side, height: side), flipped: false) { rect in
            NSColor.black.setFill()
            NSBezierPath(roundedRect: rect, xRadius: rect.width * 0.22, yRadius: rect.width * 0.22).fill()
            return true
        }
        image.isTemplate = false
        return image
    }
}
