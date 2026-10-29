import AppKit
import EncoreCore

@MainActor final class ClipboardService {
    private unowned let model: AppModel
    private let pasteboard: NSPasteboard
    private var changeCount: Int
    /// The last copy taken, kept until the next change: if that change empties the clipboard, the copy is forgotten.
    private var lastCapture: (id: UUID, at: Date)?
    private var timer: Timer?
    private var activationObserver: NSObjectProtocol?
    private var activeOrigin: ClipboardOrigin
    private(set) var lastChangeAt = Date.distantPast
    private(set) var automaticScreenshotRevision: Int?
    var revision: Int { pasteboard.changeCount }
    /// Text for a snippet's {{clipboard}}. Passwords and other concealed copies, which encore never records, are not inserted either.
    var currentText: String {
        let types = pasteboard.types?.map(\.rawValue) ?? []
        guard !PasteboardCapture.ignoredTypes.contains(where: types.contains) else { return "" }
        return pasteboard.string(forType: .string) ?? ""
    }

    init(model: AppModel, pasteboard: NSPasteboard = .general, initialOrigin: ClipboardOrigin? = nil) {
        self.model = model; self.pasteboard = pasteboard; changeCount = pasteboard.changeCount
        let app = NSWorkspace.shared.frontmostApplication
        activeOrigin = initialOrigin ?? ClipboardOrigin(bundleID: app?.bundleIdentifier ?? "", name: app?.localizedName ?? L("Unknown source"))
    }

    func start() {
        guard !model.demo else { return }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] notification in
            MainActor.assumeIsolated {
                guard let app = notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication else { return }
                self?.noteActivation(.init(bundleID: app.bundleIdentifier ?? "", name: app.localizedName ?? L("Unknown source")))
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.poll() }
        }
        RunLoop.main.add(timer!, forMode: .common)
    }

    func stop() {
        timer?.invalidate(); timer = nil
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        activationObserver = nil
    }

    func noteActivation(_ origin: ClipboardOrigin) {
        poll()
        activeOrigin = origin
    }

    func poll() {
        guard pasteboard.changeCount != changeCount else { return }
        changeCount = pasteboard.changeCount
        lastChangeAt = Date()
        automaticScreenshotRevision = nil
        // Password managers can clear the clipboard a while after a copy: the copy then leaves the history too.
        let previous = lastCapture
        lastCapture = nil
        if Self.isCleared(pasteboard) {
            if model.preferences.forgetClearedCopies, let previous, Date().timeIntervalSince(previous.at) < Self.clearWindow { model.forgetCleared(previous.id) }
            return
        }
        guard model.preferences.captureEnabled, model.storage != nil else { return }
        var origin = activeOrigin
        if let declared = pasteboard.string(forType: .init("org.nspasteboard.source")) {
            if declared.isEmpty || declared.count > 255 { origin = .unknown }
            else {
                let appURL = NSWorkspace.shared.urlForApplication(withBundleIdentifier: declared)
                origin = ClipboardOrigin(bundleID: declared, name: appURL.map { FileManager.default.displayName(atPath: $0.path).replacingOccurrences(of: ".app", with: "") } ?? declared)
            }
        }
        let bundle = origin.bundleID
        guard bundle != Bundle.main.bundleIdentifier, !model.preferences.excludedBundleIDs.contains(bundle) else { return }
        if model.preferences.ignoreSensitive && isSecureField() { return }
        do {
            if let capture = try PasteboardCapture.read(pasteboard, sourceName: origin.name, sourceBundle: bundle, ignoreSensitive: model.preferences.ignoreSensitive) {
                var clip = capture.clip
                // The card shows a masked text; the payload keeps the real value, so pasting still works.
                if model.preferences.detectSecrets, [.text, .code].contains(clip.kind), let secret = SecretKind.detect(clip.text) {
                    clip.secret = secret
                    clip.text = SecretKind.mask(clip.text, keeping: model.preferences.secretPreview)
                    clip.kind = .text
                }
                if model.accept(clip, payload: capture.payload), let id = model.library.clips.first(where: { $0.fingerprint == clip.fingerprint })?.id {
                    lastCapture = (id, Date())
                }
            }
        } catch { model.notify(error.localizedDescription) }
    }

    func write(_ payload: ClipPayload, sourceBundle: String? = nil, screenshotCapturedAt: Date? = nil) {
        let items = payload.items.map { item in
            let value = NSPasteboardItem()
            for (type, data) in item.representations { value.setData(data, forType: .init(type)) }
            value.setString(sourceBundle ?? Bundle.main.bundleIdentifier ?? "", forType: .init("org.nspasteboard.source"))
            return value
        }
        pasteboard.clearContents()
        pasteboard.writeObjects(items)
        changeCount = pasteboard.changeCount
        lastChangeAt = screenshotCapturedAt ?? Date()
        automaticScreenshotRevision = screenshotCapturedAt == nil ? nil : changeCount
    }

    /// Bitwarden's longest clearing delay is five minutes; others wait less.
    static let clearWindow: TimeInterval = 600

    /// Nothing left, or only spaces and invisible characters, which is how some apps clear the clipboard.
    static func isCleared(_ pasteboard: NSPasteboard) -> Bool {
        guard let items = pasteboard.pasteboardItems, !items.isEmpty else { return true }
        let types = Set(items.flatMap(\.types).map(\.rawValue))
        let content = ["public.file-url", "public.png", "public.tiff", "public.jpeg", "com.adobe.pdf", "public.url"]
        guard !content.contains(where: types.contains) else { return false }
        let text = pasteboard.string(forType: .string) ?? ""
        return text.trimmingCharacters(in: .whitespacesAndNewlines.union(.controlCharacters)).isEmpty
    }

    private func isSecureField() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        let system = AXUIElementCreateSystemWide()
        var focused: CFTypeRef?
        guard AXUIElementCopyAttributeValue(system, kAXFocusedUIElementAttribute as CFString, &focused) == .success, let focused else { return false }
        guard CFGetTypeID(focused) == AXUIElementGetTypeID() else { return false }
        let element = unsafeBitCast(focused, to: AXUIElement.self)
        var subrole: CFTypeRef?
        AXUIElementCopyAttributeValue(element, kAXSubroleAttribute as CFString, &subrole)
        return subrole as? String == kAXSecureTextFieldSubrole
    }
}

