import SwiftUI
import EncoreCore

/// The library: the shelf grown upwards. Same toolbar and cards, laid out as a grid between filters and a preview.
struct LibraryBody: View {
    @ObservedObject var model: AppModel
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    private var compact: Bool { model.preferences.compact }
    private var scale: Double { model.preferences.cardScale }

    var body: some View {
        HStack(spacing: 0) {
            filters.frame(width: 208)
                .opacity(appeared ? 1 : 0).offset(x: appeared || reduceMotion ? 0 : -16)
            Divider().opacity(0.6)
            grid.frame(maxWidth: .infinity)
            Divider().opacity(0.6)
            LibraryPreview(model: model).frame(width: 372)
                .opacity(appeared ? 1 : 0).offset(x: appeared || reduceMotion ? 0 : 16)
        }
        .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.07)).frame(height: 1) }
        .onAppear { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.34, bounce: 0.1).delay(0.12)) { appeared = true } }
    }

    private var filters: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section(L("Type")) {
                    ChipFlow(spacing: 6) {
                        chip(L("Tous les types"), color: .secondary, selected: model.kind == nil) { model.kind = nil }
                        ForEach(ClipKind.allCases) { kind in
                            chip(kind.title, color: Palette.accent(kind), selected: model.kind == kind) { model.kind = model.kind == kind ? nil : kind }
                        }
                    }
                }
                if !model.sources.isEmpty {
                    section(L("Application")) {
                        LazyVGrid(columns: [GridItem(.adaptive(minimum: 34, maximum: 34), spacing: 6)], alignment: .leading, spacing: 6) {
                            ForEach(model.sources, id: \.0) { source in
                                let selected = model.source == source.0
                                Button { model.source = selected ? nil : source.0 } label: {
                                    Image(nsImage: ApplicationCatalog.app(source.0).icon).resizable().interpolation(.high).frame(width: 22, height: 22)
                                        .frame(width: 34, height: 34)
                                        .background(selected ? Palette.accent.opacity(0.22) : Color.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 8))
                                        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(selected ? Palette.accent : .primary.opacity(0.08)))
                                }.buttonStyle(.plain).help(source.1).accessibilityLabel(source.1).accessibilityAddTraits(selected ? .isSelected : [])
                            }
                        }
                    }
                }
                section(L("Dates")) {
                    Picker(L("Dates"), selection: Binding(get: { dateToken }, set: { setDate($0) })) {
                        Text(L("Aujourd’hui")).tag("today")
                        Text(L("7 jours")).tag("7d")
                        Text(L("30 jours")).tag("30d")
                        Text(L("Toutes les dates")).tag("")
                    }.pickerStyle(.radioGroup).labelsHidden()
                }
                if model.kind != nil || model.source != nil || !model.query.isEmpty {
                    Button(L("Effacer les filtres")) { model.kind = nil; model.source = nil; model.query = "" }.controlSize(.small)
                }
                VStack(alignment: .leading, spacing: 6) {
                    ProgressView(value: min(1, Double(model.totalBytes) / Double(max(1, model.preferences.storageLimitMB * 1_048_576)))).progressViewStyle(.linear).tint(Palette.accent)
                    Text("\(Int64(model.totalBytes).formatted(.byteCount(style: .binary).locale(Localization.locale))) / \((Int64(model.preferences.storageLimitMB) * 1_048_576).formatted(.byteCount(style: .binary).locale(Localization.locale)))").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
                }.padding(.top, 4)
            }.padding(16)
        }
    }

    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title.uppercased(with: Localization.locale)).font(.system(size: 10, weight: .semibold)).tracking(0.6).foregroundStyle(.secondary).accessibilityAddTraits(.isHeader)
            content()
        }
    }

    private func chip(_ title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            HStack(spacing: 5) {
                Circle().fill(color).frame(width: 7, height: 7)
                Text(title).font(.system(size: 12, weight: selected ? .semibold : .regular)).lineLimit(1)
            }.padding(.horizontal, 9).frame(height: 24)
                .background(selected ? Color.primary.opacity(0.14) : .clear, in: Capsule())
                .overlay(Capsule().strokeBorder(.primary.opacity(selected ? 0.2 : 0.1)))
                .contentShape(Capsule())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? .isSelected : [])
    }

    private var dateToken: String {
        model.query.split(separator: " ").first { $0.hasPrefix("date:") }.map { String($0.dropFirst(5)) } ?? ""
    }

    private func setDate(_ value: String) {
        let words = model.query.split(separator: " ").filter { !$0.hasPrefix("date:") }.map(String.init)
        model.query = (words + (value.isEmpty ? [] : ["date:\(value)"])).joined(separator: " ")
    }

    private var grid: some View {
        ScrollViewReader { proxy in
            ScrollView {
                if model.filtered.isEmpty {
                    ContentUnavailableView(L("Aucun élément trouvé"), systemImage: "magnifyingglass", description: Text(L("Essayez un autre mot ou retirez les filtres."))).padding(.top, 80)
                }
                LazyVStack(alignment: .leading, spacing: 14, pinnedViews: [.sectionHeaders]) {
                    ForEach(ClipSection.group(model.filtered, now: model.displayTime)) { section in
                        Section {
                            LazyVGrid(columns: [GridItem(.adaptive(minimum: (compact ? 196 : 236) * scale, maximum: (compact ? 196 : 236) * scale), spacing: 12)], alignment: .leading, spacing: 12) {
                                ForEach(section.items) { item in
                                    ClipCard(model: model, clip: item.clip, index: item.index, compact: compact, height: 232 * scale, namespace: namespace).id(item.clip.id)
                                }
                            }
                        } header: {
                            HStack(spacing: 8) {
                                Text(section.title).font(.system(size: 13, weight: .semibold))
                                Text(Localization.number(section.items.count)).font(.system(size: 12)).foregroundStyle(.secondary)
                            }.padding(.vertical, 6).frame(maxWidth: .infinity, alignment: .leading).background(.bar.opacity(0.0001))
                        }
                    }
                }.padding(16)
            }
            .onChange(of: model.cursor) { _, id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear { if let id = model.cursor { proxy.scrollTo(id, anchor: .center) } }
        }
    }
}

