import AppKit
import SwiftUI
import EncoreCore

@main struct EncoreApp {
    @MainActor static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        app.setActivationPolicy(.accessory)
        app.run()
        withExtendedLifetime(delegate) {}
    }
}

final class EncorePanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor final class AppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate, NSMenuDelegate {
    private var model: AppModel!
    private var panel: EncorePanel!
    private var settingsWindow: NSWindow?
    private var statusItem: NSStatusItem!
    private var hotkeys: Hotkeys!
    private var keyMonitor: Any?
    private var mouseMonitor: Any?
    private var activationObserver: NSObjectProtocol?
    private var screenObserver: NSObjectProtocol?
    private var previousApplication: NSRunningApplication?
    private var permissionTimer: Timer?
    private var retentionTimer: Timer?
    private var wakeObserver: NSObjectProtocol?
    private var aboutWindow: NSWindow?
    private var screenshots: ScreenshotImporter!
    private var inspectorWindow: NSWindow?
    private var inspectorDirty = false
    private var applicationsTimer: Timer?
    private var applicationsObserver: NSObjectProtocol?
    private var quickLookPanel: NSPanel?
    private var shownExpanded = false
    private var downPress: DispatchWorkItem?
    private var shownColumn = false

    func applicationDidFinishLaunching(_ notification: Notification) {
        let demo = CommandLine.arguments.contains("--demo")
        model = AppModel(demo: demo)
        screenshots = ScreenshotImporter(model: model)
        model.updateScreenshotCapture = { [weak self] in self?.screenshots.configure() }
        model.togglePanel = { [weak self] in self?.toggle() }
        model.dismissPanel = { [weak self] in self?.hide() }
        model.showSettings = { [weak self] in self?.openSettings() }
        model.presentInspector = { [weak self] clip in self?.openInspector(clip) }
        model.updateLanguage = { [weak self] in
            guard let self else { return }
            self.installMenu()
            self.settingsWindow?.title = L("Encore Settings")
        }
        model.activateTarget = { [weak self] in self?.previousApplication }
        model.updateShortcuts = { [weak self] in self?.registerShortcuts() }
        model.suspendShortcuts = { [weak self] in self?.hotkeys.suspend() }
        model.updateAppearance = { [weak self] in self?.applyAppearance() }
        model.resizePanel = { [weak self] in self?.positionPanel() }
        model.updateQuickLook = { [weak self] in self?.updateQuickLook() }
        model.compactMoved = { [weak self] in self?.compactMoved() }
        panel = EncorePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "encore"
        panel.identifier = NSUserInterfaceItemIdentifier("EncoreBoard")
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .floating
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.delegate = self
        panel.contentView = NSHostingView(rootView: BoardView(model: model))
        applyAppearance()
        installMenu()
        installStatusItem()
        hotkeys = Hotkeys()
        hotkeys.action = { [weak self] id in
            if id == 2 { self?.model.toggleCollecting(); self?.show() }
            else { self?.toggle() }
        }
        registerShortcuts()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .keyUp]) { [weak self] event in
            let passThrough = MainActor.assumeIsolated {
                guard let self else { return true }
                return self.handleKey(event) != nil
            }
            return passThrough ? event : nil
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.model.demo, self.panel.isVisible, self.panel.attachedSheet == nil, NSApp.modalWindow == nil else { return }
                self.hide()
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                self.previousApplication = app
                if !self.model.demo && self.panel.isVisible { self.hide() }
            }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.objectWillChange.send()
                if self?.panel.isVisible == true { self?.positionPanel() }
            }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                let trusted = AXIsProcessTrusted()
                if self.model.accessibilityGranted != trusted { self.model.accessibilityGranted = trusted }
            }
        }
        applicationsTimer = Timer.scheduledTimer(withTimeInterval: 30, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshInstalledExclusions() }
        }
        applicationsObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didLaunchApplicationNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.refreshInstalledExclusions() }
        }
        retentionTimer = Timer.scheduledTimer(withTimeInterval: 60, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.model.prune()
                if self?.panel.isVisible == true { self?.model.displayTime = Date() }
            }
        }
        RunLoop.main.add(retentionTimer!, forMode: .common)
        wakeObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didWakeNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.prune() }
        }
        model.clipboard.start()
        // `--demo --open shelf|compact` shows the panel on launch, for screenshots.
        if model.demo, let mode = CommandLine.arguments.drop(while: { $0 != "--open" }).dropFirst().first {
            model.preferences.placement = mode == "compact" ? "compact" : "bottom"
            show()
        }
        screenshots.configure()
        if demo || CommandLine.arguments.contains("--show") || !UserDefaults.standard.bool(forKey: "hasLaunched") {
            if !demo { UserDefaults.standard.set(true, forKey: "hasLaunched") }
            show()
        }
        if CommandLine.arguments.contains("--settings") { openSettings() }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }

    func applicationWillTerminate(_ notification: Notification) {
        model.clipboard.stop(); model.stackTap.stop(); hotkeys.stop()
        screenshots.stop()
        permissionTimer?.invalidate()
        applicationsTimer?.invalidate()
        if let applicationsObserver { NSWorkspace.shared.notificationCenter.removeObserver(applicationsObserver) }
        retentionTimer?.invalidate()
        model.preferences.save(demo: model.demo)
        model.storage?.flush()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
        if let wakeObserver { NSWorkspace.shared.notificationCenter.removeObserver(wakeObserver) }
    }

    private func registerShortcuts() {
        let shortcut = GlobalShortcut(preference: model.preferences.shortcut)
        hotkeys.register(shortcut, stackEnabled: model.preferences.stackShortcutEnabled)
        model.shortcutStatus = hotkeys.primaryAvailable ? shortcut.label : "⌃⌥⌘V"
        if !hotkeys.primaryAvailable && !model.demo { model.notify(L("Shortcut used by another app · fallback: ⌃⌥⌘V")) }
        if model.preferences.stackShortcutEnabled && !hotkeys.stackAvailable { model.notify(L("⌘⇧C is already used by another app. The queue is available from the shelf.")) }
    }

    private func applyAppearance() {
        let appearance = model.preferences.appearance
        NSApp.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = ScreenPlacement.screen(target: model.preferences.displayTarget, screens: NSScreen.screens, pointer: mouse, current: panel.isVisible ? panel.screen : nil)
        let frame = (screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        // The library is the shelf grown upwards: same width, same bottom edge. From the column, it grows out of the column.
        let shelf = min(frame.height - 30, model.preferences.panelHeight)
        let height = model.expanded ? max(shelf, min(frame.height - 30, max(640, frame.height * 0.8))) : shelf
        var target = NSRect(x: frame.minX + 12, y: frame.minY + 10, width: max(600, frame.width - 24), height: height)
        if model.columnShown { target = compactFrame(in: frame) }
        let animate = panel.isVisible && (shownExpanded != model.expanded || shownColumn != model.columnShown) && !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        shownExpanded = model.expanded; shownColumn = model.columnShown
        guard animate else { panel.setFrame(target, display: true); return }
        NSAnimationContext.runAnimationGroup { context in
            context.duration = 0.34
            context.timingFunction = CAMediaTimingFunction(controlPoints: 0.2, 0.9, 0.25, 1)
            panel.animator().setFrame(target, display: true)
        }
    }

    /// The compact window, at its saved place: a share of the room the screen leaves it, so it lands at the same spot on any screen.
    private func compactFrame(in frame: NSRect) -> NSRect {
        CompactPlacement.frame(position: model.preferences.compactPosition, rows: model.preferences.compactCount, in: frame)
    }

    /// After the compact window is dragged, already snapped while moving: its place is kept for next time.
    private func compactMoved() {
        guard model.columnShown, let screen = panel.screen else { return }
        model.preferences.compactPosition = CompactPlacement.position(of: panel.frame, in: screen.visibleFrame)
        model.preferencesChanged()
    }

    private func openLibraryFromColumn() {
        guard model.columnShown else { return }
        setExpanded(true)
    }

    private func setExpanded(_ value: Bool) {
        guard model.expanded != value else { return }
        let reduce = NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        withAnimation(reduce ? .easeOut(duration: 0.15) : .spring(duration: 0.34, bounce: 0.12)) { model.expanded = value }
    }

    /// Space on the shelf: a floating preview anchored above the cursor card, following the selection.
    private func updateQuickLook() {
        guard model.quickLook, panel.isVisible, !model.expanded, model.selected != nil, let screen = panel.screen else {
            if let quickLookPanel { panel.removeChildWindow(quickLookPanel); quickLookPanel.orderOut(nil) }
            if model.quickLook && (model.selected == nil || !panel.isVisible || model.expanded) { model.quickLook = false }
            return
        }
        if quickLookPanel == nil {
            let preview = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
            preview.isOpaque = false; preview.backgroundColor = .clear; preview.hasShadow = true
            preview.level = .floating; preview.hidesOnDeactivate = false; preview.isReleasedWhenClosed = false
            preview.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
            preview.contentView = NSHostingView(rootView: QuickLookView(model: model))
            quickLookPanel = preview
        }
        guard let preview = quickLookPanel else { return }
        let size = NSSize(width: 760, height: 480)
        let card = model.cursorFrame == .zero ? NSRect(x: panel.frame.width / 2, y: 0, width: 0, height: 0) : model.cursorFrame
        let bounds = screen.visibleFrame
        var x = min(max(panel.frame.minX + card.midX - size.width / 2, bounds.minX + 8), bounds.maxX - size.width - 8)
        var y = min(panel.frame.maxY + 10, bounds.maxY - size.height - 8)
        if model.columnShown {
            // Beside the compact window, on the side with more room.
            x = panel.frame.midX > bounds.midX ? max(bounds.minX + 8, panel.frame.minX - size.width - 10) : min(bounds.maxX - size.width - 8, panel.frame.maxX + 10)
            y = min(max(panel.frame.midY - size.height / 2, bounds.minY + 8), bounds.maxY - size.height - 8)
        }
        preview.setFrame(NSRect(x: x, y: y, width: size.width, height: size.height), display: true)
        if preview.parent == nil { panel.addChildWindow(preview, ordered: .above) }
        preview.orderFront(nil)
    }

    private func show() {
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier { previousApplication = front }
        model.accessibilityGranted = AXIsProcessTrusted()
        model.displayTime = Date()
        // Each opening starts on the history: that is where the latest copy is.
        if model.board != "history" { model.board = "history" }
        model.query = ""
        model.snippetForm = nil
        model.renamingID = nil
        model.snippetEditor = nil
        model.expanded = false
        model.searchFocused = false
        model.resetSelection()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
    }

    private func hide() {
        guard panel.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        model.searchFocused = false
        model.quickLook = false
        panel.orderOut(nil)
    }

    private func toggle() { panel.isVisible ? hide() : show() }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        if event.type == .keyUp { return handleKeyUp(event) }
        guard event.window === panel, panel.isVisible, panel.attachedSheet == nil, NSApp.modalWindow == nil else { return event }
        // The snippet form keeps typing, Return and Tab for its fields; Esc closes it.
        if model.snippetForm != nil {
            if event.keyCode == 53 { model.snippetForm = nil; return nil }
            return event
        }
        if model.snippetEditor != nil {
            if event.keyCode == 53 { model.snippetEditor = nil; return nil }
            return event
        }
        // While a card's name is edited, keys go to its field; Escape leaves the name unchanged.
        if model.renamingID != nil {
            if event.keyCode == 53 { model.renamingID = nil; return nil }
            return event
        }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let editing = (panel.firstResponder as? NSTextView)?.isFieldEditor == true || model.searchFocused
        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if command {
            switch character {
            case ",": openSettings(); return nil
            case "f": model.searchFocused = true; return nil
            case "n":
                if shift { openLibraryFromColumn(); model.createCollection() } else { newText() }
                return nil
            case "t": model.preferences.captureEnabled.toggle(); model.preferencesChanged(); return nil
            case "e": model.inspector = model.selected; return nil
            // The compact window is too small to rename or make a snippet: these open the library first.
            case "r": if model.remotePeer == nil { openLibraryFromColumn(); model.renamingID = model.selected?.id }; return nil
            case "s": if model.remotePeer == nil, let id = model.selected?.id { openLibraryFromColumn(); model.renamingID = nil; model.snippetEditor = id }; return nil
            case "d": model.toggleFavorite(); return nil
            case "+", "=": if !model.columnShown { model.zoomCards(0.05) }; return nil
            case "-": if !model.columnShown { model.zoomCards(-0.05) }; return nil
            case "z" where !editing: model.undoDelete(); return nil
            case "a" where !editing: if !model.columnShown { model.selection = Set(model.filtered.map(\.id)) }; return nil
            case "c" where !editing: model.paste(copyOnly: true); return nil
            case "q": NSApp.terminate(nil); return nil
            default:
                if let index = Self.quickPasteIndex(event), model.filtered.indices.contains(index) {
                    model.paste([model.filtered[index]], plain: shift); return nil
                }
            }
            // The compact window shows the history only: there is no board to switch to.
            if (event.keyCode == 123 || event.keyCode == 124) && model.columnShown { return nil }
            if command && shift && (event.keyCode == 36 || event.keyCode == 76) && model.columnShown { return nil }
            if event.keyCode == 123 || event.keyCode == 124 {
                let boards = model.boards
                let current = boards.firstIndex(of: model.board) ?? 0
                model.board = boards[(current + Localization.step(rightArrow: event.keyCode == 124) + boards.count) % boards.count]
                return nil
            }
        }
        // The side column is a vertical list: ↑ and ↓ move through it.
        // While searching too: the column has no other use for them, and Return pastes the chosen copy.
        // ↑ on the first copy opens the library.
        if model.columnShown && (event.keyCode == 125 || event.keyCode == 126) {
            if event.keyCode == 126 && !event.isARepeat && model.filtered.first.map({ $0.id == model.cursor }) != false { setExpanded(true) }
            else { model.move(event.keyCode == 125 ? 1 : -1) }
            return nil
        }
        if model.columnShown && editing && (event.keyCode == 36 || event.keyCode == 76) && !command {
            model.paste(plain: shift)
            return nil
        }
        switch event.keyCode {
        case 53:
            if model.quickLook { model.quickLook = false }
            else if !model.query.isEmpty { model.query = ""; model.searchFocused = false; panel.makeFirstResponder(nil) }
            else { hide() }
            return nil
        case 36, 76:
            if command && shift { model.enqueue() }
            else if editing { model.searchFocused = false; panel.makeFirstResponder(nil) }
            else { model.paste(plain: shift) }
            return nil
        case 123 where !editing, 124 where !editing:
            model.move(Localization.step(rightArrow: event.keyCode == 124), extend: shift); return nil
        case 125 where editing:
            model.searchFocused = false; panel.makeFirstResponder(nil); return nil
        case 126 where !editing:
            if command, let first = model.filtered.first { model.select(first.id) }
            else if model.expanded { model.moveRow(-1, extend: shift) }
            else if !event.isARepeat { setExpanded(true) }
            return nil
        case 125 where !editing:
            // In the library a tap moves down a row and holding ↓ goes back to the shelf.
            if command, let last = model.filtered.last { model.select(last.id) }
            else if event.isARepeat { }
            else if model.expanded {
                // In the library ↓ waits: released quickly it moves down a row, held it returns to the shelf.
                let hold = DispatchWorkItem { [weak self] in self?.downPress = nil; self?.setExpanded(false) }
                downPress?.cancel(); downPress = hold
                DispatchQueue.main.asyncAfter(deadline: .now() + 0.35, execute: hold)
            } else { hide() }
            return nil
        case 48:
            model.searchFocused.toggle()
            if !model.searchFocused { panel.makeFirstResponder(nil) }
            return nil
        case 49 where !editing:
            if model.expanded { model.inspector = model.selected } else { model.quickLook.toggle() }
            return nil
        case 51 where !editing && command, 117 where !editing && command:
            // ⌘ is required: a lone ⌫ deleted cards by accident.
            model.remove(); return nil
        case 51 where !editing, 117 where !editing:
            return nil
        default: break
        }
        if !editing && !command && !flags.contains(.control) && !flags.contains(.option) && event.specialKey == nil, let text = event.characters, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }), !text.isEmpty {
            // Typed into the field once it has focus: focusing selects its text, so a letter added before would be replaced by the next one.
            model.searchFocused = true
            DispatchQueue.main.async { [weak self] in
                guard let self else { return }
                if let editor = self.panel.firstResponder as? NSTextView, editor.isFieldEditor { editor.insertText(text, replacementRange: NSRange(location: (editor.string as NSString).length, length: 0)) }
                else { self.model.query += text }
            }
            return nil
        }
        return event
    }

    private func handleKeyUp(_ event: NSEvent) -> NSEvent? {
        guard event.keyCode == 125, let hold = downPress else { return event }
        hold.cancel(); downPress = nil
        model.moveRow(1, extend: event.modifierFlags.contains(.shift))
        return nil
    }

    private func newText() {
        model.inspector = Clip(kind: .text, text: "")
    }

    static func quickPasteIndex(_ event: NSEvent) -> Int? {
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        guard flags.contains(.command), !flags.contains(.option), !flags.contains(.control) else { return nil }
        return [UInt16(18), 19, 20, 21, 23, 22, 26, 28, 25].firstIndex(of: event.keyCode)
    }

    private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 780, height: 680), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = L("Encore Settings")
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        panel.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func openInspector(_ clip: Clip) {
        guard allowDiscardInspector() else { return }
        inspectorDirty = false
        if inspectorWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 740, height: 700), styleMask: [.titled, .closable, .miniaturizable, .resizable], backing: .buffered, defer: false)
            window.contentMinSize = NSSize(width: 560, height: 520)
            window.isReleasedWhenClosed = false
            window.delegate = self
            window.center()
            inspectorWindow = window
        }
        inspectorWindow?.title = L("Preview — \(clip.displayTitle)")
        inspectorWindow?.contentView = NSHostingView(rootView: InspectorView(model: model, clip: clip, onClose: { [weak self] in self?.inspectorWindow?.performClose(nil) }, onDirtyChange: { [weak self] dirty in self?.inspectorDirty = dirty }))
        panel.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        inspectorWindow?.makeKeyAndOrderFront(nil)
    }

    private func allowDiscardInspector() -> Bool {
        guard inspectorDirty else { return true }
        let alert = NSAlert()
        alert.messageText = L("Discard changes?")
        alert.informativeText = L("The original content is kept. Your unsaved changes will be lost.")
        alert.addButton(withTitle: L("Keep editing")); alert.addButton(withTitle: L("Discard"))
        guard alert.runModal() == .alertSecondButtonReturn else { return false }
        inspectorDirty = false
        return true
    }

    func windowShouldClose(_ sender: NSWindow) -> Bool { sender !== inspectorWindow || allowDiscardInspector() }

    func windowWillClose(_ notification: Notification) {
        guard let window = notification.object as? NSWindow, window === inspectorWindow else { return }
        inspectorWindow = nil; inspectorDirty = false; model.inspector = nil
        positionPanel()
        panel.makeKeyAndOrderFront(nil); panel.makeFirstResponder(nil)
    }

    func applicationShouldTerminate(_ sender: NSApplication) -> NSApplication.TerminateReply { allowDiscardInspector() ? .terminateNow : .terminateCancel }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = Self.statusImage
        statusItem.button?.toolTip = L("Encore — your clipboard history")
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    /// The app icon reduced to a template: an outlined back card and a solid front card with the arrow cut out.
    private static let statusImage: NSImage = {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: false) { _ in
            let card = NSBezierPath(roundedRect: NSRect(x: -4.6, y: -5.6, width: 9.2, height: 11.2), xRadius: 2, yRadius: 2)
            NSGraphicsContext.saveGraphicsState()
            let back = NSAffineTransform()
            back.translateX(by: 7.2, yBy: 9.6); back.rotate(byDegrees: 14); back.concat()
            card.lineWidth = 1.4
            NSColor.black.setStroke(); card.stroke()
            NSGraphicsContext.restoreGraphicsState()
            NSGraphicsContext.saveGraphicsState()
            let front = NSAffineTransform()
            front.translateX(by: 10.6, yBy: 8.2); front.rotate(byDegrees: -7); front.concat()
            // Clear a gap around the front card so the outline behind it reads as a separate card.
            let gap = card.copy() as! NSBezierPath
            gap.lineWidth = 2.6
            NSGraphicsContext.current?.compositingOperation = .clear
            gap.stroke()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.black.setFill(); card.fill()
            // The u-turn arrow, drawn as a path so it stays crisp at menu-bar size.
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: -0.7, y: 4.2)); arrow.line(to: NSPoint(x: -3.1, y: 1.8)); arrow.line(to: NSPoint(x: -0.7, y: -0.6))
            arrow.move(to: NSPoint(x: -2.9, y: 1.8)); arrow.line(to: NSPoint(x: 1.2, y: 1.8))
            arrow.appendArc(withCenter: NSPoint(x: 1.2, y: -0.3), radius: 2.1, startAngle: 90, endAngle: -90, clockwise: true)
            arrow.line(to: NSPoint(x: -0.8, y: -2.4))
            arrow.lineWidth = 1; arrow.lineCapStyle = .round; arrow.lineJoinStyle = .round
            NSGraphicsContext.current?.compositingOperation = .clear
            arrow.stroke()
            NSGraphicsContext.restoreGraphicsState()
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "encore"
        return image
    }()

    @objc private func statusClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: L("Open Encore"), action: #selector(openBoard), keyEquivalent: "")
            menu.addItem(withTitle: model.preferences.captureEnabled ? L("Pause capture") : L("Resume capture"), action: #selector(toggleCapture), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: L("Settings…"), action: #selector(settingsAction), keyEquivalent: "")
            if Updates.shared.available { menu.addItem(withTitle: L("Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "") }
            menu.addItem(withTitle: L("About Encore"), action: #selector(about), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: L("Quit Encore"), action: #selector(quit), keyEquivalent: "")
            for item in menu.items { item.target = self }
            statusItem.menu = menu
            menu.delegate = self
            statusItem.button?.performClick(nil)
        } else { toggle() }
    }

    func menuDidClose(_ menu: NSMenu) { statusItem.menu = nil }
    @objc private func openBoard() { show() }
    @objc private func toggleCapture() { model.preferences.captureEnabled.toggle(); model.preferencesChanged() }
    @objc private func settingsAction() { openSettings() }
    @objc private func checkForUpdates() { Updates.shared.check() }
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "encore", .applicationVersion: Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "", .credits: Self.aboutCredits])
    }
    /// Centered like the rest of the panel; plain credits are left-aligned.
    private static var aboutCredits: NSAttributedString {
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = .center
        return NSAttributedString(string: L("Your clipboard. Yours to keep.\nNative, local, and open source.\nMIT license · github.com/Kamasoutra/encore") + "\n" + L("Support encore") + " · github.com/sponsors/Kamasoutra · ko-fi.com/kamasoutra" + "\n\nSeti UI icons © Jesse Weed · MIT",
                                  attributes: [.paragraphStyle: paragraph, .font: NSFont.systemFont(ofSize: NSFont.smallSystemFontSize), .foregroundColor: NSColor.labelColor])
    }

    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        let aboutItem = app.addItem(withTitle: L("About Encore"), action: #selector(about), keyEquivalent: "")
        aboutItem.target = self
        if Updates.shared.available { app.addItem(withTitle: L("Check for Updates…"), action: #selector(checkForUpdates), keyEquivalent: "").target = self }
        app.addItem(.separator())
        let settings = app.addItem(withTitle: L("Settings…"), action: #selector(settingsAction), keyEquivalent: ",")
        settings.target = self
        app.addItem(.separator())
        app.addItem(withTitle: L("Quit Encore"), action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: L("Edit menu"))
        for (title, action, key) in [(L("Undo"), "undo:", "z"), (L("Cut"), "cut:", "x"), (L("Copy"), "copy:", "c"), (L("Paste"), "paste:", "v"), (L("Select all"), "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
