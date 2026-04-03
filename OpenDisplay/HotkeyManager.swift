import Carbon
import AppKit

/// Global keyboard shortcut manager
class HotkeyManager {
    static let shared = HotkeyManager()

    enum Action: String, Codable, CaseIterable {
        case brightnessUp, brightnessDown, contrastUp, contrastDown
        case volumeUp, volumeDown, volumeMute
        case nextInput, toggleNightShift
    }

    private var hotkeys: [UInt32: (ref: EventHotKeyRef?, action: Action)] = [:]
    private var nextID: UInt32 = 1
    var onAction: ((Action) -> Void)?

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        let handler: EventHandlerUPP = { _, event, _ -> OSStatus in
            var hkID = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject),
                              EventParamType(typeEventHotKeyID), nil,
                              MemoryLayout<EventHotKeyID>.size, nil, &hkID)
            HotkeyManager.shared.handleHotkey(id: hkID.id)
            return noErr
        }
        InstallEventHandler(GetApplicationEventTarget(), handler, 1, &spec, nil, nil)
    }

    @discardableResult
    func register(keyCode: UInt32, modifiers: UInt32, action: Action) -> UInt32 {
        let id = nextID; nextID += 1
        var hkID = EventHotKeyID(signature: OSType(0x4F44), id: id)
        var ref: EventHotKeyRef?
        let mods = carbonMods(modifiers)
        RegisterEventHotKey(keyCode, mods, hkID, GetApplicationEventTarget(), 0, &ref)
        hotkeys[id] = (ref, action)
        return id
    }

    func unregisterAll() {
        hotkeys.values.forEach { if let r = $0.ref { UnregisterEventHotKey(r) } }
        hotkeys.removeAll()
    }

    private func handleHotkey(id: UInt32) { if let e = hotkeys[id] { onAction?(e.action) } }

    private func carbonMods(_ ns: UInt32) -> UInt32 {
        var c: UInt32 = 0
        if ns & UInt32(NSEvent.ModifierFlags.command.rawValue) != 0 { c |= UInt32(cmdKey) }
        if ns & UInt32(NSEvent.ModifierFlags.option.rawValue) != 0 { c |= UInt32(optionKey) }
        if ns & UInt32(NSEvent.ModifierFlags.control.rawValue) != 0 { c |= UInt32(controlKey) }
        if ns & UInt32(NSEvent.ModifierFlags.shift.rawValue) != 0 { c |= UInt32(shiftKey) }
        return c
    }
}
