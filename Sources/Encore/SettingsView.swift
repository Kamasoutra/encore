import AppKit
import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var model: AppModel
    @State private var tab = 0
    @State private var launchAtLogin = SMAppService.mainApp.status == .enabled
    @State private var excluded = ""

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 14) {
                EncoreMark(size: 42)
                VStack(alignment: .leading, spacing: 3) {
                    Text("Encore").font(.system(size: 25, weight: .bold, design: .rounded))
                    Text("Votre presse-papiers. Pour de bon.").font(.system(size: 12)).foregroundStyle(.secondary)
                }
                Spacer()
                Text("v0.1.0").font(.system(size: 11, design: .monospaced)).foregroundStyle(.tertiary)
            }.padding(24)
            TabView(selection: $tab) {
                general.tabItem { Label("Général", systemImage: "slider.horizontal.3") }.tag(0)
                privacy.tabItem { Label("Confidentialité", systemImage: "hand.raised") }.tag(1)
                data.tabItem { Label("Données", systemImage: "externaldrive") }.tag(2)
                shortcuts.tabItem { Label("Clavier", systemImage: "keyboard") }.tag(3)
            }.padding(.horizontal, 20).padding(.bottom, 20)
            if !model.status.isEmpty { Text(model.status).font(.system(size: 11)).foregroundStyle(Palette.accent).padding(.bottom, 12) }
        }.frame(width: 600, height: 590).tint(Palette.accent)
            .onAppear { excluded = model.preferences.excludedBundleIDs.joined(separator: "\n") }
            .onChange(of: model.preferences) { _, _ in model.preferencesChanged() }
    }

    private var general: some View {
        Form {
            Section("Au quotidien") {
                Toggle("Enregistrer les nouvelles copies", isOn: $model.preferences.captureEnabled).disabled(model.storage == nil)
                Toggle("Ouvrir à la connexion", isOn: $launchAtLogin).onChange(of: launchAtLogin) { _, value in
                    do {
                        if value { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
                    } catch { model.notify("Démarrage automatique : \(error.localizedDescription)"); launchAtLogin = SMAppService.mainApp.status == .enabled }
                }
                Picker("Raccourci d’ouverture", selection: $model.preferences.shortcut) {
                    Text("⌘⇧V — comme Paste").tag("commandShiftV")
                    Text("⌘⌥V").tag("commandOptionV")
                }.onChange(of: model.preferences.shortcut) { _, _ in model.updateShortcuts?() }
                Text("Actuellement : \(model.shortcutStatus). Secours : ⌃⌥⌘V.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Section("Apparence") {
                Picker("Thème", selection: $model.preferences.appearance) {
                    Text("Système").tag("system")
                    Text("Clair").tag("light")
                    Text("Sombre").tag("dark")
                }
                Toggle("Cartes compactes", isOn: $model.preferences.compact)
                Text("Glissez la poignée en haut du panneau pour régler sa hauteur.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Section("Collage direct") {
                HStack {
                    Label(model.accessibilityGranted ? "Autorisé" : "Autorisation Accessibilité nécessaire", systemImage: model.accessibilityGranted ? "checkmark.shield" : "lock")
                    Spacer()
                    Button("Configurer") { model.requestAccessibility() }
                }
                Text("Permet de coller au curseur et d’utiliser la file de collage. Sans autorisation, Encore recopie l’élément pour un ⌘V manuel.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private var privacy: some View {
        Form {
            Section("Ce qui reste privé") {
                Toggle("Ignorer les contenus confidentiels et temporaires", isOn: $model.preferences.ignoreSensitive)
                Toggle("Reconnaître le texte des images, sur ce Mac", isOn: $model.preferences.recognizeImages)
                Text("Aucun compte, aucune télémétrie, aucun serveur. L’OCR utilise Vision d’Apple localement. Les liens ne sont pas chargés à votre insu.").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Section("Applications exclues") {
                Text("Un identifiant d’application par ligne. Les gestionnaires de mots de passe courants sont exclus par défaut.").font(.system(size: 11)).foregroundStyle(.secondary)
                TextEditor(text: $excluded).font(.system(size: 11, design: .monospaced)).frame(height: 110)
                    .onChange(of: excluded) { _, value in model.preferences.excludedBundleIDs = value.split(whereSeparator: \.isNewline).map { $0.trimmingCharacters(in: .whitespaces) }.filter { !$0.isEmpty } }
                Button("Exclure une application…") {
                    let panel = NSOpenPanel()
                    panel.allowedContentTypes = [.application]
                    panel.directoryURL = URL(fileURLWithPath: "/Applications")
                    guard panel.runModal() == .OK, let url = panel.url, let bundle = Bundle(url: url)?.bundleIdentifier else { return }
                    if !model.preferences.excludedBundleIDs.contains(bundle) { model.preferences.excludedBundleIDs.append(bundle) }
                    excluded = model.preferences.excludedBundleIDs.joined(separator: "\n")
                }
            }
            Text("La détection des secrets n’est pas infaillible, notamment avec les extensions de navigateur. Excluez l’application concernée pour arrêter sa capture. Les anciennes copies restent dans l’historique.").font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 18)
        }.formStyle(.grouped)
    }

    private var data: some View {
        Form {
            Section("Conservation") {
                Picker("Garder l’historique", selection: $model.preferences.retentionDays) {
                    Text("7 jours").tag(7); Text("30 jours").tag(30); Text("90 jours").tag(90); Text("1 an").tag(365); Text("Sans expiration").tag(0)
                }
                Picker("Nombre maximal d’éléments", selection: $model.preferences.historyLimit) {
                    Text("500").tag(500); Text("2 000").tag(2000); Text("10 000").tag(10000)
                }
                Picker("Budget de contenu", selection: $model.preferences.storageLimitMB) {
                    Text("100 Mo").tag(100); Text("500 Mo").tag(500); Text("2 Go").tag(2000)
                }
                Text("Favoris et collections sont conservés sans expiration. Les nouvelles copies sont ignorées si le budget est atteint. Limite de 25 Mo par copie. Le stockage réel inclut l’encodage et les métadonnées.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
            Section("Bibliothèque locale") {
                LabeledContent("Éléments", value: "\(model.library.clips.count)")
                LabeledContent("Contenu brut", value: ByteCountFormatter.string(fromByteCount: Int64(model.totalBytes), countStyle: .file))
                Text("Stockage local en clair, protégé par les permissions de votre compte macOS. Les fichiers copiés sont référencés, pas dupliqués.").font(.system(size: 10)).foregroundStyle(.secondary)
                HStack {
                    Button("Exporter…") { model.exportLibrary() }
                    Button("Importer…") { model.importLibrary() }
                    Spacer()
                    Button("Ouvrir le dossier") { if let root = model.storage?.root { NSWorkspace.shared.open(root) } }
                }
                Button("Effacer l’historique…", role: .destructive) { model.clearHistory() }
            }
        }.formStyle(.grouped)
    }

    private var shortcuts: some View {
        Form {
            Section("Le clavier avant tout") {
                shortcut("Ouvrir / fermer", keys: model.shortcutStatus)
                shortcut("File de collage", keys: "⌘⇧C")
                shortcut("Naviguer", keys: "← →")
                shortcut("Coller / texte brut", keys: "↩ / ⇧↩")
                shortcut("Collage rapide", keys: "⌘1 … ⌘9")
                shortcut("Aperçu / édition", keys: "Espace / ⌘E")
                shortcut("Rechercher", keys: "⌘F ou saisir")
                shortcut("Favori / ajouter à la file", keys: "⌘D / ⌘⇧↩")
                shortcut("Créer un extrait / une collection", keys: "⌘N / ⌘⇧N")
                shortcut("Supprimer / annuler", keys: "⌫ / ⌘Z")
                shortcut("Pause / réglages", keys: "⌘T / ⌘,")
            }
            Section("Recherche avancée") {
                Text("app:safari   type:image   date:today\nafter:2026-10-01   before:2026-11-01").font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                Text("Les mots se combinent. La recherche ignore les accents et trouve aussi le texte reconnu dans les images.").font(.system(size: 10)).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private func shortcut(_ title: String, keys: String) -> some View {
        HStack { Text(title).font(.system(size: 11)); Spacer(); Text(keys).font(.system(size: 11, design: .monospaced)).foregroundStyle(.secondary) }
    }
}
