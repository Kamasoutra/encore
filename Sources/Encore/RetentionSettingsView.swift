import SwiftUI
import EncoreCore

struct RetentionSettingsView: View {
    @ObservedObject var model: AppModel
    @State private var rules: [RetentionRule] = []
    @State private var fallbackDays = 30
    @State private var confirm = false
    @State private var loaded = false
    private var valid: Bool { rules.allSatisfy(\.isValid) }
    private var changed: Bool { rules != model.preferences.retentionRules || fallbackDays != model.preferences.retentionDays }
    private var removalCount: Int { valid ? model.retentionRemovalCount(rules: rules, fallbackDays: fallbackDays) : 0 }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack {
                Label("Règles de conservation", systemImage: "line.3.horizontal.decrease").font(.system(size: 13, weight: .semibold))
                Spacer()
                Menu("Exemples") {
                    Button("Charger les paliers taille / durée") { rules = RetentionRule.examples }
                    Button("Retirer toutes les règles") { rules = [] }
                }.fixedSize()
                Button { rules.append(RetentionRule()) } label: { Image(systemName: "plus") }.help("Ajouter une règle")
            }
            ScrollView {
                VStack(spacing: 10) {
                    if rules.isEmpty {
                        VStack(spacing: 8) {
                            Image(systemName: "clock.badge.checkmark").font(.system(size: 28)).foregroundStyle(Palette.accent)
                            Text("Votre historique, à votre rythme.").font(.system(size: 15, weight: .medium))
                            Text("Par exemple : 3 Go pendant une heure, 500 Mo pendant deux jours, les petits textes indéfiniment.").font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                            Button("Utiliser ces exemples") { rules = RetentionRule.examples }.buttonStyle(.bordered)
                        }.padding(25).frame(maxWidth: .infinity)
                    }
                    ForEach(Array(rules.enumerated()), id: \.element.id) { index, rule in
                        if let binding = binding(rule.id) {
                            RetentionRuleEditor(rule: binding, index: index, canMoveUp: index > 0, canMoveDown: index + 1 < rules.count, move: { delta in rules.swapAt(index, index + delta) }, remove: { rules.removeAll { $0.id == rule.id } })
                        }
                    }
                }.padding(1)
            }
            HStack {
                Text("Sans règle correspondante").font(.system(size: 13))
                Spacer()
                Picker("Durée par défaut", selection: $fallbackDays) {
                    Text("7 jours").tag(7); Text("30 jours").tag(30); Text("90 jours").tag(90); Text("1 an").tag(365); Text("Indéfiniment").tag(0)
                }.labelsHidden().frame(width: 155)
            }
            Text("Favoris et collections restent conservés. La limite de nombre ne s’applique qu’aux éléments sans règle. Un fichier expire de l’historique, jamais de son dossier d’origine.").font(.system(size: 12)).foregroundStyle(.secondary)
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    if !valid { Label("Corrigez les bornes ou la durée.", systemImage: "exclamationmark.circle").foregroundStyle(.red) }
                    else { Text(removalCount == 0 ? "Aucune suppression immédiate." : "\(removalCount) élément(s) expireraient immédiatement.").foregroundStyle(removalCount > 0 ? .orange : .secondary) }
                    Text("Le délai repart à chaque nouvelle copie.").foregroundStyle(.secondary)
                }.font(.system(size: 12))
                Spacer()
                Button("Annuler") { load() }.disabled(!changed)
                Button("Appliquer") {
                    if removalCount > 0 { confirm = true } else { apply() }
                }.buttonStyle(.borderedProminent).disabled(!valid || !changed)
            }
        }.padding(24).onAppear { if !loaded { load(); loaded = true } }
            .alert("Appliquer les règles ?", isPresented: $confirm) {
                Button("Annuler", role: .cancel) {}
                Button("Appliquer et supprimer \(removalCount) élément(s)", role: .destructive) { apply() }
            } message: { Text("Les éléments déjà expirés seront retirés de l’historique. Leurs fichiers d’origine restent intacts.") }
    }

    private func binding(_ id: UUID) -> Binding<RetentionRule>? {
        guard let index = rules.firstIndex(where: { $0.id == id }) else { return nil }
        let original = rules[index]
        return Binding(get: { rules.first(where: { $0.id == id }) ?? original }, set: { value in if let index = rules.firstIndex(where: { $0.id == id }) { rules[index] = value } })
    }
    private func load() { rules = model.preferences.retentionRules; fallbackDays = model.preferences.retentionDays }
    private func apply() { model.applyRetention(rules: rules, fallbackDays: fallbackDays) }
}

