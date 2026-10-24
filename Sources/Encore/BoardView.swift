import AppKit
import SwiftUI
import EncoreCore

enum Palette {
    static let accent = Color(red: 0.56, green: 0.37, blue: 0.96)
    static let collection: [Color] = [accent, .pink, .teal, .orange, .blue]
    static func color(_ hex: String) -> Color {
        var value = hex.trimmingCharacters(in: .whitespacesAndNewlines).trimmingCharacters(in: CharacterSet(charactersIn: "#"))
        if value.count == 3 || value.count == 4 { value = value.map { "\($0)\($0)" }.joined() }
        let number = UInt64(value, radix: 16) ?? 0xA78BFA
        if value.count == 8 { return Color(.sRGB, red: Double((number >> 24) & 255) / 255, green: Double((number >> 16) & 255) / 255, blue: Double((number >> 8) & 255) / 255, opacity: Double(number & 255) / 255) }
        return Color(red: Double((number >> 16) & 255) / 255, green: Double((number >> 8) & 255) / 255, blue: Double(number & 255) / 255)
    }
    static func accent(_ kind: ClipKind) -> Color {
        switch kind {
        case .text: Color(red: 0.88, green: 0.57, blue: 0.26)
        case .code: Color(red: 0.57, green: 0.48, blue: 0.95)
        case .link: Color(red: 0.15, green: 0.65, blue: 0.61)
        case .color: .pink
        case .image: Color(red: 0.35, green: 0.61, blue: 0.91)
        case .file: .blue
        }
    }
}

