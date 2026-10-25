import AppKit
import SwiftUI
import ServiceManagement
import EncoreCore

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, privacy, retention, data, shortcuts
    var id: String { rawValue }
    var title: String {
        switch self { case .general: L("Général"); case .privacy: L("Confidentialité"); case .retention: L("Rétention"); case .data: L("Données"); case .shortcuts: L("Raccourcis") }
    }
    var symbol: String {
        switch self { case .general: "slider.horizontal.3"; case .privacy: "hand.raised"; case .retention: "clock.arrow.circlepath"; case .data: "externaldrive"; case .shortcuts: "keyboard" }
    }
    var subtitle: String {
        switch self {
        case .general: L("Un presse-papiers qui s’adapte à votre façon de travailler.")
        case .privacy: L("Choisissez ce qu’Encore peut garder. Tout reste sur ce Mac.")
        case .retention: L("Une durée par taille et type. La première règle correspondante l’emporte.")
        case .data: L("Conservation, sauvegardes et espace utilisé.")
        case .shortcuts: L("Retrouver, sélectionner, coller. Sans quitter le clavier.")
        }
    }
}

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var section: SettingsSection = .general
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled

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
                    case .shortcuts: shortcuts
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                if !model.status.isEmpty {
                    Text(model.status).font(.system(size: 12)).foregroundStyle(Palette.accent).padding(.horizontal, 24).padding(.vertical, 10)
                }
            }
        }.frame(width: 780, height: 680).font(.system(size: 13)).tint(Palette.accent)
            .environment(\.locale, Localization.locale)
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: model.preferences) { _, _ in model.preferencesChanged() }
            .onAppear { model.refreshInstalledExclusions() }
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(spacing: 10) { EncoreMark(size: 35); Text("Encore").font(.system(size: 22, weight: .semibold)) }.padding(.horizontal, 7).padding(.top, 13)
            List(selection: Binding<SettingsSection?>(get: { section }, set: { if let value = $0 { section = value } })) {
                ForEach(SettingsSection.allCases) { item in
                    Label(item.title, systemImage: item.symbol)
                        .font(.system(size: 13))
                        .padding(.vertical, 4)
                        .tag(item)
                }
            }.listStyle(.sidebar).scrollContentBackground(.hidden)
            Spacer()
            VStack(alignment: .leading, spacing: 7) {
                Label(L("100 % local"), systemImage: "lock.shield").font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Text("v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "dev")").font(.system(size: 12)).foregroundStyle(.secondary)
                    Spacer()
                    Link("GitHub ↗", destination: URL(string: "https://github.com/Kamasoutra/encore")!).font(.system(size: 12))
                }
            }.padding(8)
        }.padding(15).frame(width: 175).background(.primary.opacity(0.025))
    }

    private var general: some View {
        Form {
            Section(L("Au quotidien")) {
                Toggle(L("Enregistrer les nouvelles copies"), isOn: $model.preferences.captureEnabled).disabled(model.storage == nil || model.storageError != nil)
                Toggle(L("Ouvrir à la connexion"), isOn: $launchAtLogin).disabled(model.demo).onChange(of: launchAtLogin) { _, value in
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { model.notify(L("Démarrage automatique : \(error.localizedDescription)")); launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
                Picker(L("Ouvrir Encore"), selection: $model.preferences.shortcut) {
                    Text("⌘⇧V").tag("commandShiftV"); Text("⌘⌥V").tag("commandOptionV")
                }.onChange(of: model.preferences.shortcut) { _, _ in model.updateShortcuts?() }
                caption(L("Raccourci actif : \(model.shortcutStatus). Secours : ⌃⌥⌘V."))
                Toggle(L("Réserver ⌘⇧C pour la pile de collage"), isOn: $model.preferences.stackShortcutEnabled)
                    .onChange(of: model.preferences.stackShortcutEnabled) { _, _ in model.updateShortcuts?() }
                caption(L("Désactivé par défaut pour conserver ce raccourci dans vos autres applications. La pile reste accessible depuis le panneau."))
            }
            Section(L("Apparence")) {
                Picker(L("Langue"), selection: $model.preferences.language) {
                    Text(L("Suivre macOS")).tag("system")
                    Text("Français").tag("fr")
                    Text("English").tag("en")
                }
                Picker(L("Thème"), selection: $model.preferences.appearance) {
                    Text(L("Système")).tag("system"); Text(L("Clair")).tag("light"); Text(L("Sombre")).tag("dark")
                }
                Toggle(L("Cartes compactes"), isOn: $model.preferences.compact)
                percentageControl(L("Taille des cartes"), symbol: "rectangle.grid.1x2", value: $model.preferences.cardScale, range: 0.75...1.5)
                caption(L("Glissez la poignée au-dessus du panneau pour régler sa hauteur. ⌘+ et ⌘− ajustent les cartes."))
            }
            Section(L("Écran d’affichage")) {
                Picker(L("Afficher le panneau sur"), selection: $model.preferences.displayTarget) {
                    Text(L("Écran actuel · au pointeur")).tag("active")
                    Text(L("Écran principal de macOS")).tag("primary")
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        if let id = ScreenPlacement.identifier(screen) { Text(screen.localizedName).tag(id) }
                    }
                    if !["active", "primary"].contains(model.preferences.displayTarget), !NSScreen.screens.contains(where: { ScreenPlacement.identifier($0) == model.preferences.displayTarget }) {
                        Text(L("Écran déconnecté · principal en secours")).tag(model.preferences.displayTarget)
                    }
                }.onChange(of: model.preferences.displayTarget) { _, _ in model.resizePanel?() }
                caption(L("Le moniteur choisi est mémorisé. S’il est débranché, Encore utilise l’écran principal jusqu’à son retour."))
            }
            Section(L("Retour sonore")) {
                Toggle(L("Jouer un son à la copie et au collage"), isOn: $model.preferences.soundsEnabled)
                Picker(L("Ambiance"), selection: $model.preferences.soundTheme) { ForEach(SoundTheme.allCases) { theme in Text(theme.title).tag(theme) } }
                percentageControl(L("Volume"), symbol: "speaker.wave.2", value: $model.preferences.soundVolume, range: 0...1)
                HStack {
                    Button { FeedbackSounds.play(.capture, preferences: model.preferences) } label: { Label(L("Copie"), systemImage: "play.circle") }
                    Button { FeedbackSounds.play(.paste, preferences: model.preferences) } label: { Label(L("Collage"), systemImage: "play.circle") }
                }
                if model.preferences.soundTheme == .custom {
                    soundFileRow(L("Copie"), path: model.preferences.captureSoundPath, action: .capture)
                    soundFileRow(L("Collage"), path: model.preferences.pasteSoundPath, action: .paste)
                }
            }
            Section(L("Collage direct")) {
                HStack {
                    Label(model.accessibilityGranted ? L("Collage direct autorisé") : L("Collage manuel actif"), systemImage: model.accessibilityGranted ? "checkmark.shield" : "lock")
                    Spacer()
                    Button(L("Vérifier")) { model.accessibilityGranted = AXIsProcessTrusted() }
                    Button(L("Réglages macOS…")) { model.requestAccessibility() }
                }
                caption(L("L’autorisation Accessibilité permet le collage au curseur et en série. Sans elle, Encore recopie l’élément pour un ⌘V manuel."))
                if !model.accessibilityGranted {
                    caption(L("macOS n’autorise pas cette version d’Encore. Si vous aviez déjà accordé l’accès, désactivez puis réactivez Encore dans Accessibilité. Si nécessaire, retirez l’ancienne entrée et ajoutez l’application installée. Une signature ad hoc peut invalider l’accès après une mise à jour."))
                }
            }
        }.formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Section(L("Capture")) {
                Toggle(L("Ignorer les contenus confidentiels et temporaires"), isOn: $model.preferences.ignoreSensitive)
                Toggle(L("Reconnaître le texte des images"), isOn: $model.preferences.recognizeImages)
                caption(L("L’OCR fonctionne sur ce Mac. Aucun compte ni télémétrie. Les liens ne sont pas chargés en arrière-plan."))
            }
            Section(L("Applications exclues")) {
                VStack(spacing: 0) {
                    if model.installedExcludedBundleIDs.isEmpty { Text(L("Aucune application exclue installée")).foregroundStyle(.secondary).padding(.vertical, 8) }
                    ForEach(model.installedExcludedBundleIDs, id: \.self) { bundle in
                        let app = ApplicationCatalog.app(bundle)
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 27, height: 27)
                            Text(app.name).font(.system(size: 13))
                            Spacer()
                            Button(role: .destructive) { model.removeExcludedApp(bundle) } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }.buttonStyle(.plain).help(L("Retirer \(app.name) des exclusions"))
                        }.padding(.vertical, 8).help(bundle)
                        if bundle != model.installedExcludedBundleIDs.last { Divider() }
                    }
                }
                Button { addExcludedApp() } label: { Label(L("Ajouter une application…"), systemImage: "plus") }
                caption(L("Les gestionnaires de mots de passe installés sont exclus automatiquement. Les nouvelles installations sont détectées. Une application que vous retirez ne sera pas réactivée automatiquement."))
            }
            Section(L("Captures d’écran natives")) {
                Toggle(L("Importer les nouvelles captures enregistrées"), isOn: Binding(get: { model.preferences.importScreenshots }, set: { value in
                    if value { chooseScreenshotFolder() } else { model.preferences.importScreenshots = false }
                }))
                if model.preferences.importScreenshots {
                    HStack {
                        Label((model.preferences.screenshotFolder as NSString?)?.lastPathComponent ?? L("Bureau"), systemImage: "folder")
                        Spacer()
                        Button(L("Changer…")) { chooseScreenshotFolder() }
                    }
                }
                caption(L("Les nouvelles captures de ce dossier rejoignent l’historique sans modifier votre presse-papiers. Le dossier est surveillé uniquement quand Encore et la capture sont actifs. Les captures existantes ne sont pas importées."))
            }
            caption(L("Certaines extensions de navigateur n’identifient pas les secrets. Vous pouvez exclure leur navigateur si nécessaire."))
        }.formStyle(.grouped)
    }

    private var data: some View {
        Form {
            Section(L("Conservation")) {
                LabeledContent(L("Durée sans règle"), value: model.preferences.retentionDays == 0 ? L("Indéfiniment") : L("\(model.preferences.retentionDays) jours"))
                Button { section = .retention } label: { Label(L("Configurer les règles de rétention"), systemImage: "clock.arrow.circlepath") }
                Picker(L("Éléments sans règle"), selection: $model.preferences.historyLimit) {
                    Text(L("500 maximum")).tag(500); Text(L("2 000 maximum")).tag(2000); Text(L("10 000 maximum")).tag(10000); Text(L("Sans limite de nombre")).tag(0)
                }
                Picker(L("Budget de contenu intégré"), selection: $model.preferences.storageLimitMB) {
                    Text(L("100 Mio")).tag(100); Text(L("500 Mio")).tag(500); Text(L("2 000 Mio")).tag(2000)
                }
                caption(L("Favoris, collections et éléments sous règle échappent à la limite de nombre. Le budget plein bloque les nouvelles copies. Limite technique : 25 Mio de contenu intégré par copie."))
            }
            Section(L("Bibliothèque locale")) {
                if let error = model.storageError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button(L("Recharger la bibliothèque…")) { model.reloadStorage() }
                }
                LabeledContent(L("Éléments"), value: "\(model.library.clips.count)")
                LabeledContent(L("Contenu conservé"), value: ByteCountFormatter.string(fromByteCount: Int64(model.totalBytes), countStyle: .file))
                caption(L("Les fichiers sont référencés et ne sont pas dupliqués. Leur taille sert aux règles, mais ne consomme pas le budget d’Encore. Le stockage et les sauvegardes restent en clair."))
                HStack {
                    Button { model.exportLibrary() } label: { Label(L("Exporter…"), systemImage: "square.and.arrow.up") }
                    Button { model.importLibrary() } label: { Label(L("Importer…"), systemImage: "square.and.arrow.down") }
                    Spacer()
                    Button(L("Ouvrir le dossier")) { if let root = model.storage?.root { NSWorkspace.shared.open(root) } }
                }
                Button(L("Effacer l’historique…"), role: .destructive) { model.clearHistory() }
            }
        }.formStyle(.grouped)
    }

    private var shortcuts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                shortcutGroup(L("Essentiels"), items: [(L("Ouvrir / fermer"), model.shortcutStatus), (L("Coller"), "↩"), (L("Coller en texte brut"), "⇧↩"), (L("Collage rapide"), "⌘1 … ⌘9"), (L("File de collage"), model.preferences.stackShortcutEnabled ? "⌘⇧C" : L("Via le panneau"))])
                shortcutGroup(L("Navigation"), items: [(L("Vue complète"), "↑"), (L("Réduire"), "↓"), (L("Sélectionner"), "← →"), (L("Étendre la sélection"), "⇧←  ⇧→"), (L("Aperçu"), L("espace")), (L("Rechercher"), L("⌘F ou saisir")), (L("Taille des cartes"), "⌘+  ⌘−"), (L("Tout sélectionner"), "⌘A")])
                shortcutGroup(L("Organiser & éditer"), items: [(L("Éditer"), "⌘E"), (L("Favori"), "⌘D"), (L("Ajouter à la file"), "⌘⇧↩"), (L("Nouvel extrait"), "⌘N"), (L("Nouvelle collection"), "⌘⇧N"), (L("Supprimer / annuler"), "⌫ / ⌘Z"), (L("Pause de capture"), "⌘T"), (L("Réglages"), "⌘,")])
                VStack(alignment: .leading, spacing: 10) {
                    Text(L("Recherche avancée")).font(.system(size: 13, weight: .semibold))
                    Text("app:safari   type:image   date:today\nafter:2026-10-01   before:2026-11-01").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    caption(L("Combinez les mots et filtres. La recherche ignore les accents et inclut le texte reconnu dans les images."))
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
                        Text(item.1).font(.system(size: 13, weight: .medium)).monospacedDigit().foregroundStyle(.primary).padding(.horizontal, 8).padding(.vertical, 5).background(.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 6))
                    }.padding(.horizontal, 14).padding(.vertical, 8)
                    if item.0 != items.last?.0 { Divider().padding(.horizontal, 14) }
                }
            }.background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
        }
    }

    private func caption(_ text: String) -> some View { Text(text).font(.system(size: 12)).foregroundStyle(.secondary).fixedSize(horizontal: false, vertical: true) }
    private func percentageControl(_ title: String, symbol: String, value: Binding<Double>, range: ClosedRange<Double>) -> some View {
        VStack(spacing: 10) {
            HStack {
                Label(title, systemImage: symbol)
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
        panel.message = L("Choisissez le dossier où macOS enregistre vos captures d’écran.")
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.preferences.screenshotFolder = url.path
        model.preferences.importScreenshots = true
    }
    private func soundFileRow(_ title: String, path: String?, action: FeedbackSounds.Action) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(path.map { ($0 as NSString).lastPathComponent } ?? L("Son doux par défaut")).foregroundStyle(.secondary).lineLimit(1)
            Button(L("Choisir…")) {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                guard NSSound(contentsOf: url, byReference: true) != nil else { model.notify(L("Ce format audio n’est pas pris en charge.")); return }
                if action == .capture { model.preferences.captureSoundPath = url.path } else { model.preferences.pasteSoundPath = url.path }
            }
        }
    }
}
