import AppKit
import Carbon
import SwiftUI
import ServiceManagement
import EncoreCore

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, privacy, retention, data, peers, shortcuts
    var id: String { rawValue }
    var title: String {
        switch self { case .general: L("General"); case .privacy: L("Privacy"); case .retention: L("Retention Rules"); case .data: L("Data"); case .peers: L("Other Macs"); case .shortcuts: L("Shortcuts") }
    }
    var symbol: String {
        switch self { case .general: "slider.horizontal.3"; case .privacy: "hand.raised"; case .retention: "clock.arrow.circlepath"; case .data: "externaldrive"; case .peers: "laptopcomputer"; case .shortcuts: "keyboard" }
    }
    var subtitle: String {
        switch self {
        case .general: L("A clipboard that fits the way you work.")
        case .privacy: L("Choose what Encore keeps. Everything stays on this Mac.")
        case .retention: L("Set retention by size and type. The first matching rule wins.")
        case .data: L("Retention, backups, and storage usage.")
        case .peers: L("Find what you copy on your other Macs. Direct over the local network, encrypted, no account.")
        case .shortcuts: L("Find, select, and paste. All from the keyboard.")
        }
    }
}

/// Launch at login relies on SMAppService, so macOS 12 does not offer it.
enum LoginItem {
    static var available: Bool { if #available(macOS 13, *) { return true } else { return false } }
    static var enabled: Bool {
        if #available(macOS 13, *) { return SMAppService.mainApp.status == .enabled }
        return false
    }
    static func set(_ enabled: Bool) throws {
        guard #available(macOS 13, *) else { return }
        if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @ObservedObject private var updates = Updates.shared
    // `--settings privacy` opens on that section, for screenshots.
    @State private var shortcutRefused = false
    @State private var section = CommandLine.arguments.drop { $0 != "--settings" }.dropFirst().first.flatMap(SettingsSection.init(rawValue:)) ?? .general
    @State private var launchAtLogin = LoginItem.enabled

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Divider()
            VStack(alignment: .leading, spacing: 0) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(section.title).font(.system(size: 23, weight: .semibold))
                    Text(section.subtitle).font(.system(size: 13)).foregroundStyle(.secondary)
                }.padding(.horizontal, 25).padding(.vertical, 23)
                Divider()
                Group {
                    switch section {
                    case .general: general
                    case .privacy: privacy
                    case .retention: RetentionSettingsView(model: model)
                    case .data: data
                    case .peers: peers
                    case .shortcuts: shortcuts
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if !model.status.isEmpty {
                    Text(model.status).font(.system(size: 12)).foregroundStyle(Palette.accent).padding(.horizontal, 24).padding(.vertical, 10)
                }
            }
        }.frame(width: 780, height: 680).font(.system(size: 13)).tint(Palette.accent)
            .localized()
            .background(Color(nsColor: .windowBackgroundColor))
            .onChanged(model.preferences) { _ in model.preferencesChanged() }
            .onAppear { model.refreshInstalledExclusions() }
            .sheet(isPresented: $model.pairingSheet, onDismiss: { model.closePairing() }) { PairingSheet(model: model) }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) { EncoreMark(size: 35); Text("encore").font(.system(size: 22, weight: .semibold)) }.padding(.horizontal, 7).padding(.top, 13)
            List(selection: Binding<SettingsSection?>(get: { section }, set: { if let value = $0 { section = value } })) {
                ForEach(SettingsSection.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 13))
                        .padding(.vertical, 4)
                        .tag(item)
                }
            }.listStyle(.sidebar).hiddenScrollBackground()
            Spacer()
            VStack(alignment: .leading, spacing: 10) {
                if updates.available { versionCard }
                starCard
                supportCard
                HStack {
                    Label(L("100% local"), systemImage: "lock.shield")
                    Spacer()
                    Link("GitHub ↗", destination: URL(string: "https://github.com/Kamasoutra/encore")!)
                }.font(.system(size: 11)).foregroundStyle(.secondary).padding(.horizontal, 4)
            }
        }.padding(15).frame(width: 175).background(.primary.opacity(0.025))
    }

    /// The version in use, and the newest one the feed offers, with a check that shows nothing unless there is an update.
    private var versionCard: some View {
        VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 4) {
                Text("encore \(Updates.current)").font(.system(size: 12, weight: .semibold))
                Spacer()
                if updates.probing { ProgressView().controlSize(.small).scaleEffect(0.6).frame(width: 16, height: 16) }
                else {
                    Button { updates.probe() } label: { Image(systemName: "arrow.clockwise").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(.borderless).foregroundStyle(.secondary).help(L("Check for Updates…"))
                }
            }
            Group {
                if updates.updateFound, let latest = updates.latest {
                    Button { updates.check() } label: { Label(L("\(latest) available"), systemImage: "arrow.down.circle.fill") }
                        .buttonStyle(.borderless).foregroundStyle(Palette.accent)
                } else if updates.probing {
                    Text(L("Checking…")).foregroundStyle(.secondary)
                } else if updates.latest != nil {
                    Label(L("Up to date"), systemImage: "checkmark.circle.fill").foregroundStyle(.green)
                } else {
                    Button(L("Check for Updates…")) { updates.probe() }.buttonStyle(.borderless).foregroundStyle(Palette.accent)
                }
            }.font(.system(size: 11, weight: .medium))
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
        .onAppear { updates.probeIfStale() }
    }

    /// Both ways to tip, side by side.
    private var supportCard: some View {
        VStack(alignment: .leading, spacing: 7) {
            Label { Text(L("Support encore")) } icon: { Image(systemName: "heart.fill").foregroundStyle(.pink) }
                .font(.system(size: 12, weight: .semibold))
            // One under the other: the sidebar is too narrow for both names side by side.
            VStack(spacing: 5) {
                supportLink("GitHub Sponsors", symbol: "heart", url: "https://github.com/sponsors/Kamasoutra")
                supportLink("Ko-fi", symbol: "cup.and.saucer", url: "https://ko-fi.com/kamasoutra")
            }
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(LinearGradient(colors: [Palette.accent.opacity(0.14), Color.pink.opacity(0.1)], startPoint: .topLeading, endPoint: .bottomTrailing), in: RoundedRectangle(cornerRadius: 10))
    }

    /// A star costs nothing: it has its own card, apart from the tips.
    private var starCard: some View {
        Link(destination: URL(string: "https://github.com/Kamasoutra/encore")!) {
            // Laid out like the support card: the symbol on the title line, the reason below at full width.
            VStack(alignment: .leading, spacing: 4) {
                Label { Text(L("Star on GitHub")) } icon: { Image(systemName: "star.fill").foregroundStyle(.yellow) }
                    .font(.system(size: 12, weight: .semibold))
                Text(L("Helps others find encore")).font(.system(size: 10.5)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true)
            }
            .padding(10).frame(maxWidth: .infinity, alignment: .leading)
            .background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).foregroundStyle(.primary)
    }

    private func supportLink(_ title: String, symbol: String, url: String) -> some View {
        Link(destination: URL(string: url)!) {
            HStack(spacing: 5) {
                Image(systemName: symbol).font(.system(size: 10, weight: .semibold)).frame(width: 13)
                Text(title).font(.system(size: 11, weight: .semibold)).lineLimit(1).fixedSize()
            }
            .padding(.horizontal, 7).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
                .background(.primary.opacity(0.08), in: Capsule())
        }.buttonStyle(.plain).foregroundStyle(.primary)
    }

    private var general: some View {
        SettingsForm {
            SettingsGroup(L("Direct paste")) {
                HStack {
                    Label(model.accessibilityGranted ? L("Direct paste allowed") : L("Manual paste active"), systemImage: model.accessibilityGranted ? "checkmark.shield.fill" : "exclamationmark.triangle.fill")
                        .foregroundStyle(model.accessibilityGranted ? Color.green : Color.orange)
                    Spacer()
                    if !model.accessibilityGranted {
                        Button(L("Check again")) { model.accessibilityGranted = AXIsProcessTrusted() }
                        Button(L("macOS Settings…")) { model.requestAccessibility() }.buttonStyle(.borderedProminent)
                    }
                }
                caption(L("Accessibility access enables direct and sequential paste. Without it, Encore copies the item for you to paste with ⌘V."))
                described(L("Off, they copy the item and bring it back to the top, ready to paste with ⌘V. A plain text copy leaves it in place.")) {
                    Toggle(L("Paste on Return and double-click"), isOn: $model.preferences.pasteDirectly)
                }
                if !model.accessibilityGranted {
                    caption(L("macOS has not authorized this version of Encore. If access was already granted, turn Encore off and on in Accessibility. If needed, remove the old entry and add the installed app. Ad-hoc signatures can invalidate access after an update."))
                }
            }
            SettingsGroup(L("Everyday use")) {
                Toggle(L("Save new clipboard items"), isOn: $model.preferences.captureEnabled).disabled(model.storage == nil || model.storageError != nil)
                if LoginItem.available {
                    Toggle(L("Launch at login"), isOn: $launchAtLogin).disabled(model.demo).onChanged(launchAtLogin) { value in
                        do { try LoginItem.set(value) }
                        catch { model.notify(L("Launch at login: \(error.localizedDescription)")); launchAtLogin = LoginItem.enabled }
                    }
                }
                HStack {
                    Text(L("Open Encore")); Spacer()
                    ShortcutRecorder(preference: $model.preferences.shortcut, refused: $shortcutRefused, suspend: { model.suspendShortcuts?() }, resume: { model.updateShortcuts?() })
                }
                if shortcutRefused { caption(L("Use ⌥ or ⌃, or ⌘ with ⇧, so that ⌘V and the shortcuts of your apps keep working.")) }
                caption(L("Active shortcut: \(model.shortcutStatus). Fallback: ⌃⌥⌘V."))
                Toggle(L("Use ⌘⇧C for the paste queue"), isOn: $model.preferences.stackShortcutEnabled)
                    .onChanged(model.preferences.stackShortcutEnabled) { _ in model.updateShortcuts?() }
                caption(L("Off by default to keep this shortcut available in other apps. The queue is also available from the shelf."))
            }
            SettingsGroup(L("Appearance")) {
                Picker(L("Language"), selection: $model.preferences.language) {
                    Text(L("Follow macOS")).tag("system")
                    ForEach(languages, id: \.self) { code in Text(languageLabel(code)).tag(code) }
                }
                Picker(L("Theme"), selection: $model.preferences.appearance) {
                    Text(L("System")).tag("system"); Text(L("Light")).tag("light"); Text(L("Dark")).tag("dark")
                }
                Toggle(L("Compact cards"), isOn: $model.preferences.compact)
                percentageControl(L("Card size"), symbol: "rectangle.grid.1x2", value: $model.preferences.cardScale, range: 0.75...1.5)
                caption(L("Drag the top handle to resize the shelf. Use ⌘+ and ⌘− to resize cards."))
            }
            SettingsGroup(L("Display")) {
                Picker(L("Layout"), selection: $model.preferences.placement) {
                    Text(L("Shelf at the bottom")).tag("bottom")
                    Text(L("Compact window")).tag("compact")
                }.onChanged(model.preferences.placement) { _ in model.resizePanel?() }
                if model.preferences.placement == "compact" {
                    Stepper(value: $model.preferences.compactCount, in: 3...10) {
                        HStack { Text(L("Copies shown")); Spacer(); Text(Localization.number(model.preferences.compactCount)).monospacedDigit().foregroundStyle(.secondary) }
                    }.onChanged(model.preferences.compactCount) { _ in model.resizePanel?() }
                }
                caption(L("The compact window lists your latest copies. Drag it by its title to move it: it snaps to the corners, the middle of each edge and the center, and opens there next time."))
                Picker(L("Show shelf on"), selection: $model.preferences.displayTarget) {
                    Text(L("Current display · at pointer")).tag("active")
                    Text(L("macOS primary display")).tag("primary")
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        if let id = ScreenPlacement.identifier(screen) { Text(screen.localizedName).tag(id) }
                    }
                    if !["active", "primary"].contains(model.preferences.displayTarget), !NSScreen.screens.contains(where: { ScreenPlacement.identifier($0) == model.preferences.displayTarget }) {
                        Text(L("Display disconnected · using primary")).tag(model.preferences.displayTarget)
                    }
                }.onChanged(model.preferences.displayTarget) { _ in model.resizePanel?() }
                caption(L("Encore remembers this display. If disconnected, it uses the primary display until it returns."))
            }
            SettingsGroup(L("Sound feedback")) {
                // One row: as two, the form squeezes the volume between the switch and the themes until the slider is cut off.
                VStack(spacing: 8) {
                    Toggle(L("Play sounds on capture and paste"), isOn: $model.preferences.soundsEnabled)
                    percentageControl(L("Volume"), symbol: "speaker.wave.2", value: $model.preferences.soundVolume, range: 0...1)
                }
                ForEach(SoundTheme.allCases) { theme in soundThemeRow(theme) }
                if model.preferences.soundTheme == .custom {
                    soundFileRow(L("On copy"), path: model.preferences.captureSoundPath, action: .capture)
                    soundFileRow(L("On paste"), path: model.preferences.pasteSoundPath, action: .paste)
                }
            }
        }
    }

    private var privacy: some View {
        SettingsForm {
            SettingsGroup(L("Capture")) {
                Toggle(L("Ignore confidential and transient content"), isOn: $model.preferences.ignoreSensitive)
                Toggle(L("Recognize text in images"), isOn: $model.preferences.recognizeImages)
                caption(L("OCR runs on this Mac. No account or telemetry. Links are not loaded in the background."))
            }
            SettingsGroup(L("Excluded apps")) {
                VStack(spacing: 0) {
                    if model.installedExcludedBundleIDs.isEmpty { Text(L("No installed apps are excluded")).foregroundStyle(.secondary).padding(.vertical, 8) }
                    ForEach(model.installedExcludedBundleIDs, id: \.self) { bundle in
                        let app = ApplicationCatalog.app(bundle)
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 27, height: 27)
                            Text(app.name).font(.system(size: 13))
                            Spacer()
                            Button(role: .destructive) { model.removeExcludedApp(bundle) } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }.buttonStyle(.plain).help(L("Stop excluding \(app.name)"))
                        }.padding(.vertical, 8).help(bundle)
                        if bundle != model.installedExcludedBundleIDs.last { Divider() }
                    }
                }
                Button { addExcludedApp() } label: { Label(L("Add an app…"), systemImage: "plus") }
                caption(L("Installed password managers are excluded automatically. New installations are detected. Apps you remove will not be excluded again automatically."))
            }
            SettingsGroup(L("Native screenshots")) {
                Toggle(L("Import newly saved screenshots"), isOn: Binding(get: { model.preferences.importScreenshots }, set: { value in
                    if value { chooseScreenshotFolder() } else { model.preferences.importScreenshots = false }
                }))
                if model.preferences.importScreenshots {
                    HStack {
                        Label((model.preferences.screenshotFolder as NSString?)?.lastPathComponent ?? L("Desktop"), systemImage: "folder")
                        Spacer()
                        Button(L("Change…")) { chooseScreenshotFolder() }
                    }
                    Toggle(L("Also copy to the clipboard"), isOn: $model.preferences.copyScreenshotsToClipboard)
                    caption(L("Paste the screenshot with ⌘V. Anything copied after the screenshot takes priority."))
                }
                if model.preferences.importScreenshots && model.preferences.copyScreenshotsToClipboard {
                    caption(L("New screenshots in this folder join your history. The folder is watched while Encore and capture are active. Existing screenshots are not imported."))
                } else {
                    caption(L("New screenshots in this folder join your history without changing the clipboard. The folder is watched while Encore and capture are active. Existing screenshots are not imported."))
                }
            }
            caption(L("Some browser extensions do not mark secrets. Exclude their browser if needed."))
        }
    }

    private var data: some View {
        SettingsForm {
            SettingsGroup(L("Retention")) {
                InfoRow(L("Retention without a rule"), value: model.preferences.retentionDays == 0 ? L("Forever") : L("\(model.preferences.retentionDays) days"))
                Button { section = .retention } label: { Label(L("Configure retention rules"), systemImage: "clock.arrow.circlepath") }
                Picker(L("Items without a matching rule"), selection: $model.preferences.historyLimit) {
                    Text(L("Up to 500")).tag(500); Text(L("Up to 2,000")).tag(2000); Text(L("Up to 10,000")).tag(10000); Text(L("Unlimited items")).tag(0)
                }
                Picker(L("Embedded content budget"), selection: $model.preferences.storageLimitMB) {
                    Text(L("100 MiB")).tag(100); Text(L("500 MiB")).tag(500); Text(L("2,000 MiB")).tag(2000)
                }
                caption(L("Favorites, collections, and rule-managed items bypass the item-count limit. A full budget blocks new copies. Maximum embedded content per copy: 25 MiB."))
            }
            SettingsGroup(L("Local library")) {
                if let error = model.storageError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button(L("Reload library…")) { model.reloadStorage() }
                }
                InfoRow(L("Items"), value: Localization.number(model.library.clips.count))
                InfoRow(L("Stored content"), value: Localization.bytes(Int64(model.totalBytes)))
                caption(L("Files are referenced, not duplicated. Their size is used for retention rules but does not consume Encore's budget. Storage and backups are unencrypted."))
                HStack {
                    Button { model.exportLibrary() } label: { Label(L("Export…"), systemImage: "square.and.arrow.up") }
                    Button { model.importLibrary() } label: { Label(L("Import…"), systemImage: "square.and.arrow.down") }
                    Spacer()
                    Button(L("Open folder")) { if let root = model.storage?.root { NSWorkspace.shared.open(root) } }
                }
                HStack {
                    Button { model.exportSnippets() } label: { Label(L("Export snippets…"), systemImage: "text.badge.star") }
                    Button { model.importSnippets() } label: { Label(L("Import snippets…"), systemImage: "square.and.arrow.down") }
                }
                caption(L("Snippets with text, their names, languages and tags, as readable JSON to keep or share."))
                Button(L("Clear history…"), role: .destructive) { model.clearHistory() }
            }
            if updates.available {
                SettingsGroup(L("Updates")) {
                    Toggle(L("Install updates automatically"), isOn: Binding(get: { updates.automaticallyInstalls }, set: { updates.automaticallyInstalls = $0 }))
                    HStack {
                        Text(L("Version \(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "")")).foregroundStyle(.secondary)
                        Spacer()
                        Button(L("Check Now")) { updates.check() }
                    }
                    caption(L("Updates come from releases published on GitHub and are verified by signature before installing."))
                }
            }
        }
    }

    private var peers: some View {
        SettingsForm {
            SettingsGroup(L("Sharing")) {
                InfoRow(L("This Mac’s name"), value: model.deviceName)
                described(L("Off by default. When on, your paired Macs can browse this history and fetch an item on demand, over the local network only. Nothing is copied automatically. Excluded apps, files and confidential content are never shared.")) {
                    Toggle(L("Share history"), isOn: $model.preferences.shareWithPeers).disabled(model.peerService == nil)
                }
                described(L("Merged with the paired Macs that sync them too, then kept up to date while they are connected. Independent of history sharing.")) {
                    VStack(alignment: .leading, spacing: 12) {
                        Toggle(L("Sync favorites"), isOn: $model.preferences.syncFavorites).disabled(model.peerService == nil)
                        Toggle(L("Sync snippets"), isOn: $model.preferences.syncSnippets).disabled(model.peerService == nil)
                    }
                }
            }
            SettingsGroup(L("Paired Macs")) {
                if model.peers.isEmpty { Text(L("No paired Mac")).foregroundStyle(.secondary).padding(.vertical, 8) }
                ForEach(model.peers) { peer in
                    HStack(spacing: 10) {
                        Image(systemName: "laptopcomputer").font(.system(size: 18)).foregroundStyle(.secondary).frame(width: 27)
                        VStack(alignment: .leading, spacing: 2) {
                            Text(peer.device.name).font(.system(size: 13))
                            Text(peer.online ? L("Online") : L("Offline")).font(.system(size: 12)).foregroundStyle(peer.online ? Palette.accent : .secondary)
                        }
                        Spacer()
                        Button(L("Remove"), role: .destructive) { model.revokePeer(peer.id) }.help(L("Erase the secret shared with \(peer.device.name)"))
                    }.padding(.vertical, 4)
                }
                Button { model.pairingSheet = true } label: { Label(L("Pair a Mac…"), systemImage: "plus") }.disabled(model.peerService == nil)
                caption(L("Pairing happens once: check that both Macs show the same 6-digit code. The shared secret stays on each Mac, readable only by your account. Removing a Mac erases it."))
            }
        }
    }

    private var shortcuts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                shortcutGroup(L("Essentials"), items: [(L("Show / hide"), model.shortcutStatus), (model.pastesDirectly ? L("Paste") : L("Copy"), "↩"), (model.pastesDirectly ? L("Paste as plain text") : L("Copy as plain text"), "⇧↩"), (L("Quick paste"), "⌘1 … ⌘9"), (L("Paste queue"), model.preferences.stackShortcutEnabled ? "⌘⇧C" : L("From the shelf"))])
                shortcutGroup(L("Navigation"), items: [(L("Full library"), "↑"), (L("Reduce"), "↓"), (L("Select"), "← →"), (L("Extend selection"), "⇧←  ⇧→"), (L("Preview"), L("space")), (L("Search"), L("⌘F or start typing")), (L("Card size"), "⌘+  ⌘−"), (L("Select all"), "⌘A"), (L("Switch board"), "⌘←  ⌘→")])
                shortcutGroup(L("Organize & edit"), items: [(L("Edit"), "⌘E"), (L("Rename"), "⌘R"), (L("Make a snippet"), "⌘S"), (L("Favorite"), "⌘D"), (L("Add to queue"), "⌘⇧↩"), (L("New snippet"), "⌘N"), (L("New collection"), "⌘⇧N"), (L("Delete / undo"), "⌘⌫ / ⌘Z"), (L("Toggle capture"), "⌘T"), (L("Settings"), "⌘,")])
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Advanced search")).font(.system(size: 13, weight: .semibold))
                    Text("app:safari   type:image   date:today\nafter:2026-10-01   before:2026-11-01").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    caption(L("Combine words and filters. Search ignores accents and includes text recognized in images."))
                }
            }.padding(24)
        }
    }

    private func shortcutGroup(_ title: String, items: [(String, String)]) -> some View {
        VStack(alignment: .leading, spacing: 9) {
            Text(title).font(.system(size: 13, weight: .semibold)).foregroundStyle(.secondary)
            VStack(spacing: 0) {
                ForEach(items, id: \.0) { item in
                    HStack {
                        Text(item.0).font(.system(size: 13))
                        Spacer()
                        Text(Localization.keys(item.1)).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(.primary).padding(.horizontal, 8).padding(.vertical, 5).background(.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 6))
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                    if item.0 != items.last?.0 { Divider().padding(.horizontal, 14) }
                }
            }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private var languages: [String] { Localization.supported.sorted { Localization.nativeName($0).compare(Localization.nativeName($1), options: [.caseInsensitive, .diacriticInsensitive], locale: Localization.locale) == .orderedAscending } }
    private func languageLabel(_ code: String) -> String {
        let native = Localization.nativeName(code), local = Localization.displayName(code)
        return native.caseInsensitiveCompare(local) == .orderedSame ? native : "\(native) (\(local))"
    }
    /// A setting and its explanation in one row, so the text keeps its distance from the next setting.
    private func described<Content: View>(_ text: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
            caption(text)
        }.padding(.vertical, 4)
    }

    private func caption(_ text: String) -> some View { Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    private func percentageControl(_ title: String, symbol: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 10) {
            // A Label would make the form start the row separator at its text, leaving the icon outside the line.
            HStack(spacing: 7) {
                Image(systemName: symbol).foregroundStyle(.secondary).frame(width: 18)
                Text(title)
                Spacer()
                Text(value.wrappedValue, format: .percent.precision(.fractionLength(0)))
                    .font(.system(size: 12, weight: .medium)).monospacedDigit()
                    .padding(.horizontal, 10).padding(.vertical, 4)
                    .background(.primary.opacity(0.055), in: Capsule())
            }
            Slider(value: value, in: range).labelsHidden().controlSize(.small).accessibilityLabel(title)
        }.padding(.vertical, 5)
    }
    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url)?.bundleIdentifier else { return }
        model.preferences.disabledDefaultExclusions.removeAll { $0 == bundle }
        if !model.preferences.excludedBundleIDs.contains(bundle) { model.preferences.excludedBundleIDs.append(bundle) }
        model.refreshInstalledExclusions()
    }
    private func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.directoryURL = model.preferences.screenshotFolder.map { URL(fileURLWithPath: $0) } ?? ScreenshotImporter.defaultFolder
        panel.message = L("Choose the folder where macOS saves your screenshots.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.preferences.screenshotFolder = url.path
        model.preferences.importScreenshots = true
    }
    private func soundThemeRow(_ theme: SoundTheme) -> some View {
        let selected = model.preferences.soundTheme == theme
        return HStack(spacing: 6) {
            Button { model.preferences.soundTheme = theme } label: {
                HStack(spacing: 8) {
                    Image(systemName: selected ? "checkmark.circle.fill" : "circle").foregroundStyle(selected ? Palette.accent : Color.secondary)
                    Text(theme.title).fontWeight(selected ? .semibold : .regular)
                    Spacer(minLength: 0)
                }.contentShape(Rectangle())
            }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
            Button(L("On copy")) { FeedbackSounds.preview(theme, action: .capture, preferences: model.preferences) }
            Button(L("On paste")) { FeedbackSounds.preview(theme, action: .paste, preferences: model.preferences) }
            Button { FeedbackSounds.preview(theme, preferences: model.preferences) } label: { Label(L("Sequence"), systemImage: "play.fill") }
                .help(L("Two copies, then a paste"))
        }.controlSize(.small).modifier(LightButtons())
    }
    /// The alert sounds that come with macOS, played from where they are rather than copied.
    private static let systemSounds = ((try? FileManager.default.contentsOfDirectory(at: URL(fileURLWithPath: "/System/Library/Sounds"), includingPropertiesForKeys: nil)) ?? [])
        .filter { NSSound(contentsOf: $0, byReference: true) != nil }.sorted { $0.lastPathComponent < $1.lastPathComponent }

    private func soundFileRow(_ title: String, path: String?, action: FeedbackSounds.Action) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(path.map { ($0 as NSString).lastPathComponent } ?? L("Default soft sound")).foregroundStyle(.secondary).lineLimit(1)
            Menu(L("System sound")) {
                ForEach(Self.systemSounds, id: \.self) { url in
                    Button(url.deletingPathExtension().lastPathComponent) {
                        NSSound(contentsOf: url, byReference: true)?.play()
                        if action == .capture { model.preferences.captureSoundPath = url.path } else { model.preferences.pasteSoundPath = url.path }
                    }
                }
            }.fixedSize()
            Button(L("Choose…")) {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                guard NSSound(contentsOf: url, byReference: true) != nil else { model.notify(L("This audio format is not supported.")); return }
                if action == .capture { model.preferences.captureSoundPath = url.path } else { model.preferences.pasteSoundPath = url.path }
            }
        }
    }
}

