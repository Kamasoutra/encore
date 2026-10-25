import AppKit
import SwiftUI
import ServiceManagement
import EncoreCore

private enum SettingsSection: String, CaseIterable, Identifiable {
    case general, privacy, retention, data, shortcuts
    var id: String { rawValue }
    var title: String {
        switch self { case .general: "Général"; case .privacy: "Confidentialité"; case .retention: "Rétention"; case .data: "Données"; case .shortcuts: "Raccourcis" }
    }
    var symbol: String {
        switch self { case .general: "slider.horizontal.3"; case .privacy: "hand.raised"; case .retention: "clock.arrow.circlepath"; case .data: "externaldrive"; case .shortcuts: "keyboard" }
    }
    var subtitle: String {
        switch self {
        case .general: "Un presse-papiers qui s’adapte à votre façon de travailler."
        case .privacy: "Choisissez ce qu’Encore peut garder. Tout reste sur ce Mac."
        case .retention: "Une durée par taille et type. La première règle correspondante l’emporte."
        case .data: "Conservation, sauvegardes et espace utilisé."
        case .shortcuts: "Retrouver, sélectionner, coller. Sans quitter le clavier."
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
            .background(Color(nsColor: .windowBackgroundColor))
            .onChange(of: model.preferences) { _, _ in model.preferencesChanged() }
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
                Label("100 % local", systemImage: "lock.shield").font(.system(size: 12)).foregroundStyle(.secondary)
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
            Section("Au quotidien") {
                Toggle("Enregistrer les nouvelles copies", isOn: $model.preferences.captureEnabled).disabled(model.storage == nil || model.storageError != nil)
                Toggle("Ouvrir à la connexion", isOn: $launchAtLogin).disabled(model.demo).onChange(of: launchAtLogin) { _, value in
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { model.notify("Démarrage automatique : \(error.localizedDescription)"); launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
                Picker("Ouvrir Encore", selection: $model.preferences.shortcut) {
                    Text("⌘⇧V").tag("commandShiftV"); Text("⌘⌥V").tag("commandOptionV")
                }.onChange(of: model.preferences.shortcut) { _, _ in model.updateShortcuts?() }
                caption("Raccourci actif : \(model.shortcutStatus). Secours : ⌃⌥⌘V.")
                Toggle("Réserver ⌘⇧C pour la pile de collage", isOn: $model.preferences.stackShortcutEnabled)
                    .onChange(of: model.preferences.stackShortcutEnabled) { _, _ in model.updateShortcuts?() }
                caption("Désactivé par défaut pour conserver ce raccourci dans vos autres applications. La pile reste accessible depuis le panneau.")
            }
            Section("Apparence") {
                Picker("Thème", selection: $model.preferences.appearance) {
                    Text("Système").tag("system"); Text("Clair").tag("light"); Text("Sombre").tag("dark")
                }
                Toggle("Cartes compactes", isOn: $model.preferences.compact)
                HStack {
                    Text("Taille des cartes")
                    Slider(value: $model.preferences.cardScale, in: 0.75...1.5, step: 0.05).frame(width: 160)
                    Text(model.preferences.cardScale, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 46)
                }
                caption("Glissez la poignée au-dessus du panneau pour régler sa hauteur. ⌘+ et ⌘− ajustent les cartes.")
            }
            Section("Écran d’affichage") {
                Picker("Afficher le panneau sur", selection: $model.preferences.displayTarget) {
                    Text("Écran actuel · au pointeur").tag("active")
                    Text("Écran principal de macOS").tag("primary")
                    ForEach(NSScreen.screens, id: \.self) { screen in
                        if let id = ScreenPlacement.identifier(screen) { Text(screen.localizedName).tag(id) }
                    }
                    if !["active", "primary"].contains(model.preferences.displayTarget), !NSScreen.screens.contains(where: { ScreenPlacement.identifier($0) == model.preferences.displayTarget }) {
                        Text("Écran déconnecté · principal en secours").tag(model.preferences.displayTarget)
                    }
                }.onChange(of: model.preferences.displayTarget) { _, _ in model.resizePanel?() }
                caption("Le moniteur choisi est mémorisé. S’il est débranché, Encore utilise l’écran principal jusqu’à son retour.")
            }
            Section("Retour sonore") {
                Toggle("Jouer un son à la copie et au collage", isOn: $model.preferences.soundsEnabled)
                Picker("Ambiance", selection: $model.preferences.soundTheme) { ForEach(SoundTheme.allCases) { theme in Text(theme.title).tag(theme) } }
                HStack {
                    Text("Volume")
                    Slider(value: $model.preferences.soundVolume, in: 0...1).frame(width: 180)
                    Text(model.preferences.soundVolume, format: .percent.precision(.fractionLength(0))).monospacedDigit().frame(width: 44)
                }
                HStack {
                    Button { FeedbackSounds.play(.capture, preferences: model.preferences) } label: { Label("Copie", systemImage: "play.circle") }
                    Button { FeedbackSounds.play(.paste, preferences: model.preferences) } label: { Label("Collage", systemImage: "play.circle") }
                }
                if model.preferences.soundTheme == .custom {
                    soundFileRow("Copie", path: model.preferences.captureSoundPath, action: .capture)
                    soundFileRow("Collage", path: model.preferences.pasteSoundPath, action: .paste)
                }
            }
            Section("Collage direct") {
                HStack {
                    Label(model.accessibilityGranted ? "Autorisé" : "Autorisation nécessaire", systemImage: model.accessibilityGranted ? "checkmark.shield" : "lock")
                    Spacer(); Button("Configurer…") { model.requestAccessibility() }
                }
                caption("L’autorisation Accessibilité permet le collage au curseur et en série. Sans elle, Encore recopie l’élément pour un ⌘V manuel.")
            }
        }.formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Section("Capture") {
                Toggle("Ignorer les contenus confidentiels et temporaires", isOn: $model.preferences.ignoreSensitive)
                Toggle("Reconnaître le texte des images", isOn: $model.preferences.recognizeImages)
                caption("L’OCR fonctionne sur ce Mac. Aucun compte ni télémétrie. Les liens ne sont pas chargés en arrière-plan.")
            }
            Section("Applications exclues") {
                VStack(spacing: 0) {
                    ForEach(model.preferences.excludedBundleIDs, id: \.self) { bundle in
                        let app = ApplicationCatalog.app(bundle)
                        HStack(spacing: 10) {
                            Image(nsImage: app.icon).resizable().interpolation(.high).frame(width: 27, height: 27)
                            Text(app.name).font(.system(size: 13))
                            Spacer()
                            Button(role: .destructive) { model.preferences.excludedBundleIDs.removeAll { $0 == bundle } } label: { Image(systemName: "minus.circle").foregroundStyle(.secondary) }.buttonStyle(.plain).help("Retirer \(app.name) des exclusions")
                        }.padding(.vertical, 8).help(bundle)
                        if bundle != model.preferences.excludedBundleIDs.last { Divider() }
                    }
                }
                Button { addExcludedApp() } label: { Label("Ajouter une application…", systemImage: "plus") }
                caption("Les gestionnaires de mots de passe courants sont exclus par défaut. Les anciennes copies ne sont pas supprimées lorsqu’une application est exclue.")
            }
            Section("Captures d’écran natives") {
                Toggle("Importer les nouvelles captures enregistrées", isOn: Binding(get: { model.preferences.importScreenshots }, set: { value in
                    if value { chooseScreenshotFolder() } else { model.preferences.importScreenshots = false }
                }))
                if model.preferences.importScreenshots {
                    HStack {
                        Label((model.preferences.screenshotFolder as NSString?)?.lastPathComponent ?? "Bureau", systemImage: "folder")
                        Spacer()
                        Button("Changer…") { chooseScreenshotFolder() }
                    }
                }
                caption("Les nouvelles captures de ce dossier rejoignent l’historique sans modifier votre presse-papiers. Le dossier est surveillé uniquement quand Encore et la capture sont actifs. Les captures existantes ne sont pas importées.")
            }
            caption("Certaines extensions de navigateur n’identifient pas les secrets. Vous pouvez exclure leur navigateur si nécessaire.")
        }.formStyle(.grouped)
    }

    private var data: some View {
        Form {
            Section("Conservation") {
                LabeledContent("Durée sans règle", value: model.preferences.retentionDays == 0 ? "Indéfiniment" : "\(model.preferences.retentionDays) jours")
                Button { section = .retention } label: { Label("Configurer les règles de rétention", systemImage: "clock.arrow.circlepath") }
                Picker("Éléments sans règle", selection: $model.preferences.historyLimit) {
                    Text("500 maximum").tag(500); Text("2 000 maximum").tag(2000); Text("10 000 maximum").tag(10000); Text("Sans limite de nombre").tag(0)
                }
                Picker("Budget de contenu intégré", selection: $model.preferences.storageLimitMB) {
                    Text("100 Mio").tag(100); Text("500 Mio").tag(500); Text("2 000 Mio").tag(2000)
                }
                caption("Favoris, collections et éléments sous règle échappent à la limite de nombre. Le budget plein bloque les nouvelles copies. Limite technique : 25 Mio de contenu intégré par copie.")
            }
            Section("Bibliothèque locale") {
                if let error = model.storageError {
                    Label(error, systemImage: "exclamationmark.triangle").foregroundStyle(.red)
                    Button("Recharger la bibliothèque…") { model.reloadStorage() }
                }
                LabeledContent("Éléments", value: "\(model.library.clips.count)")
                LabeledContent("Contenu conservé", value: ByteCountFormatter.string(fromByteCount: Int64(model.totalBytes), countStyle: .file))
                caption("Les fichiers sont référencés et ne sont pas dupliqués. Leur taille sert aux règles, mais ne consomme pas le budget d’Encore. Le stockage et les sauvegardes restent en clair.")
                HStack {
                    Button { model.exportLibrary() } label: { Label("Exporter…", systemImage: "square.and.arrow.up") }
                    Button { model.importLibrary() } label: { Label("Importer…", systemImage: "square.and.arrow.down") }
                    Spacer()
                    Button("Ouvrir le dossier") { if let root = model.storage?.root { NSWorkspace.shared.open(root) } }
                }
                Button("Effacer l’historique…", role: .destructive) { model.clearHistory() }
            }
        }.formStyle(.grouped)
    }

    private var shortcuts: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 21) {
                shortcutGroup("Essentiels", items: [("Ouvrir / fermer", model.shortcutStatus), ("Coller", "↩"), ("Coller en texte brut", "⇧↩"), ("Collage rapide", "⌘1 … ⌘9"), ("File de collage", model.preferences.stackShortcutEnabled ? "⌘⇧C" : "Via le panneau")])
                shortcutGroup("Navigation", items: [("Sélectionner", "← →"), ("Étendre la sélection", "⇧←  ⇧→"), ("Aperçu", "Espace"), ("Rechercher", "⌘F ou saisir"), ("Taille des cartes", "⌘+  ⌘−"), ("Tout sélectionner", "⌘A")])
                shortcutGroup("Organiser & éditer", items: [("Éditer", "⌘E"), ("Favori", "⌘D"), ("Ajouter à la file", "⌘⇧↩"), ("Nouvel extrait", "⌘N"), ("Nouvelle collection", "⌘⇧N"), ("Supprimer / annuler", "⌫ / ⌘Z"), ("Pause de capture", "⌘T"), ("Réglages", "⌘,")])
                VStack(alignment: .leading, spacing: 10) {
                    Text("Recherche avancée").font(.system(size: 13, weight: .semibold))
                    Text("app:safari   type:image   date:today\nafter:2026-10-01   before:2026-11-01").font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                    caption("Combinez les mots et filtres. La recherche ignore les accents et inclut le texte reconnu dans les images.")
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
    private func addExcludedApp() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = [.application]; panel.directoryURL = URL(fileURLWithPath: "/Applications")
        guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url)?.bundleIdentifier else { return }
        if !model.preferences.excludedBundleIDs.contains(bundle) { model.preferences.excludedBundleIDs.append(bundle) }
    }
    private func chooseScreenshotFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true; panel.canChooseFiles = false
        panel.directoryURL = model.preferences.screenshotFolder.map { URL(fileURLWithPath: $0) } ?? ScreenshotImporter.defaultFolder
        panel.message = "Choisissez le dossier où macOS enregistre vos captures d’écran."
        guard panel.runModal() == .OK, let url = panel.url else { return }
        model.preferences.screenshotFolder = url.path
        model.preferences.importScreenshots = true
    }
    private func soundFileRow(_ title: String, path: String?, action: FeedbackSounds.Action) -> some View {
        HStack {
            Text(title)
            Spacer()
            Text(path.map { ($0 as NSString).lastPathComponent } ?? "Son doux par défaut").foregroundStyle(.secondary).lineLimit(1)
            Button("Choisir…") {
                let panel = NSOpenPanel(); panel.allowedContentTypes = [.audio]
                guard panel.runModal() == .OK, let url = panel.url else { return }
                guard NSSound(contentsOf: url, byReference: true) != nil else { model.notify("Ce format audio n’est pas pris en charge."); return }
                if action == .capture { model.preferences.captureSoundPath = url.path } else { model.preferences.pasteSoundPath = url.path }
            }
        }
    }
}
