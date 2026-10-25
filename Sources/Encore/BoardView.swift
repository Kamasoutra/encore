import AppKit
import SwiftUI
import EncoreCore
import UniformTypeIdentifiers

extension View {
    func localized() -> some View { environment(\.locale, Localization.locale).environment(\.layoutDirection, Localization.isRightToLeft ? .rightToLeft : .leftToRight) }
}

enum Palette {
    static let accent = Color(red: 0.56, green: 0.37, blue: 0.96)
    static let collection: [Color] = [accent, .pink, .teal, .orange, .blue]
    static func swatchText(_ hex: String, dark: Bool) -> Color {
        guard let color = NSColor(Self.color(hex)).usingColorSpace(.sRGB) else { return .primary }
        let background = dark ? 0.14 : 1.0
        let channels = [color.redComponent, color.greenComponent, color.blueComponent].map { component -> Double in
            let value = Double(component * color.alphaComponent) + background * Double(1 - color.alphaComponent)
            return value <= 0.04045 ? value / 12.92 : pow((value + 0.055) / 1.055, 2.4)
        }
        let luminance = channels[0] * 0.2126 + channels[1] * 0.7152 + channels[2] * 0.0722
        return luminance > 0.179 ? .black : .white
    }
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
    private var compact: Bool { model.preferences.compact }

    var body: some View {
        Group {
            if model.expanded { WorkspaceView(model: model) }
            else { shelf }
        }
        .localized()
        .tint(Palette.accent)
    }

    private var shelf: some View {
        VStack(spacing: 0) {
            ResizeHandle { height in
                model.preferences.panelHeight = height
                model.preferencesChanged()
            }.frame(height: 16)
                .help(L("Glissez pour ajuster la hauteur"))
            toolbar
            if let error = model.storageError {
                Label(L("Sauvegarde indisponible : \(error)"), systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.red).padding(.horizontal, 24).padding(.bottom, 8)
            }
            HStack(spacing: 0) {
                if model.filtered.isEmpty { emptyState.frame(maxWidth: .infinity, maxHeight: .infinity) }
                else { cards }
                if model.queueVisible { queueSidebar }
            }
            footer
        }
        .background(.ultraThinMaterial)
        .background(scheme == .dark ? Color(red: 0.08, green: 0.075, blue: 0.105).opacity(0.25) : Color(red: 0.97, green: 0.965, blue: 0.985).opacity(0.3))
        .clipShape(RoundedRectangle(cornerRadius: 24))
        .overlay(RoundedRectangle(cornerRadius: 24).strokeBorder(.white.opacity(scheme == .dark ? 0.14 : 0.7), lineWidth: 1))
        .tint(Palette.accent)
        .onChange(of: model.searchFocused) { _, value in searchFocus = value }
        .onChange(of: searchFocus) { _, value in model.searchFocused = value }
    }

    private var toolbar: some View {
        GeometryReader { geometry in
            HStack(spacing: 14) {
            HStack(spacing: 8) {
                EncoreMark()
                Text("encore").font(.system(size: 21, weight: .semibold)).tracking(-0.5)
            }.frame(width: 115, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: 11) {
                searchBar.frame(width: geometry.size.width > 1500 ? 300 : 180)
                filterMenu
                toolButton("rectangle.stack", help: L("File de collage"), active: model.queueVisible) { withAnimation(.easeInOut(duration: 0.18)) { model.queueVisible.toggle() } }
                toolButton("gearshape", help: L("Réglages · ⌘,")) { model.showSettings?() }
                toolButton("xmark", help: L("Fermer · Échap")) { model.dismissPanel?() }
            }
            }
            collectionsBar.frame(width: max(160, geometry.size.width - (geometry.size.width > 1500 ? 980 : 720))).position(x: geometry.size.width / 2, y: 21)
        }.frame(height: 42).padding(.horizontal, 25).padding(.top, 1).padding(.bottom, 15)
    }

