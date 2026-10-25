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

    func register(alternate: Bool, stackEnabled: Bool = false) {
        for ref in references { UnregisterEventHotKey(ref) }
        references.removeAll()
        let modifiers = alternate ? UInt32(cmdKey | optionKey) : UInt32(cmdKey | shiftKey)
        primaryAvailable = add(id: 1, code: UInt32(kVK_ANSI_V), modifiers: modifiers)
        stackAvailable = stackEnabled && add(id: 2, code: UInt32(kVK_ANSI_C), modifiers: UInt32(cmdKey | shiftKey))
        _ = add(id: 3, code: UInt32(kVK_ANSI_V), modifiers: UInt32(cmdKey | optionKey | controlKey))
    }

    private func add(id: UInt32, code: UInt32, modifiers: UInt32) -> Bool {
        var ref: EventHotKeyRef?
        let status = RegisterEventHotKey(code, modifiers, EventHotKeyID(signature: 0x454E4352, id: id), GetApplicationEventTarget(), 0, &ref)
        if status == noErr, let ref { references.append(ref); return true }
        return false
    }

    func stop() {
        references.forEach { UnregisterEventHotKey($0) }
        references.removeAll()
        if let handler { RemoveEventHandler(handler) }
        handler = nil
    }
}