/// Large preview with metadata and actions; the same view floats above the shelf when Space is pressed.
struct LibraryPreview: View {
    @ObservedObject var model: AppModel
    var floating = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if let clip = model.selected {
                HStack(spacing: 10) {
                    Image(nsImage: ApplicationCatalog.app(clip.sourceBundle).icon).resizable().interpolation(.high).frame(width: 30, height: 30)
                    VStack(alignment: .leading, spacing: 1) {
                        Text(clip.typeTitle).font(.system(size: 13, weight: .semibold)).foregroundStyle(Palette.accent(clip.kind, dark: scheme == .dark))
                        Text("\(clip.sourceName) · \(model.relativeAge(clip.firstCopyDate))").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
                    }
                    Spacer()
                    Button { model.toggleFavorite([clip.id]) } label: { Image(systemName: clip.favorite ? "star.fill" : "star").foregroundStyle(clip.favorite ? .yellow : .secondary).frame(width: 28, height: 28) }
                        .buttonStyle(.plain).help(clip.favorite ? L("Retirer des favoris") : L("Ajouter aux favoris")).accessibilityLabel(clip.favorite ? L("Retirer des favoris") : L("Ajouter aux favoris"))
                }
                ClipContent(model: model, clip: clip, large: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.07)))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if !floating {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                        row(L("Première copie"), Localization.date(clip.firstCopyDate))
                        if clip.firstCopiedAt != nil { row(L("Dernière copie"), Localization.date(clip.copiedAt)) }
                        row(L("Expiration"), model.remainingRetention(for: clip))
                        row(L("Taille"), size(of: clip))
                    }.font(.system(size: 12)).monospacedDigit()
                }
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Button { model.paste([clip]) } label: { (Text(L("Coller")) + Text("  ↩").foregroundStyle(.white.opacity(0.7))).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                        Button { model.inspector = clip } label: { Text(L("Éditer")).frame(maxWidth: .infinity) }
                    }
                    GridRow {
                        Button { model.paste([clip], plain: true) } label: { Text(L("Coller en texte brut")).lineLimit(1).frame(maxWidth: .infinity) }.disabled(clip.text.isEmpty)
                        Menu(L("Transformer")) { ForEach(TextAction.allCases) { action in Button(action.title) { model.transform(action, clip: clip) } } }.disabled(clip.text.isEmpty)
                    }
                }.controlSize(floating ? .small : .regular)
            } else {
                ContentUnavailableView(L("Sélectionnez un élément"), systemImage: "rectangle.on.rectangle")
            }
        }.padding(16).frame(maxHeight: .infinity, alignment: .top)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(.secondary)
            Text(value).lineLimit(1).textSelection(.enabled)
        }
    }

    private func size(of clip: Clip) -> String {
        if let bytes = clip.referencedFileBytes { return Localization.bytes(bytes) }
        if [.text, .code, .link].contains(clip.kind) { return L("\(clip.text.count) caractère(s)") }
        return Localization.bytes(Int64(clip.byteCount))
    }
}

/// Wrapping row of chips that reflows with the sidebar width and text length.
struct ChipFlow: Layout {
    var spacing: CGFloat = 6
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(width: proposal.width ?? .infinity, subviews: subviews)
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: rows.last.map { $0.y + $0.height } ?? 0)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        for row in arrange(width: bounds.width, subviews: subviews) {
            for (index, x) in row.items { subviews[index].place(at: CGPoint(x: bounds.minX + x, y: bounds.minY + row.y), proposal: .unspecified) }
        }
    }
    private func arrange(width: CGFloat, subviews: Subviews) -> [(items: [(Int, CGFloat)], y: CGFloat, width: CGFloat, height: CGFloat)] {
        var rows: [(items: [(Int, CGFloat)], y: CGFloat, width: CGFloat, height: CGFloat)] = []
        var x: CGFloat = 0, y: CGFloat = 0, height: CGFloat = 0, items: [(Int, CGFloat)] = []
        for (index, subview) in subviews.enumerated() {
            let size = subview.sizeThatFits(.unspecified)
            if x > 0 && x + size.width > width {
                rows.append((items, y, x - spacing, height)); y += height + spacing; x = 0; height = 0; items = []
            }
            items.append((index, x)); x += size.width + spacing; height = max(height, size.height)
        }
        if !items.isEmpty { rows.append((items, y, x - spacing, height)) }
        return rows
    }
}

/// Floating preview shown above the shelf with Space.
struct QuickLookView: View {
    @ObservedObject var model: AppModel
    @Environment(\.colorScheme) private var scheme
    var body: some View {
        LibraryPreview(model: model, floating: true)
            .background(SurfaceBackground(radius: 14))
            .background(RoundedRectangle(cornerRadius: 14).fill(scheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.3)))
            .clipShape(RoundedRectangle(cornerRadius: 14))
            .overlay(RoundedRectangle(cornerRadius: 14).strokeBorder(.white.opacity(scheme == .dark ? 0.14 : 0.6)))
            .localized()
            .tint(Palette.accent)
    }
}