    private var collectionsBar: some View {
        GeometryReader { geometry in
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 5) {
                    boardButton(L("Historique"), symbol: "clock.arrow.circlepath", id: "history", color: Palette.accent)
                    boardButton(L("Favoris"), symbol: "star", id: "favorites", color: .orange)
                    ForEach(model.library.collections) { collection in
                        boardButton(collection.name, symbol: "circle.fill", id: collection.id.uuidString, color: Palette.collection[collection.colorIndex % Palette.collection.count])
                            .contextMenu {
                                Button(role: .destructive) { model.deleteCollection(collection) } label: { Label(L("Supprimer la collection"), systemImage: "trash") }
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
                        .buttonStyle(.plain).help(L("Créer une collection · ⌘⇧N")).accessibilityLabel(L("Nouvelle collection"))
                }.frame(minWidth: geometry.size.width)
            }
        }.frame(height: 36)
    }

    private var filterMenu: some View {
        Menu {
                Button(L("Tous les types")) { model.kind = nil }
                ForEach(ClipKind.allCases) { kind in
                    Button { model.kind = kind } label: { Label(kind.title, systemImage: kind.symbol) }
                }
                Divider()
                Button(L("Toutes les applications")) { model.source = nil }
                ForEach(model.sources, id: \.0) { source in Button(source.1) { model.source = source.0 } }
            } label: {
                Image(systemName: "line.3.horizontal.decrease").font(.system(size: 15)).foregroundStyle(model.kind != nil || model.source != nil ? Palette.accent : .secondary)
            }.menuStyle(.borderlessButton).frame(width: 22).help(L("Filtrer par type ou application")).accessibilityLabel(L("Filtres"))
    }

    private func boardButton(_ title: String, symbol: String, id: String, color: Color) -> some View {
        Button { model.board = id } label: {
            HStack(spacing: 6) {
                Image(systemName: symbol).font(.system(size: symbol == "circle.fill" ? 7 : 12, weight: .medium)).foregroundStyle(model.board == id ? color : .secondary)
                Text(title).font(.system(size: 13, weight: model.board == id ? .semibold : .medium)).lineLimit(1)
            }
            .padding(.horizontal, 12).frame(height: 35)
            .background(model.board == id ? color.opacity(0.13) : .clear, in: Capsule())
            .overlay(Capsule().strokeBorder(model.board == id ? color.opacity(0.23) : .clear))
        }.buttonStyle(.plain).accessibilityAddTraits(model.board == id ? [.isSelected] : [])
    }

