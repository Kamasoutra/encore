import SwiftUI
import EncoreCore

/// The library: the shelf grown upwards. Same toolbar and cards, laid out as a grid between filters and a preview.
struct LibraryBody: View {
    @ObservedObject var model: AppModel
    let namespace: Namespace.ID
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var appeared = false
    @State private var day = 0
    @State private var viewport = CGRect.zero
    @State private var revealed: UUID?
    private static let header: CGFloat = 36
    private var compact: Bool { model.preferences.compact }
    private var scale: Double { model.preferences.cardScale }

    var body: some View {
        GeometryReader { geometry in
            // The grid keeps whole columns; the preview takes the width left over.
            let card: Double = (compact ? 196 : 236) * scale
            let room: Double = geometry.size.width - 208 - 372 - 22
            let columns = max(1, Int(room / (card + 12)))
            let gridWidth: Double = Double(columns) * (card + 12) + 20
            HStack(spacing: 0) {
                filters.frame(width: 208)
                    .opacity(appeared ? 1 : 0).offset(x: appeared || reduceMotion ? 0 : -16)
                Divider().opacity(0.6)
                grid.frame(width: gridWidth)
                Divider().opacity(0.6)
                LibraryPreview(model: model).frame(maxWidth: .infinity)
                    .opacity(appeared ? 1 : 0).offset(x: appeared || reduceMotion ? 0 : 16)
            }
            .onAppear { model.libraryColumns = columns }
            .onChange(of: columns) { _, value in model.libraryColumns = value }
        }
        .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.07)).frame(height: 1) }
        .onAppear { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.34, bounce: 0.1).delay(0.12)) { appeared = true } }
    }

    private var filters: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                section(L("Type")) {
                    ChipFlow(spacing: 6) {
                        chip(L("All types"), color: .secondary, selected: model.kind == nil) { model.kind = nil }
                        ForEach(ClipKind.allCases) { kind in
                            chip(kind.title, color: Palette.accent(kind), selected: model.kind == kind) { model.kind = model.kind == kind ? nil : kind }
                        }
                    }
                }
                if !model.sources.isEmpty {
                    section(L("App")) {
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
                        Text(L("Today")).tag("today")
                        Text(L("7 days")).tag("7d")
                        Text(L("30 days")).tag("30d")
                        Text(L("All dates")).tag("")
                    }.pickerStyle(.radioGroup).labelsHidden()
                }
                if model.kind != nil || model.source != nil || !model.query.isEmpty {
                    Button(L("Clear filters")) { model.kind = nil; model.source = nil; model.query = "" }.controlSize(.small)
                }
            }.padding(16)
        }
        .safeAreaInset(edge: .bottom, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                ProgressView(value: min(1, Double(model.totalBytes) / Double(max(1, model.preferences.storageLimitMB * 1_048_576)))).progressViewStyle(.linear).tint(Palette.accent)
                Text("\(Int64(model.totalBytes).formatted(.byteCount(style: .binary).locale(Localization.locale))) / \((Int64(model.preferences.storageLimitMB) * 1_048_576).formatted(.byteCount(style: .binary).locale(Localization.locale)))").font(.system(size: 11)).foregroundStyle(.secondary).monospacedDigit()
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
        let sections = ClipSection.group(model.filtered, now: model.displayTime)
        return ScrollViewReader { proxy in
            ScrollView {
                if model.remoteLoading {
                    ProgressView().controlSize(.small).frame(maxWidth: .infinity).padding(.top, 80)
                } else if model.filtered.isEmpty {
                    ContentUnavailableView(L("No items found"), systemImage: "magnifyingglass", description: Text(L("Try another word or remove the filters."))).padding(.top, 80)
                }
                // One grid for every day: nested lazy grids lose track of positions and break scrolling to the cursor.
                LazyVGrid(columns: Array(repeating: GridItem(.fixed((compact ? 196 : 236) * scale), spacing: 12), count: model.libraryColumns), alignment: .leading, spacing: 12) {
                    ForEach(Array(sections.enumerated()), id: \.element.id) { index, section in
                        Section {
                            ForEach(section.items) { item in
                                ClipCard(model: model, clip: item.clip, index: item.index, compact: compact, height: 232 * scale, namespace: namespace)
                                    .id(item.clip.id)
                            }
                        } header: {
                            dayTitle(section)
                                .background { GeometryReader { geometry in Color.clear.preference(key: DayOffsetKey.self, value: [index: geometry.frame(in: .named("library")).minY]) } }
                        }
                    }
                }.padding(.horizontal, 16).padding(.bottom, 16)
            }
            .coordinateSpace(name: "library")
            // No pinned headers: a background never matches the translucent panel. Cards fade out at the top and the current day floats there.
            .mask {
                VStack(spacing: 0) {
                    Color.clear.frame(height: Self.header)
                    LinearGradient(colors: [.clear, .black], startPoint: .top, endPoint: .bottom).frame(height: 8)
                    Color.black
                }
            }
            .overlay(alignment: .topLeading) {
                if sections.indices.contains(day) { dayTitle(sections[day]).padding(.horizontal, 16).allowsHitTesting(false) }
            }
            .onPreferenceChange(DayOffsetKey.self) { offsets in
                // The current day is the last one whose title went under the top band; lazy titles far above are not measured.
                if let current = offsets.filter({ $0.value <= Self.header }).keys.max() { day = current }
                else if let first = offsets.keys.min() { day = max(0, first - 1) }
            }
            .background { GeometryReader { geometry in Color.clear.onAppear { viewport = geometry.frame(in: .global) }.onChange(of: geometry.frame(in: .global)) { _, frame in viewport = frame } } }
            .onPreferenceChange(CursorFrameKey.self) { card in
                // Lazy grids misjudge scrolls without an anchor: compare a new cursor card with the visible area, below the current day, and scroll only when it leaves it.
                guard let id = model.cursor, id != revealed else { return }
                revealed = id
                let room = viewport.height - card.height
                let anchor: UnitPoint? = if card == .zero || room <= Self.header { .center }
                    else if card.minY < viewport.minY + Self.header { UnitPoint(x: 0.5, y: (Self.header + 12) / room) }
                    else if card.maxY > viewport.maxY { UnitPoint(x: 0.5, y: 1 - 8 / room) }
                    else { nil }
                guard let anchor else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: anchor) }
            }
            .onAppear { if let id = model.cursor { revealed = id; proxy.scrollTo(id, anchor: .center) } }
        }
    }

    private func dayTitle(_ section: ClipSection) -> some View {
        HStack(spacing: 8) {
            Text(section.title).font(.system(size: 13, weight: .semibold))
            Text(Localization.number(section.items.count)).font(.system(size: 12)).foregroundStyle(.secondary)
        }.frame(height: Self.header).frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DayOffsetKey: PreferenceKey {
    static let defaultValue: [Int: CGFloat] = [:]
    static func reduce(value: inout [Int: CGFloat], nextValue: () -> [Int: CGFloat]) { value.merge(nextValue()) { $1 } }
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
                        .buttonStyle(.plain).help(clip.favorite ? L("Remove from favorites") : L("Add to favorites")).accessibilityLabel(clip.favorite ? L("Remove from favorites") : L("Add to favorites"))
                }
                ClipContent(model: model, clip: clip, large: true)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.primary.opacity(0.04), in: RoundedRectangle(cornerRadius: 10))
                    .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(.primary.opacity(0.07)))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                if !floating {
                    Grid(alignment: .leading, horizontalSpacing: 14, verticalSpacing: 5) {
                        row(L("First copied"), Localization.date(clip.firstCopyDate))
                        if clip.firstCopiedAt != nil { row(L("Last copied"), Localization.date(clip.copiedAt)) }
                        row(L("Expires"), model.remainingRetention(for: clip))
                        row(L("Size"), size(of: clip))
                    }.font(.system(size: 12)).monospacedDigit()
                }
                Grid(horizontalSpacing: 8, verticalSpacing: 8) {
                    GridRow {
                        Button { model.paste([clip]) } label: { (Text(L("Paste")) + Text("  ↩").foregroundStyle(.white.opacity(0.7))).frame(maxWidth: .infinity) }.buttonStyle(.borderedProminent)
                        Button { model.inspector = clip } label: { Text(L("Edit")).frame(maxWidth: .infinity) }.disabled(model.remotePeer != nil)
                    }
                    GridRow {
                        Button { model.paste([clip], plain: true) } label: { Text(L("Paste as plain text")).lineLimit(1).frame(maxWidth: .infinity) }.disabled(clip.text.isEmpty)
                        Menu(L("Transform")) { ForEach(TextAction.allCases) { action in Button(action.title) { model.transform(action, clip: clip) } } }.disabled(clip.text.isEmpty || model.remotePeer != nil)
                    }
                }.controlSize(floating ? .small : .regular)
            } else {
                ContentUnavailableView(L("Select an item"), systemImage: "rectangle.on.rectangle")
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
        if [.text, .code, .link].contains(clip.kind) { return L("\(clip.text.count) characters") }
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
