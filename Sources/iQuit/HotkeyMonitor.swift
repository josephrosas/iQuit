import AppKit
import Carbon

struct SavedHotkey: Equatable {
    var keyCode: UInt32
    var modifiers: NSEvent.ModifierFlags

    var displayString: String {
        var parts = ""
        if modifiers.contains(.control) { parts += "⌃" }
        if modifiers.contains(.option) { parts += "⌥" }
        if modifiers.contains(.shift) { parts += "⇧" }
        if modifiers.contains(.command) { parts += "⌘" }
        parts += Self.keyName(keyCode)
        return parts
    }

    var carbonModifiers: UInt32 {
        var value: UInt32 = 0
        if modifiers.contains(.command) { value |= UInt32(cmdKey) }
        if modifiers.contains(.option) { value |= UInt32(optionKey) }
        if modifiers.contains(.control) { value |= UInt32(controlKey) }
        if modifiers.contains(.shift) { value |= UInt32(shiftKey) }
        return value
    }

    static func from(event: NSEvent) -> SavedHotkey? {
        let keys = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard !keys.isEmpty else { return nil }
        return SavedHotkey(keyCode: UInt32(event.keyCode), modifiers: keys)
    }

    private static func keyName(_ keyCode: UInt32) -> String {
        switch Int(keyCode) {
        case kVK_Space: return "Space"
        case kVK_Return: return "↩"
        case kVK_Escape: return "⎋"
        case kVK_Tab: return "⇥"
        case kVK_Delete: return "⌫"
        case kVK_ForwardDelete: return "⌦"
        case kVK_LeftArrow: return "←"
        case kVK_RightArrow: return "→"
        case kVK_UpArrow: return "↑"
        case kVK_DownArrow: return "↓"
        default:
            break
        }

        var actualLength = 0
        var chars = [UniChar](repeating: 0, count: 4)
        var deadKeyState: UInt32 = 0
        let keyboard = TISCopyCurrentKeyboardLayoutInputSource().takeRetainedValue()
        guard let raw = TISGetInputSourceProperty(keyboard, kTISPropertyUnicodeKeyLayoutData) else {
            return "?"
        }
        let data = Unmanaged<CFData>.fromOpaque(raw).takeUnretainedValue() as Data
        return data.withUnsafeBytes { buffer -> String in
            guard let layout = buffer.baseAddress?.assumingMemoryBound(to: UCKeyboardLayout.self) else {
                return "?"
            }
            UCKeyTranslate(
                layout,
                UInt16(keyCode),
                UInt16(kUCKeyActionDisplay),
                0,
                UInt32(LMGetKbdType()),
                OptionBits(kUCKeyTranslateNoDeadKeysBit),
                &deadKeyState,
                4,
                &actualLength,
                &chars
            )
            return String(utf16CodeUnits: chars, count: Int(actualLength)).uppercased()
        }
    }
}

@MainActor
final class HotkeyMonitor {
    var onQuitAll: (() -> Void)?
    var onForceQuitAll: (() -> Void)?

    private var quitAllRef: EventHotKeyRef?
    private var forceQuitAllRef: EventHotKeyRef?
    private var handlerRef: EventHandlerRef?
    private static let signature = OSType(0x49515431) // 'IQT1'

    func register(quitAll: SavedHotkey?, forceQuitAll: SavedHotkey?) {
        unregister()

        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let monitor = Unmanaged.passUnretained(self).toOpaque()
        InstallEventHandler(GetApplicationEventTarget(), { _, event, userData in
            guard let userData, let event else { return noErr }
            var hotKeyID = EventHotKeyID()
            let status = GetEventParameter(
                event,
                EventParamName(kEventParamDirectObject),
                EventParamType(typeEventHotKeyID),
                nil,
                MemoryLayout<EventHotKeyID>.size,
                nil,
                &hotKeyID
            )
            guard status == noErr else { return noErr }
            let monitor = Unmanaged<HotkeyMonitor>.fromOpaque(userData).takeUnretainedValue()
            DispatchQueue.main.async {
                if hotKeyID.id == 1 {
                    monitor.onQuitAll?()
                } else if hotKeyID.id == 2 {
                    monitor.onForceQuitAll?()
                }
            }
            return noErr
        }, 1, &spec, monitor, &handlerRef)

        if let quitAll {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: 1)
            if RegisterEventHotKey(quitAll.keyCode, quitAll.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr {
                quitAllRef = ref
            }
        }
        if let forceQuitAll {
            var ref: EventHotKeyRef?
            let id = EventHotKeyID(signature: Self.signature, id: 2)
            if RegisterEventHotKey(forceQuitAll.keyCode, forceQuitAll.carbonModifiers, id, GetApplicationEventTarget(), 0, &ref) == noErr {
                forceQuitAllRef = ref
            }
        }
    }

    func unregister() {
        if let quitAllRef {
            UnregisterEventHotKey(quitAllRef)
            self.quitAllRef = nil
        }
        if let forceQuitAllRef {
            UnregisterEventHotKey(forceQuitAllRef)
            self.forceQuitAllRef = nil
        }
        if let handlerRef {
            RemoveEventHandler(handlerRef)
            self.handlerRef = nil
        }
    }
}