struct EncoreMark: View {
    var size: CGFloat = 28
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.22).fill(Palette.accent.opacity(0.3)).frame(width: size * 0.7, height: size * 0.8).rotationEffect(.degrees(-16)).offset(x: -size * 0.12, y: -size * 0.04)
            RoundedRectangle(cornerRadius: size * 0.22).fill(LinearGradient(colors: [Color(red: 0.78, green: 0.63, blue: 1), Palette.accent], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: size * 0.7, height: size * 0.8).rotationEffect(.degrees(9)).offset(x: size * 0.1, y: size * 0.05)
            Image(systemName: "arrow.uturn.backward").font(.system(size: size * 0.36, weight: .bold)).foregroundStyle(.white).offset(x: size * 0.1, y: size * 0.05)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

struct BoardView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocus: Bool
    @Environment(\.colorScheme) private var scheme
    @State private var dragHeight: Double?
    private var compact: Bool { model.preferences.compact }

    var body: some View {
        VStack(spacing: 0) {
            Capsule().fill(.secondary.opacity(0.35)).frame(width: 40, height: 4).padding(.top, 7).padding(.bottom, 3)
                .frame(maxWidth: .infinity).contentShape(Rectangle())
                .gesture(DragGesture().onChanged { gesture in
                    if dragHeight == nil { dragHeight = model.preferences.panelHeight }
                    model.preferences.panelHeight = min(650, max(280, (dragHeight ?? 380) - gesture.translation.height))
                    model.resizePanel?()
                }.onEnded { _ in dragHeight = nil; model.preferencesChanged() })
                .help("Glissez pour ajuster la hauteur")
            toolbar
            if let error = model.storageError {
                Label("Sauvegarde indisponible : \(error)", systemImage: "exclamationmark.triangle").font(.system(size: 11)).foregroundStyle(.red).padding(.horizontal, 24).padding(.bottom, 8)
            }
            HStack(spacing: 0) {
                if model.filtered.isEmpty { emptyState.frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { cards }
                if model.queueVisible { queueSidebar }
            }
            footer
        }
        .background(.ultraThinMaterial)
        .background(scheme == .dark ? Color(red: 0.08, green: 0.075, blue: 0.105).opacity(0.92) : Color(red: 0.97, green: 0.965, blue: 0.985).opacity(0.94))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(scheme == .dark ? 0.14 : 0.7), lineWidth: 1))
        .tint(Palette.accent)
        .onChange(of: model.searchFocused) { _, value in searchFocus = value }
        .onChange(of: searchFocus) { _, value in model.searchFocused = value }
        .sheet(item: $model.inspector) { clip in InspectorView(model: model, clip: clip) }
    }

    private var toolbar: some View {
        HStack(spacing: 14) {
            HStack(spacing: 8) {
                EncoreMark()
                Text("encore").font(.system(size: 21, weight: .bold, design: .rounded)).tracking(-0.6)
            }.padding(.trailing, 4)
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    boardButton("Historique", symbol: "clock.arrow.circlepath", id: "history", color: Palette.accent)
                    boardButton("Favoris", symbol: "star", id: "favorites", color: .orange)
                    ForEach(model.library.collections) { collection in
                        boardButton(collection.name, symbol: "circle.fill", id: collection.id.uuidString, color: Palette.collection[collection.colorIndex % Palette.collection.count])
                            .contextMenu {
                                Button("Supprimer la collection", role: .destructive) { model.deleteCollection(collection) }
                            }
                            .onDrop(of: ["local.kama.encore.clip-id"], isTargeted: nil) { providers in
                                guard let provider = providers.first else { return false }
                                provider.loadDataRepresentation(forTypeIdentifier: "local.kama.encore.clip-id") { data, _ in
                                    guard let data, let value = String(data: data, encoding: .utf8), let id = UUID(uuidString: value) else { return }
                                    DispatchQueue.main.async { model.assignCollection(collection.id, ids: [id], toggle: false) }
                                }
                                return true
                            }
                    }
                    Button { model.createCollection() } label: { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 30) }
                        .buttonStyle(.plain).help("Créer une collection · ⌘⇧N").accessibilityLabel("Nouvelle collection")
                }
            }.frame(minWidth: 180)
            searchBar.frame(width: 240)
            Menu {
                Button("Tous les types") { model.kind = nil }
                ForEach(ClipKind.allCases) { kind in
                    Button { model.kind = kind } label: { Label(kind.title, systemImage: kind.symbol) }
                }
                Divider()
                Button("Toutes les applications") { model.source = nil }
                ForEach(model.sources, id: \.0) { source in Button(source.1) { model.source = source.0 } }
            } label: {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 15)).foregroundStyle(model.kind != nil || model.source != nil ? Palette.accent : .secondary)
            }.menuStyle(.borderlessButton).frame(width: 22).help("Filtrer par type ou application").accessibilityLabel("Filtres")
            toolButton("rectangle.stack", help: "File de collage", active: model.queueVisible) { withAnimation(.easeInOut(duration: 0.18)) { model.queueVisible.toggle() } }
            toolButton("gearshape", help: "Réglages · ⌘,") { model.showSettings?() }
            toolButton("xmark", help: "Fermer · Échap") { model.dismissPanel?() }
        }.padding(.horizontal, 23).padding(.top, 5).padding(.bottom, 15)
    }

    private func boardButton(_ title: String, symbol: String, id: String, color: Color) -> some View {
        Button { model.board = id } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: symbol == "circle.fill" ? 7 : 12, weight: .medium)).foregroundStyle(model.board == id ? color : .secondary)
                Text(title).font(.system(size: 12, weight: model.board == id ? .semibold : .medium)).lineLimit(1)
            }
            .padding(.horizontal, 11).frame(height: 31)
            .background(model.board == id ? color.opacity(0.13) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(model.board == id ? color.opacity(0.23) : .clear))
        }.buttonStyle(.plain).accessibilityAddTraits(model.board == id ? [.isSelected] : [])
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Rechercher…", text: $model.query).textFieldStyle(.plain).font(.system(size: 12)).focused($searchFocus)
                .accessibilityLabel("Rechercher dans l’historique")
            if model.query.isEmpty { Text("⌘F").font(.system(size: 10, design: .monospaced)).foregroundStyle(.tertiary) }
            else { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel("Effacer la recherche") }
        }.padding(.horizontal, 10).frame(height: 32)
            .background(.primary.opacity(0.045), in: RoundedRectangle(cornerRadius: 10))
            .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(searchFocus ? Palette.accent.opacity(0.65) : .primary.opacity(0.06)))
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 13) {
                    ForEach(Array(model.filtered.enumerated()), id: \.element.id) { index, clip in
                        ClipCard(model: model, clip: clip, index: index, compact: compact)
                            .id(clip.id)
                    }
                }.padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 13)
            }
            .onChange(of: model.cursor) { _, id in
                guard let id else { return }
                withAnimation(.easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: model.library.clips.isEmpty ? "doc.on.clipboard" : "magnifyingglass").font(.system(size: 32, weight: .light)).foregroundStyle(Palette.accent).padding(.bottom, 3)
            Text(model.library.clips.isEmpty ? "Vos idées, à portée de clavier." : "Aucun élément trouvé").font(.system(size: 21, weight: .semibold, design: .rounded))
            Text(model.library.clips.isEmpty ? "Copiez un texte, un lien ou une image. Retrouvez-le ici avec \(model.shortcutStatus)." : "Essayez un autre mot ou retirez les filtres.").font(.system(size: 12)).foregroundStyle(.secondary)
            if model.kind != nil || model.source != nil || !model.query.isEmpty {
                Button("Effacer les filtres") { model.kind = nil; model.source = nil; model.query = "" }.buttonStyle(.bordered)
            } else if !model.accessibilityGranted {
                Button("Activer le collage direct") { model.requestAccessibility() }.buttonStyle(.borderedProminent).padding(.top, 6)
                Text("Sans autorisation, Encore recopie les éléments ; vous les collez avec ⌘V.").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
        }.padding(24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Circle().fill(model.preferences.captureEnabled ? Color.green : Color.orange).frame(width: 5, height: 5)
            Text(model.preferences.captureEnabled ? "\(model.filtered.count) élément\(model.filtered.count == 1 ? "" : "s")" : "Capture en pause").font(.system(size: 10, weight: .medium))
            if let kind = model.kind {
                Button { model.kind = nil } label: { Label(kind.title, systemImage: "xmark.circle.fill").font(.system(size: 10)) }.buttonStyle(.plain).foregroundStyle(Palette.accent)
            }
            if let source = model.source {
                Button { model.source = nil } label: { Label(model.sources.first { $0.0 == source }?.1 ?? source, systemImage: "xmark.circle.fill").font(.system(size: 10)) }.buttonStyle(.plain).foregroundStyle(Palette.accent)
            }
            if !model.status.isEmpty { Text(model.status).font(.system(size: 11)).foregroundStyle(Palette.accent).lineLimit(1) }
            Spacer(minLength: 4)
            if model.status.isEmpty {
                hint("← →", "naviguer")
                hint("↩", "coller")
                hint("⇧↩", "texte brut")
                hint("espace", "aperçu")
            }
            Text("100 % local").font(.system(size: 9, weight: .medium)).foregroundStyle(.tertiary).padding(.leading, 4)
        }.foregroundStyle(.secondary).padding(.horizontal, 25).frame(height: 33)
            .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.06)).frame(height: 1).padding(.horizontal, 24) }
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(keys).font(.system(size: 9, weight: .medium, design: .monospaced)).padding(.horizontal, 4).padding(.vertical, 2).background(.primary.opacity(0.055), in: RoundedRectangle(cornerRadius: 3))
            Text(label).font(.system(size: 9))
        }
    }

    private func toolButton(_ symbol: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(active ? Palette.accent : .secondary).frame(width: 22, height: 28) }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private var queueSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label("File de collage", systemImage: "rectangle.stack").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(model.queue.count)").font(.system(size: 10, weight: .bold)).foregroundStyle(Palette.accent)
            }
            Text(model.collecting ? "Copiez pour ajouter · ⌘V pour coller" : "Ajoutez des cartes, puis activez la file.").font(.system(size: 10)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(Array(model.queue.enumerated()), id: \.element) { index, id in
                        if let clip = model.library.clips.first(where: { $0.id == id }) {
                            HStack(spacing: 7) {
                                Text("\(index + 1)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(Palette.accent)
                                Text(clip.displayTitle).font(.system(size: 11)).lineLimit(1)
                                Spacer(minLength: 0)
                                Button { model.queue.removeAll { $0 == id } } label: { Image(systemName: "xmark").font(.system(size: 9)) }.buttonStyle(.plain).accessibilityLabel("Retirer de la file")
                            }.padding(9).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            HStack {
                Button(model.collecting ? "Arrêter" : "Activer") { model.toggleCollecting() }.buttonStyle(.borderedProminent).controlSize(.small)
                Spacer()
                Button { model.queue.reverse() } label: { Image(systemName: "arrow.up.arrow.down") }.buttonStyle(.plain).help("Inverser l’ordre")
                Button { model.queue = []; model.collecting = false } label: { Image(systemName: "trash") }.buttonStyle(.plain).help("Vider la file")
            }
        }.padding(14).frame(width: 235).background(.primary.opacity(0.025)).overlay(alignment: .leading) { Rectangle().fill(.primary.opacity(0.07)).frame(width: 1) }.padding(.bottom, 10)
    }
}

struct ClipCard: View {
    @ObservedObject var model: AppModel
    let clip: Clip
    let index: Int
    let compact: Bool
    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false
    private var selected: Bool { model.selection.contains(clip.id) }
    private var accent: Color { Palette.accent(clip.kind) }
    private var ids: Set<UUID> { selected ? model.selection : [clip.id] }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 6) {
                sourceIcon.frame(width: 16, height: 16)
                Text(clip.sourceName).font(.system(size: 10, weight: .medium)).lineLimit(1).foregroundStyle(.secondary)
                Spacer(minLength: 2)
                if clip.favorite { Image(systemName: "star.fill").font(.system(size: 10)).foregroundStyle(.orange) }
                if !clip.collectionIDs.isEmpty { Image(systemName: "folder.fill").font(.system(size: 9)).foregroundStyle(Palette.accent) }
                if index < 9 { Text("⌘\(index + 1)").font(.system(size: 10, weight: .semibold, design: .monospaced)).foregroundStyle(selected ? Palette.accent : .secondary) }
            }.padding(.horizontal, 14).frame(height: 37)
            cardContent.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            HStack {
                Label(clip.kind.title, systemImage: clip.kind.symbol).font(.system(size: 9, weight: .medium)).foregroundStyle(accent)
                Spacer()
                Text(clip.copiedAt, style: .relative).font(.system(size: 9)).foregroundStyle(.tertiary).lineLimit(1)
            }.padding(.horizontal, 14).frame(height: 29)
        }
        .frame(width: compact ? 200 : 246)
        .background(scheme == .dark ? Color(red: 0.14, green: 0.14, blue: 0.18) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Palette.accent : .primary.opacity(hovered ? 0.18 : 0.07), lineWidth: selected ? 2 : 1))
        .shadow(color: .black.opacity(scheme == .dark ? 0.14 : 0.05), radius: 6, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { model.select(clip.id); model.paste([clip], plain: NSEvent.modifierFlags.contains(.shift)) }
        .onTapGesture { model.select(clip.id, modifiers: NSEvent.modifierFlags) }
        .contextMenu { contextActions }
        .onDrag { itemProvider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(clip.kind.title), \(clip.displayTitle), \(clip.sourceName)")
        .accessibilityValue(selected ? "Sélectionné" : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.select(clip.id) }
    }

    @ViewBuilder private var sourceIcon: some View {
        if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: clip.sourceBundle) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().interpolation(.high)
        } else { Image(systemName: "app.fill").resizable().foregroundStyle(accent) }
    }

    @ViewBuilder private var cardContent: some View {
        switch clip.kind {
        case .color:
            ZStack {
                Palette.color(clip.text)
                VStack(spacing: 7) {
                    Text(clip.text.uppercased()).font(.system(size: 30, weight: .medium, design: .rounded)).tracking(-1)
                    Text("Un peu de couleur.").font(.system(size: 11)).opacity(0.75)
                }.foregroundStyle(.white).shadow(color: .black.opacity(0.25), radius: 4, y: 1)
            }.clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 8)
        case .link:
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [accent.opacity(0.9), Color(red: 0.08, green: 0.28, blue: 0.35)], startPoint: .topTrailing, endPoint: .bottomLeading)
                    Image(systemName: "globe.europe.africa.fill").font(.system(size: 82, weight: .ultraLight)).foregroundStyle(.white.opacity(0.13)).frame(maxWidth: .infinity, alignment: .trailing).padding(8)
                    Image(systemName: "arrow.up.right").font(.system(size: 25, weight: .light)).foregroundStyle(.white).padding(16)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.displayTitle).font(.system(size: 14, weight: .semibold)).lineLimit(1)
                    Text(URL(string: clip.text)?.path.removingPercentEncoding ?? clip.text).font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(2)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }.background(accent.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 8)
        case .image:
            if let image = model.image(for: clip) {
                ZStack { Color.primary.opacity(0.025); Image(nsImage: image).resizable().scaledToFit().padding(6) }.clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 8)
            } else { Image(systemName: "photo").font(.system(size: 36)).foregroundStyle(.secondary) }
        case .file:
            VStack(spacing: 12) {
                Image(systemName: clip.fileNames.count > 1 ? "doc.on.doc.fill" : "doc.fill").font(.system(size: 45, weight: .light)).foregroundStyle(accent.gradient)
                Text(clip.displayTitle).font(.system(size: 13, weight: .medium)).lineLimit(2).multilineTextAlignment(.center)
                if clip.fileNames.count > 1 { Text("\(clip.fileNames.count) fichiers").font(.system(size: 10)).foregroundStyle(.secondary) }
            }.padding(18)
        case .code:
            VStack(alignment: .leading, spacing: 8) {
                if !clip.title.isEmpty { Text(clip.title).font(.system(size: 12, weight: .semibold)) }
                Text(highlightedCode(clip.text)).font(.system(size: compact ? 10 : 11, design: .monospaced)).lineSpacing(4).lineLimit(compact ? 7 : 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.padding(13).background(Palette.accent.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 8)
        case .text:
            VStack(alignment: .leading, spacing: 7) {
                if !clip.title.isEmpty { Text(clip.title).font(.system(size: 14, weight: .semibold)).lineLimit(1) }
                Text(String(clip.text.prefix(3000))).font(.system(size: compact ? 12 : 14)).lineSpacing(5).lineLimit(compact ? 5 : 10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.padding(15).background(accent.opacity(scheme == .dark ? 0.055 : 0.035)).clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 8)
        }
    }

    @ViewBuilder private var contextActions: some View {
        Button("Coller") { model.paste(model.library.clips.filter { ids.contains($0.id) }) }
        Button("Coller en texte brut") { model.paste(model.library.clips.filter { ids.contains($0.id) }, plain: true) }
        Button("Copier") { model.paste(model.library.clips.filter { ids.contains($0.id) }, copyOnly: true) }
        Divider()
        Button(clip.favorite ? "Retirer des favoris" : "Ajouter aux favoris") { model.toggleFavorite(ids) }
        Menu("Collections") {
            ForEach(model.library.collections) { collection in
                Button { model.assignCollection(collection.id, ids: ids) } label: {
                    Label(collection.name, systemImage: clip.collectionIDs.contains(collection.id) ? "checkmark" : "folder")
                }
            }
            Divider()
            Button("Nouvelle collection…") { model.createCollection() }
        }
        Button("Ajouter à la file") { model.enqueue(model.filtered.filter { ids.contains($0.id) }.map(\.id)) }
        Button("Aperçu et édition") { model.inspector = clip }
        if !clip.text.isEmpty {
            Menu("Transformer une copie") { ForEach(TextAction.allCases) { action in Button(action.title) { model.transform(action, clip: clip) } } }
        }
        if clip.kind == .image {
            Button("Reconnaître le texte") { model.recognize(clip.id) }
            if !clip.recognizedText.isEmpty { Button("Créer un texte depuis l’image") { model.addText(clip.recognizedText) } }
        }
        Divider()
        Button("Supprimer", role: .destructive) { model.remove(ids) }
    }

    private func itemProvider() -> NSItemProvider {
        let provider = NSItemProvider()
        provider.registerDataRepresentation(forTypeIdentifier: "local.kama.encore.clip-id", visibility: .ownProcess) { completion in completion(Data(clip.id.uuidString.utf8), nil); return nil }
        if let payload = model.storage?.payload(clip.id), let item = payload.items.first {
            for (type, data) in item.representations {
                provider.registerDataRepresentation(forTypeIdentifier: type, visibility: .all) { completion in completion(data, nil); return nil }
            }
        }
        provider.suggestedName = clip.displayTitle
        return provider
    }

    private func highlightedCode(_ source: String) -> AttributedString {
        var value = AttributedString(String(source.prefix(3000)))
        value.foregroundColor = scheme == .dark ? Color(red: 0.79, green: 0.81, blue: 0.9) : Color(red: 0.23, green: 0.24, blue: 0.34)
        for word in ["struct", "class", "func", "let", "var", "import", "return", "const", "def", "true", "false", "nil", "if", "else", "public", "private"] {
            let text = String(value.characters)
            if let regex = try? NSRegularExpression(pattern: "\\b\(word)\\b") {
                for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                    if let range = Range(match.range, in: text), let lower = AttributedString.Index(range.lowerBound, within: value), let upper = AttributedString.Index(range.upperBound, within: value) { value[lower..<upper].foregroundColor = Palette.accent }
                }
            }
        }
        return value
    }
}