private enum SizeUnit: Int64, CaseIterable, Identifiable {
    case octets = 1, ko = 1000, mo = 1_000_000, go = 1_000_000_000, to = 1_000_000_000_000
    var id: Int64 { rawValue }
    var title: String {
        switch self { case .octets: "o"; case .ko: "ko"; case .mo: "Mo"; case .go: "Go"; case .to: "To" }
    }
    static func preferred(for bytes: Int64) -> SizeUnit { allCases.reversed().first { bytes >= $0.rawValue } ?? .mo }
}

private struct RetentionRuleEditor: View {
    @Binding var rule: RetentionRule
    let index: Int
    let canMoveUp: Bool
    let canMoveDown: Bool
    let move: (Int) -> Void
    let remove: () -> Void
    @State private var minUnit: SizeUnit
    @State private var maxUnit: SizeUnit

    init(rule: Binding<RetentionRule>, index: Int, canMoveUp: Bool, canMoveDown: Bool, move: @escaping (Int) -> Void, remove: @escaping () -> Void) {
        _rule = rule; self.index = index; self.canMoveUp = canMoveUp; self.canMoveDown = canMoveDown; self.move = move; self.remove = remove
        _minUnit = State(initialValue: .preferred(for: rule.wrappedValue.minimumBytes))
        _maxUnit = State(initialValue: .preferred(for: rule.wrappedValue.maximumBytes ?? 1_000_000_000))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 8) {
                Text("\(index + 1)").font(.system(size: 11, weight: .semibold)).foregroundStyle(Palette.accent).frame(width: 20, height: 20).background(Palette.accent.opacity(0.12), in: Circle())
                Toggle("Activer", isOn: $rule.enabled).labelsHidden().toggleStyle(.switch).controlSize(.mini)
                TextField("Nom de la règle", text: $rule.name).textFieldStyle(.plain).font(.system(size: 13, weight: .semibold))
                Button { move(-1) } label: { Image(systemName: "chevron.up") }.disabled(!canMoveUp).help("Monter la règle")
                Button { move(1) } label: { Image(systemName: "chevron.down") }.disabled(!canMoveDown).help("Descendre la règle")
                Button(role: .destructive, action: remove) { Image(systemName: "trash") }.help("Supprimer la règle")
            }.buttonStyle(.borderless)
            HStack(spacing: 8) {
                Picker("Type", selection: $rule.kind) {
                    Text("Tous les types").tag(ClipKind?.none)
                    ForEach(ClipKind.allCases) { kind in Text(kind.title).tag(Optional(kind)) }
                }.labelsHidden().frame(width: 120)
                Text("de").foregroundStyle(.secondary)
                sizeField(bytes: $rule.minimumBytes, unit: $minUnit)
                Toggle("à", isOn: Binding(get: { rule.maximumBytes != nil }, set: { rule.maximumBytes = $0 ? max(min(rule.minimumBytes, Int64.max - 1) + 1, 1_000_000_000) : nil })).toggleStyle(.checkbox)
                if rule.maximumBytes != nil {
                    sizeField(bytes: Binding(get: { rule.maximumBytes ?? 0 }, set: { rule.maximumBytes = $0 }), unit: $maxUnit)
                } else { Text("sans plafond").foregroundStyle(.secondary) }
            }
            HStack(spacing: 8) {
                Label("Conserver", systemImage: "clock").foregroundStyle(.secondary)
                if rule.duration.unit != .forever {
                    TextField("Durée", value: $rule.duration.value, format: .number).textFieldStyle(.roundedBorder).frame(width: 56)
                }
                Picker("Unité de durée", selection: $rule.duration.unit) { ForEach(RetentionUnit.allCases) { unit in Text(unit.title).tag(unit) } }.labelsHidden().frame(width: 135)
                Spacer()
                Text("Minimum inclus · maximum exclu").font(.system(size: 11)).foregroundStyle(.secondary)
            }
        }.font(.system(size: 12)).padding(13)
            .background(Color(nsColor: .controlBackgroundColor), in: RoundedRectangle(cornerRadius: 12))
            .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(rule.isValid ? Color.primary.opacity(0.09) : .red.opacity(0.65)))
            .opacity(rule.enabled ? 1 : 0.6)
    }

    private func sizeField(bytes: Binding<Int64>, unit: Binding<SizeUnit>) -> some View {
        HStack(spacing: 3) {
            TextField("Taille", value: Binding(get: { Double(bytes.wrappedValue) / Double(unit.wrappedValue.rawValue) }, set: { value in
                let scaled = value * Double(unit.wrappedValue.rawValue)
                if scaled.isFinite && scaled >= 0 && scaled < Double(Int64.max - 1) { bytes.wrappedValue = Int64(scaled.rounded()) }
            }), format: .number.precision(.fractionLength(0...3))).textFieldStyle(.roundedBorder).frame(width: 65)
            Picker("Unité", selection: unit) { ForEach(SizeUnit.allCases) { value in Text(value.title).tag(value) } }.labelsHidden().frame(width: 53)
        }
    }
}