private struct PairingSheet: View {
    @ObservedObject var model: AppModel

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text(L("Pair a Mac")).font(.system(size: 17, weight: .semibold))
            if let session = model.pairing, let state = model.pairingState { progress(session, state) } else { discovery }
        }.padding(24).frame(width: 440).frame(minHeight: 250, alignment: .top)
            .environment(\.locale, Localization.locale)
    }

    private var discovery: some View {
        VStack(alignment: .leading, spacing: 12) {
            note(L("Turn on “Share history” on the other Mac, then choose it below. Both Macs must be on the same network."))
            VStack(spacing: 0) {
                if model.nearbyMacs.isEmpty {
                    HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Looking for nearby Macs…")).foregroundStyle(.secondary) }.frame(maxWidth: .infinity, alignment: .leading).padding(12)
                }
                ForEach(model.nearbyMacs) { device in
                    HStack(spacing: 10) {
                        Image(systemName: "laptopcomputer").foregroundStyle(.secondary).frame(width: 22)
                        Text(device.name)
                        Spacer()
                        Button(L("Pair")) { model.beginPairing(with: device) }
                    }.padding(.horizontal, 12).padding(.vertical, 8)
                    if device.id != model.nearbyMacs.last?.id { Divider().padding(.horizontal, 12) }
                }
            }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 10))
            Spacer(minLength: 0)
            HStack { Spacer(); Button(L("Cancel")) { model.closePairing() }.keyboardShortcut(.cancelAction) }
        }
    }

    @ViewBuilder private func progress(_ session: PairingSession, _ state: PairingSession.State) -> some View {
        let name = session.remote?.name ?? "Mac"
        switch state {
        case .connecting:
            HStack(spacing: 8) { ProgressView().controlSize(.small); Text(L("Connecting…")).foregroundStyle(.secondary) }
            Spacer(minLength: 0)
            HStack { Spacer(); Button(L("Cancel")) { model.closePairing() }.keyboardShortcut(.cancelAction) }
        case .comparing, .confirmed:
            note(session.incoming ? L("\(name) wants to pair. Check that both Macs show the same code.") : L("Check that \(name) shows the same code."))
            Text(formatted(session.code ?? "")).font(.system(size: 40, weight: .semibold, design: .monospaced)).frame(maxWidth: .infinity).padding(.vertical, 6).textSelection(.enabled)
            if state == .confirmed { note(L("Waiting for confirmation on the other Mac…")) }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(L("Cancel")) { model.closePairing() }.keyboardShortcut(.cancelAction)
                Button(L("Confirm")) { model.confirmPairing() }.keyboardShortcut(.defaultAction).disabled(state == .confirmed)
            }
        case .paired:
            Label(L("\(name) is paired."), systemImage: "checkmark.circle.fill").foregroundStyle(Palette.accent)
            Spacer(minLength: 0)
            HStack { Spacer(); Button(L("Done")) { model.closePairing() }.keyboardShortcut(.defaultAction) }
        case .failed:
            Label(L("Pairing cancelled or failed. No secret was saved."), systemImage: "xmark.octagon").foregroundStyle(.secondary)
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Button(L("Close")) { model.closePairing() }.keyboardShortcut(.cancelAction)
                Button(L("Try Again")) { model.resetPairing() }.keyboardShortcut(.defaultAction)
            }
        }
    }

    private func formatted(_ code: String) -> String { code.count == 6 ? "\(code.prefix(3)) \(code.suffix(3))" : code }
    private func note(_ text: String) -> some View { Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
}

