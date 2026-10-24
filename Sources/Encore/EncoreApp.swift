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
    private var aboutWindow: NSWindow?

    func applicationDidFinishLaunching(_ notification: Notification) {
        let demo = CommandLine.arguments.contains("--demo")
        model = AppModel(demo: demo)
        model.togglePanel = { [weak self] in self?.toggle() }
        model.dismissPanel = { [weak self] in self?.hide() }
        model.showSettings = { [weak self] in self?.openSettings() }
        model.activateTarget = { [weak self] in self?.previousApplication }
        model.updateShortcuts = { [weak self] in self?.registerShortcuts() }
        model.updateAppearance = { [weak self] in self?.applyAppearance() }
        model.resizePanel = { [weak self] in self?.positionPanel() }
        panel = EncorePanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "Encore"
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
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            let passThrough = MainActor.assumeIsolated {
                guard let self else { return true }
                return self.handleKey(event) != nil
            }
            return passThrough ? event : nil
        }
        mouseMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, self.panel.isVisible, self.panel.attachedSheet == nil, NSApp.modalWindow == nil else { return }
                self.hide()
            }
        }
        activationObserver = NSWorkspace.shared.notificationCenter.addObserver(forName: NSWorkspace.didActivateApplicationNotification, object: nil, queue: .main) { [weak self] note in
            MainActor.assumeIsolated {
                guard let self, let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication, app.bundleIdentifier != Bundle.main.bundleIdentifier else { return }
                self.previousApplication = app
                if self.panel.isVisible { self.hide() }
            }
        }
        screenObserver = NotificationCenter.default.addObserver(forName: NSApplication.didChangeScreenParametersNotification, object: nil, queue: .main) { [weak self] _ in
            MainActor.assumeIsolated { if self?.panel.isVisible == true { self?.positionPanel() } }
        }
        permissionTimer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.model.accessibilityGranted = AXIsProcessTrusted() }
        }
        model.clipboard.start()
        if demo || CommandLine.arguments.contains("--show") || !UserDefaults.standard.bool(forKey: "hasLaunched") {
            if !demo { UserDefaults.standard.set(true, forKey: "hasLaunched") }
            show()
        }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool { show(); return true }

    func applicationWillTerminate(_ notification: Notification) {
        model.clipboard.stop(); model.stackTap.stop(); hotkeys.stop()
        permissionTimer?.invalidate()
        model.preferences.save(demo: model.demo)
        model.storage?.flush()
        if let keyMonitor { NSEvent.removeMonitor(keyMonitor) }
        if let mouseMonitor { NSEvent.removeMonitor(mouseMonitor) }
        if let activationObserver { NSWorkspace.shared.notificationCenter.removeObserver(activationObserver) }
        if let screenObserver { NotificationCenter.default.removeObserver(screenObserver) }
    }

    private func registerShortcuts() {
        hotkeys.register(alternate: model.preferences.shortcut == "commandOptionV")
        model.shortcutStatus = hotkeys.primaryAvailable ? (model.preferences.shortcut == "commandOptionV" ? "⌘⌥V" : "⌘⇧V") : "⌃⌥⌘V"
        if !hotkeys.primaryAvailable { model.notify("Raccourci occupé par une autre app · secours : ⌃⌥⌘V") }
    }

    private func applyAppearance() {
        let appearance = model.preferences.appearance
        NSApp.appearance = appearance == "dark" ? NSAppearance(named: .darkAqua) : appearance == "light" ? NSAppearance(named: .aqua) : nil
    }

    private func positionPanel() {
        let mouse = NSEvent.mouseLocation
        let screen = panel.isVisible ? panel.screen : NSScreen.screens.first { $0.frame.contains(mouse) }
        let frame = (screen ?? NSScreen.main ?? NSScreen.screens[0]).visibleFrame
        let width = max(600, frame.width - 24)
        let height = min(frame.height - 30, model.preferences.panelHeight)
        panel.setFrame(NSRect(x: frame.minX + 12, y: frame.minY + 10, width: width, height: height), display: true)
    }

    private func show() {
        if let front = NSWorkspace.shared.frontmostApplication, front.bundleIdentifier != Bundle.main.bundleIdentifier { previousApplication = front }
        model.accessibilityGranted = AXIsProcessTrusted()
        model.query = ""
        model.searchFocused = false
        model.resetSelection()
        positionPanel()
        panel.makeKeyAndOrderFront(nil)
        panel.makeFirstResponder(nil)
    }

    private func hide() {
        guard panel.attachedSheet == nil, NSApp.modalWindow == nil else { return }
        model.searchFocused = false
        panel.orderOut(nil)
    }

    private func toggle() { panel.isVisible ? hide() : show() }

    private func handleKey(_ event: NSEvent) -> NSEvent? {
        guard event.window === panel, panel.isVisible, panel.attachedSheet == nil, NSApp.modalWindow == nil else { return event }
        let flags = event.modifierFlags.intersection([.command, .shift, .option, .control])
        let command = flags.contains(.command)
        let shift = flags.contains(.shift)
        let editing = panel.firstResponder is NSTextView
        let character = event.charactersIgnoringModifiers?.lowercased() ?? ""
        if command {
            switch character {
            case ",": openSettings(); return nil
            case "f": model.searchFocused = true; return nil
            case "n":
                if shift { model.createCollection() } else { newText() }
                return nil
            case "t": model.preferences.captureEnabled.toggle(); model.preferencesChanged(); return nil
            case "e", "r": model.inspector = model.selected; return nil
            case "d": model.toggleFavorite(); return nil
            case "z" where !editing: model.undoDelete(); return nil
            case "a" where !editing: model.selection = Set(model.filtered.map(\.id)); return nil
            case "c" where !editing: model.paste(copyOnly: true); return nil
            case "q": NSApp.terminate(nil); return nil
            default:
                if let number = Int(character), (1...9).contains(number), model.filtered.count >= number {
                    model.paste([model.filtered[number - 1]], plain: shift); return nil
                }
            }
            if event.keyCode == 123 || event.keyCode == 124 {
                let boards = ["history", "favorites"] + model.library.collections.map { $0.id.uuidString }
                let current = boards.firstIndex(of: model.board) ?? 0
                model.board = boards[(current + (event.keyCode == 124 ? 1 : boards.count - 1)) % boards.count]
                return nil
            }
        }
        switch event.keyCode {
        case 53:
            if !model.query.isEmpty { model.query = ""; model.searchFocused = false; panel.makeFirstResponder(nil) }
            else { hide() }
            return nil
        case 36, 76:
            if command && shift { model.enqueue() }
            else if editing { model.searchFocused = false; panel.makeFirstResponder(nil) }
            else { model.paste(plain: shift) }
            return nil
        case 123 where !editing, 124 where !editing:
            model.move(event.keyCode == 124 ? 1 : -1, extend: shift); return nil
        case 125 where editing:
            model.searchFocused = false; panel.makeFirstResponder(nil); return nil
        case 48:
            model.searchFocused.toggle()
            if !model.searchFocused { panel.makeFirstResponder(nil) }
            return nil
        case 49 where !editing:
            model.inspector = model.selected; return nil
        case 51 where !editing, 117 where !editing:
            model.remove(); return nil
        default: break
        }
        if !editing && !command && !flags.contains(.control) && !flags.contains(.option), let text = event.characters, text.unicodeScalars.allSatisfy({ !CharacterSet.controlCharacters.contains($0) }), !text.isEmpty {
            model.query += text
            model.searchFocused = true
            return nil
        }
        return event
    }

    private func newText() {
        model.inspector = Clip(kind: .text, text: "")
    }

    private func openSettings() {
        if settingsWindow == nil {
            let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 600, height: 590), styleMask: [.titled, .closable, .miniaturizable], backing: .buffered, defer: false)
            window.title = "Réglages d’Encore"
            window.isReleasedWhenClosed = false
            window.contentView = NSHostingView(rootView: SettingsView(model: model))
            window.center()
            settingsWindow = window
        }
        panel.orderOut(nil)
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    private func installStatusItem() {
        statusItem = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        statusItem.button?.image = NSImage(systemSymbolName: "square.on.square", accessibilityDescription: "Encore")
        statusItem.button?.toolTip = "Encore — votre historique du presse-papiers"
        statusItem.button?.target = self
        statusItem.button?.action = #selector(statusClick)
        statusItem.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
    }

    @objc private func statusClick() {
        if NSApp.currentEvent?.type == .rightMouseUp {
            let menu = NSMenu()
            menu.addItem(withTitle: "Ouvrir Encore", action: #selector(openBoard), keyEquivalent: "")
            menu.addItem(withTitle: model.preferences.captureEnabled ? "Mettre la capture en pause" : "Reprendre la capture", action: #selector(toggleCapture), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Réglages…", action: #selector(settingsAction), keyEquivalent: "")
            menu.addItem(withTitle: "À propos d’Encore", action: #selector(about), keyEquivalent: "")
            menu.addItem(.separator())
            menu.addItem(withTitle: "Quitter Encore", action: #selector(quit), keyEquivalent: "")
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
    @objc private func quit() { NSApp.terminate(nil) }
    @objc private func about() {
        NSApp.activate(ignoringOtherApps: true)
        NSApp.orderFrontStandardAboutPanel(options: [.applicationName: "Encore", .applicationVersion: "0.1.0", .credits: NSAttributedString(string: "Votre presse-papiers. Pour de bon.\nApplication native, locale et open source.\nLicence MIT · github.com/Kamasoutra/encore")])
    }

    private func installMenu() {
        let main = NSMenu()
        let appItem = NSMenuItem()
        let app = NSMenu()
        let aboutItem = app.addItem(withTitle: "À propos d’Encore", action: #selector(about), keyEquivalent: "")
        aboutItem.target = self
        app.addItem(.separator())
        let settings = app.addItem(withTitle: "Réglages…", action: #selector(settingsAction), keyEquivalent: ",")
        settings.target = self
        app.addItem(.separator())
        app.addItem(withTitle: "Quitter Encore", action: #selector(NSApplication.terminate(_:)), keyEquivalent: "q")
        appItem.submenu = app
        main.addItem(appItem)
        let editItem = NSMenuItem()
        let edit = NSMenu(title: "Édition")
        for (title, action, key) in [("Annuler", "undo:", "z"), ("Couper", "cut:", "x"), ("Copier", "copy:", "c"), ("Coller", "paste:", "v"), ("Tout sélectionner", "selectAll:", "a")] { edit.addItem(withTitle: title, action: Selector(action), keyEquivalent: key) }
        editItem.submenu = edit
        main.addItem(editItem)
        NSApp.mainMenu = main
    }
}
