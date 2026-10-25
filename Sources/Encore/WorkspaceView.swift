import SwiftUI
import EncoreCore

struct WorkspaceView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 18) {
                EncoreMark(size: 25)
                Text(L("Bibliothèque")).font(.system(size: 18, weight: .semibold))
                Spacer(minLength: 12)
                HStack(spacing: 8) {
                    Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                    TextField(L("Rechercher dans l’historique"), text: $model.query).textFieldStyle(.plain).focused($searchFocused).accessibilityLabel(L("Rechercher dans l’historique"))
                    if !model.query.isEmpty { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill") }.buttonStyle(.plain).foregroundStyle(.secondary) }
                    Text("⌘F").font(.system(size: 12)).foregroundStyle(.secondary)
                }.padding(11).frame(maxWidth: 580).background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 10))
                Spacer(minLength: 12)
                Button { model.expanded = false } label: { Label(L("Réduire"), systemImage: "arrow.down.right.and.arrow.up.left") }.keyboardShortcut(.downArrow, modifiers: [])
                Button { model.showSettings?() } label: { Image(systemName: "gearshape") }.buttonStyle(.plain).help(L("Réglages")).accessibilityLabel(L("Réglages"))
                Button { model.dismissPanel?() } label: { Image(systemName: "xmark") }.buttonStyle(.plain).help(L("Fermer"))
            }.padding(20)
            Divider()
            HSplitView {
                filters.frame(minWidth: 165, idealWidth: 190, maxWidth: 230)
                results.frame(minWidth: 300, maxWidth: .infinity)
                detail.frame(minWidth: 270, idealWidth: 390, maxWidth: 550)
            }
            Divider()
            HStack(spacing: 16) {
                Text(L("\(model.filtered.count) résultat(s)")).monospacedDigit()
                Spacer()
                Text(L("← → sélectionner · ↩ coller · espace éditer · ↓ réduire"))
            }.font(.system(size: 12)).foregroundStyle(.secondary).padding(.horizontal, 20).padding(.vertical, 12)
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.12)))
        .onChange(of: model.searchFocused) { _, value in searchFocused = value }
        .onChange(of: searchFocused) { _, value in model.searchFocused = value }
        .onAppear { searchFocused = model.searchFocused }
    }

    private var filters: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 7) {
                filterButton(L("Historique"), icon: "clock.arrow.circlepath", selected: model.board == "history") { model.board = "history" }
                filterButton(L("Favoris"), icon: "star", selected: model.board == "favorites") { model.board = "favorites" }
                ForEach(model.library.collections) { collection in
                    filterButton(collection.name, icon: "circle.fill", selected: model.board == collection.id.uuidString) { model.board = collection.id.uuidString }
                }
                Divider().padding(.vertical, 10)
                Text(L("Type")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                filterButton(L("Tous les types"), icon: "square.grid.2x2", selected: model.kind == nil) { model.kind = nil }
                ForEach(ClipKind.allCases) { kind in
                    filterButton(kind.title, icon: kind.symbol, selected: model.kind == kind) { model.kind = kind }
                }
                Divider().padding(.vertical, 10)
                Text(L("Application")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary)
                Picker(L("Application"), selection: $model.source) {
                    Text(L("Toutes les applications")).tag(String?.none)
                    ForEach(model.sources, id: \.0) { app in Text(app.1).tag(Optional(app.0)) }
                }.labelsHidden()
                Text(L("Dates")).font(.system(size: 12, weight: .semibold)).foregroundStyle(.secondary).padding(.top, 12)
                Button(L("Aujourd’hui")) { setDate("today") }.buttonStyle(.plain)
                Button(L("Cette semaine")) { setDate("week") }.buttonStyle(.plain)
                Button(L("Toutes les dates")) { setDate(nil) }.buttonStyle(.plain)
                Button(L("Effacer les filtres")) { model.kind = nil; model.source = nil; model.query = ""; model.board = "history" }.padding(.top, 15)
            }.font(.system(size: 13)).padding(14)
        }.background(.primary.opacity(0.02))
    }

    private func filterButton(_ title: String, icon: String, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: icon).frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 10).padding(.vertical, 8)
                .background(selected ? Palette.accent.opacity(0.15) : .clear, in: RoundedRectangle(cornerRadius: 7))
                .foregroundStyle(selected ? Palette.accent : .primary)
        }.buttonStyle(.plain)
    }

    private func setDate(_ value: String?) {
        let words = model.query.split(separator: " ").filter { !$0.hasPrefix("date:") && !$0.hasPrefix("after:") && !$0.hasPrefix("before:") }
        model.query = (words.map(String.init) + (value.map { ["date:\($0)"] } ?? [])).joined(separator: " ")
    }

    private var results: some View {
        ScrollViewReader { reader in
            ScrollView {
                LazyVStack(spacing: 6) {
                    if model.filtered.isEmpty {
                        ContentUnavailableView(L("Aucun élément trouvé"), systemImage: "magnifyingglass", description: Text(L("Essayez un autre mot ou retirez les filtres."))).padding(.top, 60)
                    }
                    ForEach(model.filtered) { clip in
                        resultRow(clip).id(clip.id)
                    }
                }.padding(12)
            }.onChange(of: model.cursor) { _, id in if let id { reader.scrollTo(id, anchor: .center) } }
        }
    }

    private func resultRow(_ clip: Clip) -> some View {
        HStack(spacing: 12) {
            Image(nsImage: ApplicationCatalog.app(clip.sourceBundle).icon).resizable().frame(width: 34, height: 34)
            VStack(alignment: .leading, spacing: 5) {
                Text(clip.displayTitle).font(.system(size: 14, weight: .medium)).lineLimit(1)
                Text(clip.text.isEmpty ? clip.kind.title : String(clip.text.prefix(180))).font(.system(size: 12)).foregroundStyle(.secondary).lineLimit(2)
            }
            Spacer(minLength: 4)
            VStack(alignment: .trailing, spacing: 6) {
                Text(model.relativeAge(clip.firstCopyDate)).font(.system(size: 11)).foregroundStyle(.secondary)
                if clip.favorite { Image(systemName: "star.fill").foregroundStyle(.orange) }
            }
        }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            .background(model.selection.contains(clip.id) ? Palette.accent.opacity(0.13) : .primary.opacity(0.025), in: RoundedRectangle(cornerRadius: 10))
            .contentShape(Rectangle())
            .onTapGesture(count: 2) { model.select(clip.id); model.paste([clip]) }
            .onTapGesture { model.select(clip.id, modifiers: NSEvent.modifierFlags) }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction { model.select(clip.id) }
    }

    private var detail: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let clip = model.selected {
                HStack {
                    Label(clip.kind.title, systemImage: clip.kind.symbol).foregroundStyle(Palette.accent)
                    Spacer()
                    Button { model.toggleFavorite([clip.id]) } label: { Image(systemName: clip.favorite ? "star.fill" : "star") }.buttonStyle(.plain)
                }.font(.system(size: 14, weight: .semibold))
                Group {
                    if clip.kind == .file {
                        FilePreview(previews: model.filePreviews, clip: clip, urls: model.fileURLs(for: clip), fitContent: true)
                    } else if clip.kind == .image, let image = model.image(for: clip) {
                        Image(nsImage: image).resizable().scaledToFit()
                    } else {
                        ScrollView { Text(clip.text).font(.system(size: 14, design: clip.kind == .code ? .monospaced : .default)).textSelection(.enabled).frame(maxWidth: .infinity, alignment: .topLeading) }
                    }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
                Text(model.remainingRetention(for: clip)).font(.system(size: 12)).foregroundStyle(.secondary)
                HStack {
                    Button(L("Aperçu et édition")) { model.inspector = clip }
                    Spacer()
                    Button(L("Coller")) { model.paste() }.buttonStyle(.borderedProminent)
                }
            } else { Spacer(); Text(L("Sélectionnez un élément")).foregroundStyle(.secondary); Spacer() }
        }.padding(20)
    }
}