/// Records the shortcut that shows encore: click, then type the keys. Escape cancels.
struct ShortcutRecorder: View {
    @Binding var preference: String
    @Binding var refused: Bool
    let suspend: () -> Void
    let resume: () -> Void
    @State private var monitor: Any?

    var body: some View {
        HStack(spacing: 6) {
            Button { monitor == nil ? start() : stop() } label: {
                Text(monitor == nil ? Localization.keys(GlobalShortcut(preference: preference).label) : L("Type a shortcut…")).frame(minWidth: 110)
            }
            if monitor == nil && preference != GlobalShortcut.standard.preference {
                Button { preference = GlobalShortcut.standard.preference; resume() } label: { Image(systemName: "arrow.uturn.backward") }
                    .buttonStyle(.borderless).help(L("Back to ⌘⇧V"))
            }
        }
        .onDisappear(perform: stop)
    }

    private func start() {
        refused = false
        suspend()
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            if Int(event.keyCode) == kVK_Escape { stop() }
            else if let shortcut = GlobalShortcut(event: event) { preference = shortcut.preference; refused = false; stop() }
            else { refused = true; NSSound.beep() }
            return nil
        }
    }

    private func stop() {
        guard let monitor else { return }
        NSEvent.removeMonitor(monitor)
        self.monitor = nil
        resumeOnceReleased()
    }

    /// The new shortcut would fire if registered while its keys are still held: wait until they are released.
    private func resumeOnceReleased() {
        guard NSEvent.modifierFlags.intersection([.command, .option, .control, .shift]).isEmpty else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.1) { resumeOnceReleased() }
            return
        }
        resume()
    }
}
