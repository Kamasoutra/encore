import AppKit
import Carbon

@MainActor final class Hotkeys {
    private var references: [EventHotKeyRef] = []
    private var handler: EventHandlerRef?
    var action: ((UInt32) -> Void)?
    var primaryAvailable = false
    var stackAvailable = false

    init() {
        var spec = EventTypeSpec(eventClass: OSType(kEventClassKeyboard), eventKind: UInt32(kEventHotKeyPressed))
        InstallEventHandler(GetApplicationEventTarget(), { _, event, context in
            guard let event, let context else { return OSStatus(eventNotHandledErr) }
            var key = EventHotKeyID()
            GetEventParameter(event, EventParamName(kEventParamDirectObject), EventParamType(typeEventHotKeyID), nil, MemoryLayout<EventHotKeyID>.size, nil, &key)
            MainActor.assumeIsolated { Unmanaged<Hotkeys>.fromOpaque(context).takeUnretainedValue().action?(key.id) }
            return noErr
        }, 1, &spec, Unmanaged.passUnretained(self).toOpaque(), &handler)
    }

    func register(_ primary: GlobalShortcut, stackEnabled: Bool = false) {
        suspend()
        primaryAvailable = add(id: 1, code: primary.code, modifiers: primary.modifiers)
        stackAvailable = stackEnabled && add(id: 2, code: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey))
        _ = add(id: 3, code: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey | controlKey))
    }

    private func add(id: UInt32, code: UInt32, modifiers: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x454E4352, id: id), GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { references.append(ref); return true }
        return false
    }

    /// Releases the shortcuts, so a new one can be typed in the settings without triggering them.
    func suspend() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
    }

    func stop() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}

/// The shortcut that shows encore, stored in the preferences as "commandShiftV", "commandOptionV", or "code:modifiers:label".
struct GlobalShortcut: Equatable {
    var code: UInt32
    var modifiers: UInt32
    var label: String

    /// The keys alone: the same keys typed in another order or layout are the same shortcut.
    static func == (a: Self, b: Self) -> Bool { a.code == b.code && a.modifiers == b.modifiers }

    static let standard = GlobalShortcut(code: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | shiftKey), label: "⌘⇧V")

    init(code: UInt32, modifiers: UInt32, label: String) {
        self.code = code; self.modifiers = modifiers; self.label = label
    }

    init(preference: String) {
        let parts = preference.split(separator: ":", maxSplits: 2).map(String.init)
        if preference == "commandOptionV" { self.init(code: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey), label: "⌘⌥V") }
        else if parts.count == 3, let code = UInt32(parts[0]), let modifiers = UInt32(parts[1]) { self.init(code: code, modifiers: modifiers, label: parts[2]) }
        else { self = .standard }
    }

    var preference: String { self == .standard ? "commandShiftV" : "\(code):\(modifiers):\(label)" }

    /// The shortcut typed in the settings, or nil when it would take over a key or an app shortcut such as ⌘V:
    /// it needs ⌥ or ⌃, or ⌘ with another modifier.
    init?(event: NSEvent) {
        let flags = event.modifierFlags.intersection([.command, .option, .control, .shift])
        guard flags.contains(.option) || flags.contains(.control) || flags.isSuperset(of: [.command, .shift]) else { return nil }
        let names: [Int: String] = [kVK_Space: "Space", kVK_Return: "↩", kVK_Tab: "⇥", kVK_Delete: "⌫", kVK_ForwardDelete: "⌦",
                                    kVK_LeftArrow: "←", kVK_RightArrow: "→", kVK_UpArrow: "↑", kVK_DownArrow: "↓", kVK_Home: "↖", kVK_End: "↘",
                                    kVK_PageUp: "⇞", kVK_PageDown: "⇟", kVK_F1: "F1", kVK_F2: "F2", kVK_F3: "F3", kVK_F4: "F4", kVK_F5: "F5", kVK_F6: "F6",
                                    kVK_F7: "F7", kVK_F8: "F8", kVK_F9: "F9", kVK_F10: "F10", kVK_F11: "F11", kVK_F12: "F12"]
        let code = Int(event.keyCode)
        guard code != kVK_Escape, let key = names[code] ?? event.characters(byApplyingModifiers: []).flatMap({ $0.isEmpty ? nil : $0.uppercased() }) else { return nil }
        var modifiers = 0, label = ""
        if flags.contains(.control) { modifiers |= controlKey; label += "⌃" }
        if flags.contains(.option) { modifiers |= optionKey; label += "⌥" }
        if flags.contains(.shift) { modifiers |= shiftKey; label += "⇧" }
        if flags.contains(.command) { modifiers |= cmdKey; label += "⌘" }
        self.init(code: UInt32(code), modifiers: UInt32(modifiers), label: label + key)
    }
}