    private var searchBar: some View {
        HStack(spacing: 7) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(L("Rechercher…"), text: $model.query).textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocus)
                .accessibilityLabel(L("Rechercher dans l’historique"))
            if model.query.isEmpty { Text("⌘F").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary) }
            else { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel(L("Effacer la recherche")) }
        }.padding(.horizontal, 12).frame(height: 38)
            .background(.primary.opacity(0.065), in: RoundedRectangle(cornerRadius: 11))
            .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(searchFocus ? Palette.accent.opacity(0.8) : .primary.opacity(0.13)))
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
            Text(model.library.clips.isEmpty ? L("Vos idées, à portée de clavier.") : L("Aucun élément trouvé")).font(.system(size: 21, weight: .semibold, design: .rounded))
            Text(model.library.clips.isEmpty ? L("Copiez un texte, un lien ou une image. Retrouvez-le ici avec \(model.shortcutStatus).") : L("Essayez un autre mot ou retirez les filtres.")).font(.system(size: 12)).foregroundStyle(.secondary)
            if model.kind != nil || model.source != nil || !model.query.isEmpty {
                Button(L("Effacer les filtres")) { model.kind = nil; model.source = nil; model.query = "" }.buttonStyle(.bordered)
            } else if !model.accessibilityGranted {
                Button(L("Activer le collage direct")) { model.requestAccessibility() }.buttonStyle(.borderedProminent).padding(.top, 6)
                Text(L("Sans autorisation, Encore recopie les éléments ; vous les collez avec ⌘V.")).font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }.padding(24)
    }

    private var footer: some View {
        HStack(spacing: 12) {
            Circle().fill(model.preferences.captureEnabled ? Color.green : Color.orange).frame(width: 5, height: 5)
            Text(model.preferences.captureEnabled ? L("\(model.filtered.count) élément(s)") : L("Capture en pause")).font(.system(size: 12, weight: .medium))
            if let kind = model.kind {
                Button { model.kind = nil } label: { Label(kind.title, systemImage: "xmark.circle.fill").font(.system(size: 12)) }.buttonStyle(.plain).foregroundStyle(Palette.accent)
            }
            if let source = model.source {
                Button { model.source = nil } label: { Label(model.sources.first { $0.0 == source }?.1 ?? source, systemImage: "xmark.circle.fill").font(.system(size: 12)) }.buttonStyle(.plain).foregroundStyle(Palette.accent)
            }
            if !model.status.isEmpty { Text(model.status).font(.system(size: 12)).foregroundStyle(Palette.accent).lineLimit(1) }
            Spacer(minLength: 4)
            if model.status.isEmpty {
                hint("← →", L("naviguer"))
                Button { model.expanded = true } label: { hint("↑", L("explorer")) }.buttonStyle(.plain)
                hint("↓", L("réduire"))
                hint("↩", L("coller"))
                hint("⇧↩", L("texte brut"))
                hint(L("espace"), L("aperçu"))
            }
            Text(L("100 % local")).font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary).padding(.leading, 4)
        }.foregroundStyle(.secondary).padding(.horizontal, 25).frame(height: 42)
            .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.06)).frame(height: 1).padding(.horizontal, 24) }
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(Localization.keys(keys)).font(.system(size: 12, weight: .semibold)).foregroundStyle(.primary).padding(.horizontal, 6).padding(.vertical, 4).background(.primary.opacity(0.09), in: RoundedRectangle(cornerRadius: 5))
            Text(label).font(.system(size: 12)).foregroundStyle(.primary.opacity(0.8))
        }
    }

    private func toolButton(_ symbol: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(active ? Palette.accent : .primary.opacity(0.8)).frame(width: 29, height: 34) }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private var queueSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("File de collage"), systemImage: "rectangle.stack").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(model.queue.count)").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.accent)
            }
            Text(model.collecting ? L("Copiez pour ajouter · ⌘V pour coller") : L("Ajoutez des cartes, puis activez la file.")).font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 7) {
                    ForEach(Array(model.queue.enumerated()), id: \.element) { index, id in
                        if let clip = model.library.clips.first(where: { $0.id == id }) {
                            HStack(spacing: 7) {
                                Text("\(index + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
                                Text(clip.displayTitle).font(.system(size: 12)).lineLimit(1)
                                Spacer(minLength: 0)
                                Button { model.queue.removeAll { $0 == id } } label: { Image(systemName: "xmark").font(.system(size: 11)) }.buttonStyle(.plain).accessibilityLabel(L("Retirer de la file"))
                            }.padding(9).background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            HStack {
                Button(model.collecting ? L("Arrêter") : L("Activer")) { model.toggleCollecting() }.buttonStyle(.borderedProminent).controlSize(.small)
                Spacer()
                Button { model.queue.reverse() } label: { Image(systemName: "arrow.up.arrow.down") }.buttonStyle(.plain).help(L("Inverser l’ordre"))
                Button { model.queue = []; model.collecting = false } label: { Image(systemName: "trash") }.buttonStyle(.plain).help(L("Vider la file"))
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
    private var scale: Double { model.preferences.cardScale }
    private var typeTitle: String {
        guard clip.kind == .file, let name = clip.fileNames.first else { return clip.kind.title }
        let ext = (name as NSString).pathExtension
        if ext.lowercased() == "pdf" { return "PDF" }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) { return "Image" }
        return clip.kind.title
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 9) {
                VStack(alignment: .leading, spacing: 3) {
                    Text(typeTitle).font(.system(size: 14 * scale, weight: .semibold))
                    Text(model.relativeAge(clip.firstCopyDate)).font(.system(size: max(11, 12 * scale), weight: .medium)).foregroundStyle(.white.opacity(0.9)).lineLimit(1)
                }
                Spacer(minLength: 2)
                if clip.favorite { Image(systemName: "star.fill").font(.system(size: 12 * scale)).foregroundStyle(.yellow) }
                sourceIcon.frame(width: 40 * scale, height: 40 * scale).help(clip.sourceName)
            }.foregroundStyle(.white).padding(.horizontal, 12).frame(height: 48 * scale)
                .background(LinearGradient(colors: [accent, accent.opacity(0.8)], startPoint: .topLeading, endPoint: .bottomTrailing).overlay(.black.opacity(0.24)))
            cardContent.frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            HStack {
                if index < 9 { Text("⌘\(index + 1)").font(.system(size: 12 * scale, weight: .semibold)).foregroundStyle(selected ? Palette.accent : .secondary) }
                Image(systemName: model.retentionDecision(for: clip).expiresAt == nil ? "infinity" : "clock").font(.system(size: 12 * scale)).foregroundStyle(.secondary).help(model.retentionSummary(for: clip))
                Spacer()
                Text(model.remainingRetention(for: clip)).font(.system(size: max(11, 12 * scale))).foregroundStyle(.secondary).lineLimit(1).help(model.retentionSummary(for: clip))
            }.padding(.horizontal, 14).frame(height: 32 * scale)
        }
        .frame(width: (compact ? 200 : 258) * scale)
        .background(scheme == .dark ? Color(red: 0.14, green: 0.14, blue: 0.18) : .white)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).strokeBorder(selected ? Palette.accent : .primary.opacity(hovered ? 0.18 : 0.07), lineWidth: selected ? 2.5 : 1))
        .shadow(color: selected ? Palette.accent.opacity(0.2) : .clear, radius: 7)
        .shadow(color: .black.opacity(scheme == .dark ? 0.14 : 0.05), radius: 6, y: 3)
        .contentShape(RoundedRectangle(cornerRadius: 16))
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { model.select(clip.id); model.paste([clip], plain: NSEvent.modifierFlags.contains(.shift)) }
        .onTapGesture { model.select(clip.id, modifiers: NSEvent.modifierFlags) }
        .contextMenu { contextActions }
        .onDrag { itemProvider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("\(clip.kind.title), \(clip.displayTitle), \(clip.sourceName)"))
        .accessibilityValue(selected ? L("Sélectionné") : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.select(clip.id) }
    }

    @ViewBuilder private var sourceIcon: some View {
        Image(nsImage: ApplicationCatalog.app(clip.sourceBundle).icon).resizable().interpolation(.high)
    }

    @ViewBuilder private var cardContent: some View {
        switch clip.kind {
        case .color:
            ZStack {
                Palette.color(clip.text)
                VStack(spacing: 7) {
                    Text(clip.text.uppercased()).font(.system(size: 30 * scale, weight: .medium, design: .rounded)).tracking(-1)
                    Text("HEX").font(.system(size: 12 * scale)).opacity(0.75)
                }.foregroundStyle(Palette.swatchText(clip.text, dark: scheme == .dark))
            }.clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 8)
        case .link:
            VStack(alignment: .leading, spacing: 0) {
                ZStack(alignment: .bottomLeading) {
                    LinearGradient(colors: [accent.opacity(0.9), Color(red: 0.08, green: 0.28, blue: 0.35)], startPoint: .topTrailing, endPoint: .bottomLeading)
                    Image(systemName: "globe.europe.africa.fill").font(.system(size: 82 * scale, weight: .ultraLight)).foregroundStyle(.white.opacity(0.13)).frame(maxWidth: .infinity, alignment: .trailing).padding(8)
                    Image(systemName: "arrow.up.right").font(.system(size: 25 * scale, weight: .light)).foregroundStyle(.white).padding(16)
                }
                VStack(alignment: .leading, spacing: 4) {
                    Text(clip.displayTitle).font(.system(size: 14 * scale, weight: .semibold)).lineLimit(1)
                    Text(URL(string: clip.text)?.path.removingPercentEncoding ?? clip.text).font(.system(size: 12 * scale)).foregroundStyle(.secondary).lineLimit(2)
                }.padding(12).frame(maxWidth: .infinity, alignment: .leading)
            }.background(accent.opacity(0.04)).clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 8)
        case .image:
            if let image = model.image(for: clip) {
                GeometryReader { geometry in Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
            } else { Image(systemName: "photo").font(.system(size: 36)).foregroundStyle(.secondary) }
        case .file:
            VStack(spacing: 0) {
                FilePreview(previews: model.filePreviews, clip: clip, urls: model.fileURLs(for: clip))
                HStack {
                    Text(clip.displayTitle).font(.system(size: 12 * scale, weight: .medium)).lineLimit(2)
                    if clip.fileNames.count > 1 { Text("+\(clip.fileNames.count - 1)").font(.system(size: 12 * scale, weight: .semibold)).foregroundStyle(.secondary) }
                }.padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .code:
            VStack(alignment: .leading, spacing: 8) {
                if !clip.title.isEmpty { Text(clip.title).font(.system(size: 12 * scale, weight: .semibold)) }
                Text(highlightedCode(clip.text)).font(.system(size: (compact ? 12 : 13) * scale, design: .monospaced)).lineSpacing(4).lineLimit(compact ? 7 : 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }.padding(13).background(Palette.accent.opacity(0.045)).clipShape(RoundedRectangle(cornerRadius: 9)).padding(.horizontal, 8)
        case .text:
            if let rich = model.richText(for: clip) {
                RichTextPreview(text: rich, scale: scale)
            } else {
                VStack(alignment: .leading, spacing: 7) {
                if !clip.title.isEmpty { Text(clip.title).font(.system(size: 14 * scale, weight: .semibold)).lineLimit(1) }
                Text(String(clip.text.prefix(3000))).font(.system(size: (compact ? 13 : 15) * scale)).lineSpacing(5).lineLimit(compact ? 7 : 14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                }.padding(15).background(accent.opacity(scheme == .dark ? 0.055 : 0.035))
            }
        }
    }

    @ViewBuilder private var contextActions: some View {
        if let file = model.fileURLs(for: clip).first {
            Button { NSWorkspace.shared.open(file) } label: { Label(L("Ouvrir"), systemImage: "arrow.up.forward.app") }.keyboardShortcut("o")
            ShareLink(item: file) { Label(L("Partager"), systemImage: "square.and.arrow.up") }
            Divider()
        } else if clip.kind == .link, let url = URL(string: clip.text) {
            Button { NSWorkspace.shared.open(url) } label: { Label(L("Ouvrir le lien"), systemImage: "arrow.up.forward.app") }.keyboardShortcut("o")
            ShareLink(item: url) { Label(L("Partager"), systemImage: "square.and.arrow.up") }
            Divider()
        }
        Button { model.paste(model.library.clips.filter { ids.contains($0.id) }) } label: { Label(L("Coller"), systemImage: "doc.on.clipboard") }.keyboardShortcut(.return, modifiers: [])
        Button { model.paste(model.library.clips.filter { ids.contains($0.id) }, plain: true) } label: { Label(L("Coller en texte brut"), systemImage: "text.alignleft") }.keyboardShortcut(.return, modifiers: .shift)
        Button { model.paste(model.library.clips.filter { ids.contains($0.id) }, copyOnly: true) } label: { Label(L("Copier"), systemImage: "doc.on.doc") }.keyboardShortcut("c")
        Divider()
        Button { model.toggleFavorite(ids) } label: { Label(clip.favorite ? L("Retirer des favoris") : L("Ajouter aux favoris"), systemImage: clip.favorite ? "star.slash" : "star") }
        Menu {
            ForEach(model.library.collections) { collection in
                Button { model.assignCollection(collection.id, ids: ids) } label: {
                    Label(collection.name, systemImage: clip.collectionIDs.contains(collection.id) ? "checkmark" : "folder")
                }
            }
            Divider()
            Button { model.createCollection() } label: { Label(L("Nouvelle collection…"), systemImage: "folder.badge.plus") }
        } label: { Label(L("Collections"), systemImage: "folder") }
        Button { model.enqueue(model.filtered.filter { ids.contains($0.id) }.map(\.id)) } label: { Label(L("Ajouter à la file"), systemImage: "text.badge.plus") }
        Divider()
        Button { model.inspector = clip } label: { Label(L("Aperçu et édition"), systemImage: "eye") }.keyboardShortcut(.space, modifiers: [])
        if !clip.text.isEmpty {
            Menu { ForEach(TextAction.allCases) { action in Button(action.title) { model.transform(action, clip: clip) } } } label: { Label(L("Transformer une copie"), systemImage: "wand.and.stars") }
        }
        if clip.kind == .image {
            Button { model.recognize(clip.id) } label: { Label(L("Reconnaître le texte"), systemImage: "text.viewfinder") }
            if !clip.recognizedText.isEmpty { Button { model.addText(clip.recognizedText) } label: { Label(L("Créer un texte depuis l’image"), systemImage: "text.badge.plus") } }
        }
        Divider()
        Button(role: .destructive) { model.remove(ids) } label: { Label(L("Supprimer"), systemImage: "trash") }
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