@MainActor final class StackTap {
    static let syntheticTag: Int64 = 0x454E434F5245
    private unowned let model: AppModel
    private var tap: CFMachPort?
    private var source: CFRunLoopSource?

    init(model: AppModel) { self.model = model }

    func enable() -> Bool {
        guard AXIsProcessTrusted() else { return false }
        if let tap { CGEvent.tapEnable(tap: tap, enable: true); return true }
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let callback: CGEventTapCallBack = { _, type, event, context in
            guard let context else { return Unmanaged.passUnretained(event) }
            return MainActor.assumeIsolated {
                let service = Unmanaged<StackTap>.fromOpaque(context).takeUnretainedValue()
                if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
                    if let tap = service.tap { CGEvent.tapEnable(tap: tap, enable: true) }
                    return Unmanaged.passUnretained(event)
                }
                let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
                if service.model.collecting, type == .keyDown, modifiers == .maskCommand,
                   event.getIntegerValueField(.keyboardEventKeycode) == 9,
                   event.getIntegerValueField(.keyboardEventAutorepeat) == 0,
                   event.getIntegerValueField(.eventSourceUserData) != StackTap.syntheticTag,
                   NSWorkspace.shared.frontmostApplication?.bundleIdentifier != Bundle.main.bundleIdentifier {
                    if !service.model.queue.isEmpty && !service.model.advanceQueue() { return nil }
                }
                return Unmanaged.passUnretained(event)
            }
        }
        guard let tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap, options: .defaultTap, eventsOfInterest: mask, callback: callback, userInfo: Unmanaged.passUnretained(self).toOpaque()) else { return false }
        self.tap = tap
        source = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        CFRunLoopAddSource(CFRunLoopGetMain(), source, .commonModes)
        CGEvent.tapEnable(tap: tap, enable: true)
        return true
    }

    func stop() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let source { CFRunLoopRemoveSource(CFRunLoopGetMain(), source, .commonModes) }
        tap = nil; source = nil
    }
}
