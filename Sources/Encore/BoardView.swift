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
    /// Type colours: a light tone that reads on dark cards, a deeper one for light cards.
    static func accent(_ kind: ClipKind, dark: Bool = true) -> Color {
        let (r, g, b): (Double, Double, Double) = switch kind {
        case .text: (0.95, 0.65, 0.40)
        case .code: (0.77, 0.66, 1.0)
        case .link: (0.37, 0.83, 0.77)
        case .color: (1.0, 0.50, 0.65)
        case .image: (0.49, 0.71, 1.0)
        case .file: (0.66, 0.65, 1.0)
        }
        return dark ? Color(red: r, green: g, blue: b) : Color(red: r * 0.62, green: g * 0.6, blue: b * 0.72)
    }
    static func monogram(_ host: String) -> Color {
        let hue = Double(host.unicodeScalars.reduce(UInt32(5381)) { ($0 << 5) &+ $0 &+ $1.value } % 360) / 360
        return Color(hue: hue, saturation: 0.45, brightness: 0.62)
    }
    static func card(_ dark: Bool) -> Color { dark ? Color(red: 0.17, green: 0.17, blue: 0.2).opacity(0.86) : Color.white.opacity(0.92) }
}

struct EncoreMark: View {
    var size: CGFloat = 22
    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: size * 0.2).fill(Palette.accent.opacity(0.35)).frame(width: size * 0.68, height: size * 0.78).rotationEffect(.degrees(-14)).offset(x: -size * 0.12, y: -size * 0.02)
            RoundedRectangle(cornerRadius: size * 0.2).fill(LinearGradient(colors: [Color(red: 0.87, green: 0.8, blue: 1), Palette.accent], startPoint: .topLeading, endPoint: .bottomTrailing)).frame(width: size * 0.68, height: size * 0.78).rotationEffect(.degrees(8)).offset(x: size * 0.1, y: size * 0.04)
            Image(systemName: "arrow.counterclockwise").font(.system(size: size * 0.32, weight: .heavy)).foregroundStyle(.white).rotationEffect(.degrees(8)).offset(x: size * 0.1, y: size * 0.04)
        }.frame(width: size, height: size).accessibilityHidden(true)
    }
}

/// Behind-window blur for the borderless panel; macOS renders it opaque when Reduce Transparency is on.
struct SurfaceBackground: NSViewRepresentable {
    var radius: CGFloat
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .popover; view.blendingMode = .behindWindow; view.state = .active
        view.maskImage = Self.mask(radius)
        return view
    }
    func updateNSView(_ view: NSVisualEffectView, context: Context) {}
    static func mask(_ radius: CGFloat) -> NSImage {
        let size = NSSize(width: radius * 2 + 1, height: radius * 2 + 1)
        let image = NSImage(size: size, flipped: false) { rect in NSColor.black.setFill(); NSBezierPath(roundedRect: rect, xRadius: radius, yRadius: radius).fill(); return true }
        image.capInsets = NSEdgeInsets(top: radius, left: radius, bottom: radius, right: radius)
        image.resizingMode = .stretch
        return image
    }
}

struct ClipSection: Identifiable {
    struct Item: Identifiable { let index: Int; let clip: Clip; var id: UUID { clip.id } }
    let id: String
    let title: String
    var items: [Item]

    /// Day sections, after a first section for the `named` leading items that matched a search by name.
    static func group(_ clips: [Clip], now: Date, named: Int = 0) -> [ClipSection] {
        var calendar = Calendar.current; calendar.locale = Localization.locale
        var sections: [ClipSection] = []
        if named > 0 { sections.append(ClipSection(id: "named", title: L("Snippets"), items: clips.prefix(named).enumerated().map { .init(index: $0.offset, clip: $0.element) })) }
        for (index, clip) in clips.enumerated().dropFirst(named) {
            let date = clip.copiedAt
            let (id, title): (String, String) = if calendar.isDate(date, inSameDayAs: now) { ("today", L("Today")) }
                else if let yesterday = calendar.date(byAdding: .day, value: -1, to: now), calendar.isDate(date, inSameDayAs: yesterday) { ("yesterday", L("Yesterday")) }
                else if let week = calendar.dateInterval(of: .weekOfYear, for: now), week.contains(date) { ("week", L("This week")) }
                else { ("month-\(calendar.component(.year, from: date))-\(calendar.component(.month, from: date))", date.formatted(Date.FormatStyle(locale: Localization.locale).month(.wide).year())) }
            if sections.last?.id == id { sections[sections.count - 1].items.append(.init(index: index, clip: clip)) }
            else { sections.append(ClipSection(id: id, title: title, items: [.init(index: index, clip: clip)])) }
        }
        return sections
    }

    /// Favorites in a section per language or tag, as ordered by the model.
    static func snippets(_ clips: [Clip]) -> [ClipSection] {
        var sections: [ClipSection] = []
        for (index, clip) in clips.enumerated() {
            let group = clip.snippetGroup
            if sections.last?.id == "group:\(group)" { sections[sections.count - 1].items.append(.init(index: index, clip: clip)) }
            else { sections.append(ClipSection(id: "group:\(group)", title: group.isEmpty ? L("No tag") : group, items: [.init(index: index, clip: clip)])) }
        }
        return sections
    }
}

struct BoardView: View {
    @ObservedObject var model: AppModel
    @FocusState private var searchFocus: Bool
    @Environment(\.colorScheme) private var scheme
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var cardSpace
    private var compact: Bool { model.preferences.compact }

    var body: some View {
        Group {
            if model.columnShown { SideColumn(model: model, search: searchBar, openLibrary: { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.34, bounce: 0.12)) { model.expanded = true } }) } else { shelf }
        }
        .background(SurfaceBackground(radius: 20))
        .background(RoundedRectangle(cornerRadius: 20).fill(scheme == .dark ? Color.black.opacity(0.18) : Color.white.opacity(0.25)))
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .overlay(RoundedRectangle(cornerRadius: 20).strokeBorder(.white.opacity(scheme == .dark ? 0.12 : 0.6), lineWidth: 1))
        .overlay { if let form = model.snippetForm { SnippetFormView(model: model, form: form).id(form.id) } }
        .overlay { if let id = model.snippetEditor, let clip = model.boardClips.first(where: { $0.id == id }) { SnippetEditorView(model: model, clip: clip).id(id) } }
        .coordinateSpace(name: "clip-dust")
        .onPreferenceChange(ClipDustFramesKey.self) { model.removalFrames = $0 }
        .onPreferenceChange(ClipDustViewportKey.self) { model.removalViewport = $0 }
        .localized()
        .tint(Palette.accent)
        .onChanged(model.searchFocused) { value in searchFocus = value }
        .onChanged(searchFocus) { value in model.searchFocused = value }
        .onAppear { searchFocus = model.searchFocused }
        .onPreferenceChange(CursorFrameKey.self) { frame in
            model.cursorFrame = frame
            if model.quickLook { model.updateQuickLook?() }
        }
    }

    private var shelf: some View {
        VStack(spacing: 0) {
            Group {
                if model.expanded { Color.clear } else {
                    ResizeHandle(onFinish: { height in
                        model.preferences.panelHeight = height
                        model.preferencesChanged()
                    })
                    .help(L("Drag to adjust shelf height"))
                }
            }.frame(height: 12)
            toolbar
            if let error = model.storageError {
                Label(L("Storage unavailable: \(error)"), systemImage: "exclamationmark.triangle").font(.system(size: 12)).foregroundStyle(.red).padding(.horizontal, 16).padding(.bottom, 8)
            }
            Group {
                if model.expanded {
                    LibraryBody(model: model, namespace: cardSpace)
                        .transition(reduceMotion ? .opacity : .asymmetric(insertion: .opacity.animation(.easeOut(duration: 0.2).delay(0.08)), removal: .opacity.animation(.easeIn(duration: 0.12))))
                } else {
                    HStack(spacing: 0) {
                        if model.filtered.isEmpty { emptyState.frame(maxWidth: .infinity, maxHeight: .infinity) }
                        else { cards }
                        if model.queueVisible { queueSidebar }
                    }
                }
            }.frame(maxHeight: .infinity)
            footer
        }
    }

    private var toolbar: some View {
        HStack(spacing: 16) {
            HStack(spacing: 8) {
                EncoreMark()
                Text("encore").font(.system(size: 15, weight: .semibold)).tracking(-0.2)
                if model.expanded { Text(L("Library")).font(.system(size: 13)).foregroundStyle(.secondary).transition(.opacity) }
            }.frame(maxWidth: .infinity, alignment: .leading)
            collectionsBar.layoutPriority(1)
            HStack(spacing: 4) {
                searchBar.frame(width: 240)
                if !model.expanded { filterMenu }
                toolButton("rectangle.stack", help: L("Paste queue"), active: model.queueVisible) { withAnimation(.easeInOut(duration: 0.18)) { model.queueVisible.toggle() } }
                toolButton("gearshape", help: L("Settings · ⌘,")) { model.showSettings?() }
                toolButton("xmark", help: L("Close · Esc")) { model.dismissPanel?() }
            }.frame(maxWidth: .infinity, alignment: .trailing)
        }.frame(height: 32).padding(.horizontal, 16).padding(.bottom, 8)
    }

    private var collectionsBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 2) {
                boardButton(L("History"), symbol: nil, id: "history", color: Palette.accent)
                boardButton(L("Favorites"), symbol: "star.fill", id: "favorites", color: .orange)
                if model.hasSnippets || model.board == "snippets" { boardButton(L("Snippets"), symbol: "curlybraces", id: "snippets", color: Palette.accent) }
                ForEach(model.library.collections) { collection in
                    boardButton(collection.name, symbol: "circle.fill", id: collection.id.uuidString, color: Palette.collection[collection.colorIndex % Palette.collection.count])
                        .contextMenu {
                            Button(role: .destructive) { model.deleteCollection(collection) } label: { Label(L("Delete collection"), systemImage: "trash") }
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
                ForEach(model.peers) { peer in
                    boardButton(peer.device.name, symbol: "laptopcomputer", id: "peer:\(peer.id)", color: .teal)
                        .opacity(peer.online ? 1 : 0.45).help(peer.online ? L("Online") : L("Offline"))
                }
                Button { model.createCollection() } label: { Image(systemName: "plus").font(.system(size: 12, weight: .semibold)).frame(width: 26, height: 26) }
                    .buttonStyle(.plain).foregroundStyle(.secondary).help(L("Create collection · ⌘⇧N")).accessibilityLabel(L("New collection"))
            }.padding(2).background(.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 8))
        }.frame(maxWidth: 640).fixedSize(horizontal: true, vertical: false)
    }

    private var filterMenu: some View {
        Menu {
            Button(L("All types")) { model.kind = nil }
            ForEach(ClipKind.allCases) { kind in
                Button { model.kind = kind } label: { Label(kind.title, systemImage: kind.symbol) }
            }
            Divider()
            Button(L("All apps")) { model.source = nil }
            ForEach(model.sources, id: \.0) { source in Button(source.1) { model.source = source.0 } }
        } label: {
            Image(systemName: "line.3.horizontal.decrease").font(.system(size: 14)).foregroundStyle(model.kind != nil || model.source != nil ? Palette.accent : .secondary)
        }.menuStyle(.borderlessButton).menuIndicator(.hidden).frame(width: 28, height: 28).help(L("Filter by type or app")).accessibilityLabel(L("Filters"))
    }

    private func boardButton(_ title: String, symbol: String?, id: String, color: Color) -> some View {
        let selected = model.board == id
        return Button { model.board = id } label: {
            HStack(spacing: 6) {
                if let symbol { Image(systemName: symbol).font(.system(size: symbol == "circle.fill" ? 7 : 10, weight: .semibold)).foregroundStyle(color) }
                Text(title).font(.system(size: 13, weight: selected ? .semibold : .regular)).lineLimit(1)
            }
            .foregroundStyle(selected ? .primary : .secondary)
            .padding(.horizontal, 12).frame(height: 26)
            .background(selected ? Color.primary.opacity(0.13) : .clear, in: RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).accessibilityAddTraits(selected ? [.isSelected] : [])
    }

    private var searchBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").font(.system(size: 12, weight: .medium)).foregroundStyle(.secondary)
            TextField(L("Search…"), text: $model.query).textFieldStyle(.plain).font(.system(size: 13)).focused($searchFocus)
                .accessibilityLabel(L("Search history"))
            if model.query.isEmpty { Text(Localization.keys("⌘F")).font(.system(size: 11, weight: .medium)).foregroundStyle(.tertiary) }
            else { Button { model.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain).accessibilityLabel(L("Clear search")) }
        }.padding(.horizontal, 8).frame(height: 28)
            .background(.primary.opacity(0.07), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(searchFocus ? Palette.accent.opacity(0.8) : .primary.opacity(0.08)))
    }

    private var cards: some View {
        ScrollViewReader { proxy in
            ScrollView(.horizontal, showsIndicators: false) {
                LazyHStack(spacing: 12) {
                    ForEach(model.sections) { section in
                        DaySeparator(title: section.title)
                        ForEach(section.items) { item in
                            ClipCard(model: model, clip: item.clip, index: item.index, compact: compact, namespace: cardSpace).id(item.clip.id)
                                .modifier(ClipDustFrame(id: item.clip.id))
                        }
                    }
                }.padding(.horizontal, 16).padding(.top, 8).padding(.bottom, 12)
                    .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.24), value: model.library.clips.map(\.id))
            }
            .background {
                GeometryReader { proxy in Color.clear.preference(key: ClipDustViewportKey.self, value: proxy.frame(in: .named("clip-dust"))) }
            }
            .onChanged(model.cursor) { id in
                guard let id else { return }
                withAnimation(reduceMotion ? nil : .easeOut(duration: 0.15)) { proxy.scrollTo(id, anchor: .center) }
            }
            .onAppear { if let id = model.cursor { proxy.scrollTo(id, anchor: .center) } }
        }
    }

    @ViewBuilder private var emptyState: some View {
        if model.remoteLoading { ProgressView().controlSize(.small) } else { emptyMessage }
    }

    private var emptyMessage: some View {
        VStack(spacing: 10) {
            Image(systemName: model.library.clips.isEmpty ? "doc.on.clipboard" : "magnifyingglass").font(.system(size: 30, weight: .light)).foregroundStyle(Palette.accent).padding(.bottom, 3)
            Text(model.library.clips.isEmpty ? L("Your ideas, a keystroke away.") : L("No items found")).font(.system(size: 19, weight: .semibold, design: .rounded))
            Text(model.library.clips.isEmpty ? L("Copy text, a link, or an image. Find it here with \(model.shortcutStatus).") : L("Try another word or remove the filters.")).font(.system(size: 12)).foregroundStyle(.secondary)
            if model.kind != nil || model.source != nil || !model.query.isEmpty {
                Button(L("Clear filters")) { model.kind = nil; model.source = nil; model.query = "" }.buttonStyle(.bordered)
            } else if !model.accessibilityGranted {
                Button(L("Enable direct paste")) { model.requestAccessibility() }.buttonStyle(.borderedProminent).padding(.top, 6)
                Text(L("Without access, Encore copies items for you to paste with ⌘V.")).font(.system(size: 12)).foregroundStyle(.tertiary)
            }
        }.padding(24)
    }

    private var footer: some View {
        HStack(spacing: 14) {
            Circle().fill(model.preferences.captureEnabled ? Color.green : Color.orange).frame(width: 6, height: 6)
            Text(model.preferences.captureEnabled ? L("\(model.filtered.count) items") : L("Capture paused")).font(.system(size: 11, weight: .medium)).monospacedDigit()
            pasteSwitch
            layoutSwitch
            if model.preferences.pasteDirectly && !model.accessibilityGranted {
                // Without Accessibility, Return can only copy: say so where the user looks.
                Button { model.requestAccessibility() } label: {
                    Label(L("Enable direct paste"), systemImage: "exclamationmark.triangle.fill").font(.system(size: 11, weight: .semibold))
                        .padding(.horizontal, 8).padding(.vertical, 3).background(.orange.opacity(0.18), in: Capsule())
                }.buttonStyle(.plain).foregroundStyle(.orange).help(L("Without access, Encore copies items for you to paste with ⌘V."))
            }
            if let kind = model.kind {
                Button { model.kind = nil } label: { Label(kind.title, systemImage: "xmark.circle.fill").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(Palette.accent)
            }
            if let source = model.source {
                Button { model.source = nil } label: { Label(model.sources.first { $0.0 == source }?.1 ?? source, systemImage: "xmark.circle.fill").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(Palette.accent)
            }
            if !model.status.isEmpty { Text(model.status).font(.system(size: 11)).foregroundStyle(Palette.accent).lineLimit(1) }
            Spacer(minLength: 4)
            if model.status.isEmpty {
                if model.expanded {
                    hint("← ↑ ↓ →", L("navigate"))
                    hint("⌘← ⌘→", L("boards"))
                    hint("↩", model.pastesDirectly ? L("paste") : L("copy"))
                    hint("⌘E", L("Edit"))
                    hint("⌘R", L("rename"))
                    hint("⌘S", L("snippet"))
                    hint("⌘F", L("search"))
                    hint("⌘D", L("favorite"))
                    hint("⌘⌫", L("delete"))
                    Button { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.34, bounce: 0.12)) { model.expanded = false } } label: { hint(L("hold ↓"), L("reduce")) }.buttonStyle(.plain)
                } else {
                    Button { withAnimation(reduceMotion ? .easeOut(duration: 0.15) : .spring(duration: 0.34, bounce: 0.12)) { model.expanded = true } } label: { hint("↑", L("explore")) }.buttonStyle(.plain)
                    hint("⌘← ⌘→", L("boards"))
                    hint("↩", model.pastesDirectly ? L("paste") : L("copy"))
                    hint("⇧↩", L("plain text"))
                    hint(L("space"), L("preview"))
                    hint("⌘R", L("rename"))
                    hint("⌘S", L("snippet"))
                    hint("⌘F", L("search"))
                    hint("⌘D", L("favorite"))
                    hint("⌘⌫", L("delete"))
                }
            }
        }.foregroundStyle(.secondary).padding(.horizontal, 16).frame(height: 34)
            .overlay(alignment: .top) { Rectangle().fill(.primary.opacity(0.07)).frame(height: 1) }
            .onReceive(Timer.publish(every: 1.5, on: .main, in: .common).autoconnect()) { _ in
                if !model.accessibilityGranted && AXIsProcessTrusted() { model.accessibilityGranted = true }
            }
    }

    /// Same symbol as scripts/icon.swift, one weight lighter so it stays crisp at footer size.
    private static let iconArrow: NSImage = {
        let image = NSImage(systemSymbolName: "arrow.uturn.backward", accessibilityDescription: nil)?.withSymbolConfiguration(.init(pointSize: 112, weight: .semibold)) ?? NSImage()
        image.isTemplate = true
        return image
    }()

    /// The shelf, or the compact window that lists the latest copies.
    private var layoutSwitch: some View {
        HStack(spacing: 0) {
            ForEach(["bottom", "compact"], id: \.self) { placement in
                let active = model.preferences.placement == placement
                Button {
                    guard !active else { return }
                    model.preferences.placement = placement
                    model.preferencesChanged()
                    model.expanded = false
                    model.resizePanel?()
                } label: {
                    Label(placement == "bottom" ? L("shelf") : L("compact"), systemImage: placement == "bottom" ? "rectangle.bottomthird.inset.filled" : "rectangle.inset.topright.filled")
                        .font(.system(size: 11, weight: active ? .semibold : .medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(active ? Palette.accent.opacity(0.35) : .clear, in: Capsule())
                        .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.7)))
                }.buttonStyle(.plain)
            }
        }.padding(2).background(.primary.opacity(0.06), in: Capsule())
            .help(L("Shelf or compact window"))
    }

    /// What Return and double-click do, kept in sync with the setting.
    private var pasteSwitch: some View {
        HStack(spacing: 0) {
            // The arrow of the app icon: drawn at icon size and scaled down, since small point sizes use a squarer variant of the symbol.
            Image(nsImage: Self.iconArrow).renderingMode(.template).resizable().scaledToFit().frame(height: 12).rotationEffect(.degrees(7)).foregroundStyle(.primary).padding(.leading, 7).padding(.trailing, 4)
            ForEach([true, false], id: \.self) { direct in
                let active = model.preferences.pasteDirectly == direct
                Button {
                    guard !active else { return }
                    withAnimation(.easeOut(duration: 0.15)) { model.preferences.pasteDirectly = direct }
                    model.preferencesChanged()
                } label: {
                    Label(direct ? L("paste") : L("copy"), systemImage: direct ? "arrow.down.doc" : "doc.on.doc")
                        .font(.system(size: 11, weight: active ? .semibold : .medium))
                        .padding(.horizontal, 7).padding(.vertical, 2)
                        .background(active ? Palette.accent.opacity(0.35) : .clear, in: Capsule())
                        .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.7)))
                }.buttonStyle(.plain)
            }
        }.padding(2).background(.primary.opacity(0.06), in: Capsule())
            .help(L("What Return and double-click do"))
    }

    private func hint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(Localization.keys(keys)).font(.system(size: 11, weight: .semibold)).foregroundStyle(.primary).padding(.horizontal, 5).padding(.vertical, 2).background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.system(size: 11))
        }.help(keys.contains("↩") ? L("↩ is the Return key, also called Enter.") : "")
    }

    private func toolButton(_ symbol: String, help: String, active: Bool = false, action: @escaping () -> Void) -> some View {
        Button(action: action) { Image(systemName: symbol).font(.system(size: 14, weight: .medium)).foregroundStyle(active ? Palette.accent : .secondary).frame(width: 28, height: 28).contentShape(Rectangle()) }.buttonStyle(.plain).help(help).accessibilityLabel(help)
    }

    private var queueSidebar: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Label(L("Paste queue"), systemImage: "rectangle.stack").font(.system(size: 12, weight: .semibold))
                Spacer()
                Text("\(model.queue.count)").font(.system(size: 12, weight: .bold)).foregroundStyle(Palette.accent)
            }
            Text(model.collecting ? L("Copy to collect · ⌘V to paste") : L("Add cards, then enable the queue.")).font(.system(size: 12)).foregroundStyle(.secondary)
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(Array(model.queue.enumerated()), id: \.element) { index, id in
                        if let clip = model.library.clips.first(where: { $0.id == id }) {
                            HStack(spacing: 7) {
                                Text("\(index + 1)").font(.system(size: 12, weight: .semibold)).foregroundStyle(Palette.accent)
                                Text(clip.displayTitle).font(.system(size: 12)).lineLimit(1)
                                Spacer(minLength: 0)
                                Button { model.queue.removeAll { $0 == id } } label: { Image(systemName: "xmark").font(.system(size: 11)) }.buttonStyle(.plain).accessibilityLabel(L("Remove from queue"))
                            }.padding(8).background(.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8))
                        }
                    }
                }
            }
            HStack {
                Button(model.collecting ? L("Stop") : L("Enable")) { model.toggleCollecting() }.buttonStyle(.borderedProminent).controlSize(.small)
                Spacer()
                Button { model.queue.reverse() } label: { Image(systemName: "arrow.up.arrow.down") }.buttonStyle(.plain).help(L("Reverse order"))
                Button { model.queue = []; model.collecting = false } label: { Image(systemName: "trash") }.buttonStyle(.plain).help(L("Clear queue"))
            }
        }.padding(14).frame(width: 235).background(.primary.opacity(0.03)).overlay(alignment: .leading) { Rectangle().fill(.primary.opacity(0.07)).frame(width: 1) }.padding(.bottom, 10)
    }
}

struct DaySeparator: View {
    let title: String
    var body: some View {
        label
            .frame(width: 18)
            .frame(maxHeight: .infinity, alignment: .bottom)
            .overlay(alignment: .leading) { Rectangle().fill(.primary.opacity(0.12)).frame(width: 1) }
            .accessibilityAddTraits(.isHeader)
    }

    @ViewBuilder private var label: some View {
        let text = Text(title.uppercased(with: Localization.locale)).font(.system(size: 10, weight: .semibold)).tracking(0.8).foregroundStyle(.secondary).lineLimit(1).fixedSize()
        if #available(macOS 13, *) {
            VerticalLabel { text.rotationEffect(.degrees(-90)) }
        } else {
            // macOS 12 has no Layout protocol: reserve the turned size from the measured text width.
            let width = ceil(NSAttributedString(string: title.uppercased(with: Localization.locale), attributes: [.font: NSFont.systemFont(ofSize: 10, weight: .semibold), .kern: 0.8]).size().width) + 2
            text.frame(width: width, height: 14).rotationEffect(.degrees(-90)).frame(width: 14, height: width)
        }
    }
}

/// Lays out a rotated label with its turned size, so it can be aligned like any other view.
@available(macOS 13, *)
struct VerticalLabel: Layout {
    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let size = subviews.first?.sizeThatFits(.unspecified) ?? .zero
        return CGSize(width: size.height, height: size.width)
    }
    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        subviews.first?.place(at: CGPoint(x: bounds.midX, y: bounds.midY), anchor: .center, proposal: .unspecified)
    }
}

/// Text is selectable only in the large preview: in cards, a right click must open Encore's menu, not the text menu.
struct Selectable: ViewModifier {
    let enabled: Bool
    func body(content: Content) -> some View {
        if enabled { content.textSelection(.enabled) } else { content.textSelection(.disabled) }
    }
}

struct ClipCard: View {
    // Not observed: a card only redraws when the values it shows change, not on every cursor move.
    // Observing the model made each arrow key rebuild and lay out every visible card, too slow on older Macs.
    let model: AppModel
    let clip: Clip
    let index: Int
    let compact: Bool
    var height: CGFloat? = nil
    var namespace: Namespace.ID? = nil
    private let selected: Bool
    private let cursor: Bool
    private let preferences: Preferences
    private let now: Date
    private let remote: Bool
    private let renaming: Bool
    @Environment(\.colorScheme) private var scheme
    @State private var hovered = false
    private var dark: Bool { scheme == .dark }
    private var scale: Double { preferences.cardScale }

    init(model: AppModel, clip: Clip, index: Int, compact: Bool, height: CGFloat? = nil, namespace: Namespace.ID? = nil) {
        self.model = model; self.clip = clip; self.index = index; self.compact = compact; self.height = height; self.namespace = namespace
        selected = model.selection.contains(clip.id)
        cursor = model.cursor == clip.id
        preferences = model.preferences
        now = model.displayTime
        remote = model.remotePeer != nil
        renaming = model.renamingID == clip.id
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8 * scale) {
                // The type stays visible as an icon once a name replaces it.
                Image(systemName: clip.kind.symbol).font(.system(size: 13 * scale, weight: .semibold)).foregroundStyle(Palette.accent(clip.kind, dark: dark)).frame(width: 16 * scale)
                VStack(alignment: .leading, spacing: 1) {
                    if renaming {
                        CardNameField(model: model, clip: clip, scale: scale).foregroundStyle(Palette.accent(clip.kind, dark: dark))
                    } else {
                        // A given name reads as a title; the type shown by default stays in the type's color, lighter.
                        if clip.name.isEmpty {
                            Text(clip.typeTitle).font(.system(size: 12 * scale, weight: .semibold)).lineLimit(1).foregroundStyle(Palette.accent(clip.kind, dark: dark).opacity(0.8))
                        } else {
                            Text(clip.name).font(.system(size: 12.5 * scale, weight: .bold)).lineLimit(1).foregroundStyle(.primary)
                        }
                    }
                    Text(model.relativeAge(clip.firstCopyDate)).font(.system(size: max(10, 11 * scale))).foregroundStyle(.secondary).lineLimit(1)
                }
                Spacer(minLength: 2)
                if clip.snippet { SnippetBadge(clip: clip, size: 15 * scale) }
                if clip.favorite { Image(systemName: "star.fill").font(.system(size: 12 * scale)).foregroundStyle(.yellow).accessibilityLabel(L("Favorites")) }
                Image(nsImage: ApplicationCatalog.app(clip.sourceBundle).icon).resizable().interpolation(.high).frame(width: 28 * scale, height: 28 * scale).help(clip.sourceName)
            }.padding(.leading, 10).padding(.trailing, 10).frame(height: 42 * scale)
                .background(Palette.accent(clip.kind).opacity(dark ? 0.16 : 0.14))
                .contentShape(Rectangle())
                .onTapGesture { headerClick() }
            ClipContent(model: model, clip: clip, scale: scale, compact: compact).frame(maxWidth: .infinity, maxHeight: .infinity).clipped()
            HStack(spacing: 6) {
                if index < 9 {
                    Text(Localization.keys("⌘\(index + 1)")).font(.system(size: 11 * scale, weight: .medium)).monospacedDigit().foregroundStyle(selected ? .primary : .secondary)
                        .padding(.horizontal, 5).padding(.vertical, 1)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(selected ? Palette.accent : .primary.opacity(0.15)))
                }
                Spacer(minLength: 0)
                retention
            }.padding(.horizontal, 12).frame(height: 28 * scale).help(model.retentionSummary(for: clip))
        }
        .frame(width: (compact ? 196 : 236) * scale, height: height)
        .background(Palette.card(dark))
        .clipShape(RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(selected ? Palette.accent : .primary.opacity(hovered ? 0.2 : 0.08), lineWidth: selected ? 2 : 1))
        // A blurred halo fades smoothly instead of showing a hard-edged ring.
        .background { if selected { RoundedRectangle(cornerRadius: 14).fill(Palette.accent.opacity(dark ? 0.75 : 0.55)).padding(-3).blur(radius: 4) } }
        .shadow(color: .black.opacity(dark ? 0.22 : 0.06), radius: hovered ? 10 : 5, y: hovered ? 4 : 2)
        .modifier(MatchedCard(id: clip.id, namespace: namespace))
        .background { if cursor { GeometryReader { proxy in Color.clear.preference(key: CursorFrameKey.self, value: proxy.frame(in: .global)) } } }
        .contentShape(RoundedRectangle(cornerRadius: 12))
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { model.cancelRename(); model.select(clip.id); model.paste([clip], plain: NSEvent.modifierFlags.contains(.shift)) }
        .onTapGesture { model.select(clip.id, modifiers: NSEvent.modifierFlags) }
        .contextMenu { ClipActions(model: model, clip: clip) }
        .onDrag { itemProvider() }
        .accessibilityElement(children: .combine)
        .accessibilityLabel(L("\(clip.kind.title), \(clip.displayTitle), \(clip.sourceName)"))
        .accessibilityValue(selected ? L("Selected") : "")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { model.select(clip.id); model.paste([clip]) }
    }

    /// The header takes its own clicks, so it tells a double-click from a click that renames a selected card.
    private func headerClick() {
        guard !renaming else { return }
        let flags = NSEvent.modifierFlags
        if NSApp.currentEvent?.clickCount ?? 1 >= 2 {
            model.cancelRename(); model.select(clip.id); model.paste([clip], plain: flags.contains(.shift))
        } else if selected, cursor, model.selection.count == 1, !remote, flags.intersection([.command, .shift]).isEmpty {
            model.scheduleRename(clip.id)
        } else {
            model.select(clip.id, modifiers: flags)
        }
    }

    /// Time left before the clip expires, in orange during its last day.
    @ViewBuilder private var retention: some View {
        if remote {
            Image(systemName: "laptopcomputer").font(.system(size: 11 * scale, weight: .medium)).foregroundStyle(.teal)
        } else if let deadline = model.retentionDecision(for: clip).expiresAt {
            let soon = deadline.timeIntervalSince(now) < 86_400
            Label(model.remainingRetention(for: clip), systemImage: "clock").labelStyle(.titleAndIcon).font(.system(size: 11 * scale, weight: .medium)).foregroundStyle(soon ? AnyShapeStyle(.orange) : AnyShapeStyle(.tertiary)).lineLimit(1)
        } else {
            Image(systemName: "infinity").font(.system(size: 11 * scale, weight: .medium)).foregroundStyle(.tertiary).accessibilityLabel(L("Kept forever"))
        }
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
}

/// Asks for a snippet's {{fields}} over the panel, then pastes the filled-in text.
struct SnippetFormView: View {
    let model: AppModel
    let form: SnippetForm
    @State private var values: [String: String] = [:]
    @FocusState private var focus: String?

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).onTapGesture { model.snippetForm = nil }
            VStack(alignment: .leading, spacing: 10) {
                Text(form.clip.displayTitle).font(.system(size: 15, weight: .semibold)).lineLimit(1)
                ForEach(form.fields, id: \.self) { field in
                    TextField(field, text: Binding(get: { values[field, default: ""] }, set: { values[field] = $0 }))
                        .textFieldStyle(.roundedBorder).focused($focus, equals: field)
                        .onSubmit { advance(from: field) }
                }
                HStack {
                    Spacer()
                    Button(L("Cancel")) { model.snippetForm = nil }
                    Button(L("Paste")) { paste() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(18).frame(width: 360)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        // Focus once the field exists; set during appearance it is ignored.
        .onAppear { DispatchQueue.main.async { focus = form.fields.first } }
    }

    /// Return moves to the next field, and pastes from the last one.
    private func advance(from field: String) {
        if let index = form.fields.firstIndex(of: field), index + 1 < form.fields.count { focus = form.fields[index + 1] } else { paste() }
    }

    private func paste() {
        model.snippetForm = nil
        model.paste([form.clip], plain: form.plain, copyOnly: form.copyOnly, fields: values)
    }
}

struct CursorFrameKey: PreferenceKey {
    static let defaultValue = CGRect.zero
    static func reduce(value: inout CGRect, nextValue: () -> CGRect) { let next = nextValue(); if next != .zero { value = next } }
}

struct MatchedCard: ViewModifier {
    let id: UUID
    let namespace: Namespace.ID?
    func body(content: Content) -> some View {
        if let namespace { content.matchedGeometryEffect(id: id, in: namespace) } else { content }
    }
}

extension Clip {
    var typeTitle: String {
        if let secret { return secret.title }
        guard kind == .file, let name = fileNames.first else { return kind.itemTitle }
        let ext = (name as NSString).pathExtension
        if ext.lowercased() == "pdf" { return "PDF" }
        if let type = UTType(filenameExtension: ext), type.conforms(to: .image) { return ClipKind.image.itemTitle }
        return kind.itemTitle
    }
}

/// The body of a clip, shared by cards and the large preview.
struct ClipContent: View {
    let model: AppModel
    let clip: Clip
    var scale: Double = 1
    var compact = false
    var large = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        switch clip.kind {
        case .color:
            VStack(alignment: .leading, spacing: 2) {
                Spacer(minLength: 0)
                Text(clip.text.uppercased()).font(.system(size: (large ? 40 : 24) * scale, weight: .semibold, design: .rounded)).tracking(-0.5)
                Text("HEX").font(.system(size: 11 * scale)).opacity(0.7)
            }.foregroundStyle(Palette.swatchText(clip.text, dark: scheme == .dark)).padding(12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottomLeading)
                .background(Palette.color(clip.text), in: RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1)))
                .padding(8)
        case .link:
            let url = URL(string: clip.text)
            let host = clip.displayTitle
            VStack(alignment: .leading, spacing: 12 * scale) {
                HStack(spacing: 10) {
                    Text(host.first.map { String($0).uppercased() } ?? "·").font(.system(size: 16 * scale, weight: .bold)).foregroundStyle(.white)
                        .frame(width: 38 * scale, height: 38 * scale).background(Palette.monogram(host), in: Circle())
                    Text(host).font(.system(size: 15 * scale, weight: .semibold)).lineLimit(1)
                }
                Text(url.map { ($0.path.removingPercentEncoding ?? $0.path) + ($0.query.map { "?\($0)" } ?? "") } ?? clip.text)
                    .font(.system(size: 13 * scale)).foregroundStyle(.secondary).lineLimit(large ? nil : 4).modifier(Selectable(enabled: large))
                if large, let url { Button { NSWorkspace.shared.open(url) } label: { Label(L("Open link"), systemImage: "arrow.up.forward.app") } }
            }.padding(14).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        case .image:
            if let image = model.image(for: clip) {
                if large { Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity) }
                else {
                    GeometryReader { geometry in Image(nsImage: image).resizable().scaledToFill().frame(width: geometry.size.width, height: geometry.size.height).clipped() }
                        .overlay(alignment: .bottomLeading) {
                            Text(Self.imageInfo(image, bytes: clip.byteCount)).font(.system(size: 11 * scale, weight: .medium)).foregroundStyle(.white.opacity(0.92)).monospacedDigit()
                                .padding(.horizontal, 12).padding(.top, 18).padding(.bottom, 8).frame(maxWidth: .infinity, alignment: .leading)
                                .background(LinearGradient(colors: [.clear, .black.opacity(0.55)], startPoint: .top, endPoint: .bottom))
                        }
                }
            } else { Image(systemName: "photo").font(.system(size: 36)).foregroundStyle(.secondary).frame(maxWidth: .infinity, maxHeight: .infinity) }
        case .file:
            VStack(spacing: 0) {
                FilePreview(previews: model.filePreviews, clip: clip, urls: model.fileURLs(for: clip), fitContent: large)
                VStack(alignment: .leading, spacing: 2) {
                    HStack(spacing: 4) {
                        Text(clip.displayTitle).font(.system(size: 12 * scale, weight: .semibold)).lineLimit(large ? 3 : 1)
                        if clip.fileNames.count > 1 { Text("+\(clip.fileNames.count - 1)").font(.system(size: 12 * scale, weight: .semibold)).foregroundStyle(.secondary) }
                    }
                    if let bytes = clip.referencedFileBytes { Text(Localization.bytes(bytes)).font(.system(size: 11 * scale)).foregroundStyle(.secondary).monospacedDigit() }
                }.padding(.horizontal, 12).padding(.vertical, 8).frame(maxWidth: .infinity, alignment: .leading)
            }
        case .code:
            ScrollView(large ? .vertical : []) {
                Text(highlightedCode(clip.text)).font(.system(size: (large ? 13 : compact ? 11 : 12) * scale, design: .monospaced)).lineSpacing(3).lineLimit(large ? nil : compact ? 8 : 12)
                    .modifier(Selectable(enabled: large)).frame(maxWidth: .infinity, alignment: .topLeading)
            }.padding(10).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .background(scheme == .dark ? Color.black.opacity(0.3) : Color.primary.opacity(0.05), in: RoundedRectangle(cornerRadius: 8)).padding(8)
        case .text:
            if let rich = model.richText(for: clip) {
                if large { ScrollingRichText(text: rich, scale: 1.15) } else { RichTextPreview(text: rich, scale: scale) }
            } else {
                ScrollView(large ? .vertical : []) {
                    VStack(alignment: .leading, spacing: 6) {
                        if !clip.title.isEmpty { Text(clip.title).font(.system(size: 14 * scale, weight: .semibold)).lineLimit(large ? nil : 1) }
                        Text(String(clip.text.prefix(large ? 20_000 : 3000))).font(.system(size: (large ? 15 : compact ? 13 : 14) * scale)).lineSpacing(3).lineLimit(large ? nil : compact ? 7 : 12)
                            .modifier(Selectable(enabled: large))
                    }.frame(maxWidth: .infinity, alignment: .topLeading)
                }.padding(.horizontal, 14).padding(.vertical, 12).frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            }
        }
    }

    static func imageInfo(_ image: NSImage, bytes: Int) -> String {
        let rep = image.representations.first
        let size = rep.map { "\($0.pixelsWide)×\($0.pixelsHigh)" } ?? "\(Int(image.size.width))×\(Int(image.size.height))"
        return "\(size) · \(Localization.bytes(Int64(bytes)))"
    }

    private func highlightedCode(_ source: String) -> AttributedString {
        var value = AttributedString(String(source.prefix(large ? 20_000 : 3000)))
        value.foregroundColor = scheme == .dark ? Color(red: 0.83, green: 0.84, blue: 0.9) : Color(red: 0.23, green: 0.24, blue: 0.34)
        let keyword = scheme == .dark ? Color(red: 1, green: 0.48, blue: 0.7) : Color(red: 0.68, green: 0.15, blue: 0.5)
        let text = String(value.characters)
        if let regex = try? NSRegularExpression(pattern: "\\b(struct|class|enum|func|let|var|import|return|const|def|true|false|nil|null|if|else|guard|public|private|for|in|while|async|await|function)\\b") {
            for match in regex.matches(in: text, range: NSRange(text.startIndex..., in: text)) {
                if let range = Range(match.range, in: text), let lower = AttributedString.Index(range.lowerBound, within: value), let upper = AttributedString.Index(range.upperBound, within: value) { value[lower..<upper].foregroundColor = keyword }
            }
        }
        return value
    }
}

/// Context menu and action list for one clip or the current selection.
struct ClipActions: View {
    @ObservedObject var model: AppModel
    let clip: Clip
    private var ids: Set<UUID> { model.selection.contains(clip.id) ? model.selection : [clip.id] }

    var body: some View {
        if let file = model.fileURLs(for: clip).first {
            Button { NSWorkspace.shared.open(file) } label: { Label(L("Open"), systemImage: "arrow.up.forward.app") }.keyboardShortcut("o")
            if #available(macOS 13, *) { ShareLink(item: file) { Label(L("Share"), systemImage: "square.and.arrow.up") } }
            Divider()
        } else if clip.kind == .link, let url = URL(string: clip.text) {
            Button { NSWorkspace.shared.open(url) } label: { Label(L("Open link"), systemImage: "arrow.up.forward.app") }.keyboardShortcut("o")
            if #available(macOS 13, *) { ShareLink(item: url) { Label(L("Share"), systemImage: "square.and.arrow.up") } }
            Divider()
        }
        Button { model.paste(model.boardClips.filter { ids.contains($0.id) }) } label: { Label(model.pastesDirectly ? L("Paste") : L("Copy"), systemImage: "doc.on.clipboard") }.keyboardShortcut(.return, modifiers: [])
        Button { model.paste(model.boardClips.filter { ids.contains($0.id) }, plain: true) } label: { Label(model.pastesDirectly ? L("Paste as plain text") : L("Copy as plain text"), systemImage: "text.alignleft") }.keyboardShortcut(.return, modifiers: .shift)
        Button { model.paste(model.boardClips.filter { ids.contains($0.id) }, copyOnly: true) } label: { Label(L("Copy"), systemImage: "doc.on.doc") }.keyboardShortcut("c")
        // Items from another Mac only become editable once pasted into the local history.
        if model.remotePeer == nil { localActions }
    }

    @ViewBuilder private var localActions: some View {
        Divider()
        Button { model.toggleFavorite(ids) } label: { Label(clip.favorite ? L("Remove from favorites") : L("Add to favorites"), systemImage: clip.favorite ? "star.slash" : "star") }.keyboardShortcut("d")
        Button { model.renamingID = nil; model.snippetEditor = clip.id } label: { Label(L("Make a snippet"), systemImage: "curlybraces") }.keyboardShortcut("s")
        if clip.snippet { Button { model.removeSnippets(ids) } label: { Label(L("Remove from snippets"), systemImage: "minus.circle") } }
        Menu {
            ForEach(model.library.collections) { collection in
                Button { model.assignCollection(collection.id, ids: ids) } label: {
                    Label(collection.name, systemImage: clip.collectionIDs.contains(collection.id) ? "checkmark" : "folder")
                }
            }
            Divider()
            Button { model.createCollection() } label: { Label(L("New collection…"), systemImage: "folder.badge.plus") }
        } label: { Label(L("Collections"), systemImage: "folder") }
        Button { model.enqueue(model.filtered.filter { ids.contains($0.id) }.map(\.id)) } label: { Label(L("Add to queue"), systemImage: "text.badge.plus") }
        Divider()
        Button { model.inspector = clip } label: { Label(L("Preview and edit"), systemImage: "eye") }.keyboardShortcut("e")
        if !clip.text.isEmpty {
            Menu { ForEach(TextAction.allCases) { action in Button(action.title) { model.transform(action, clip: clip) } } } label: { Label(L("Transform a copy"), systemImage: "wand.and.stars") }
        }
        if clip.kind == .image {
            Button { model.recognize(clip.id) } label: { Label(L("Recognize text"), systemImage: "text.viewfinder") }
            if !clip.recognizedText.isEmpty { Button { model.addText(clip.recognizedText) } label: { Label(L("Create text from image"), systemImage: "text.badge.plus") } }
        }
        Divider()
        Button(role: .destructive) { model.remove(ids) } label: { Label(L("Delete"), systemImage: "trash") }.keyboardShortcut(.delete)
    }
}

/// Edits a card's name in place: Return or a click elsewhere keeps it, Escape (handled by the panel) drops it.
struct CardNameField: View {
    let model: AppModel
    let clip: Clip
    let scale: Double
    @State private var name = ""
    @FocusState private var focused: Bool

    var body: some View {
        TextField(clip.typeTitle, text: $name)
            .textFieldStyle(.plain).font(.system(size: 12 * scale, weight: .bold))
            .focused($focused)
            .onSubmit { commit() }
            .onChanged(focused) { if !$0 { commit() } }
            .onAppear { name = clip.name; DispatchQueue.main.async { focused = true } }
    }

    private func commit() {
        guard model.renamingID == clip.id else { return }
        model.rename(clip.id, to: name)
    }
}


/// The latest copies in a narrow column on a side of the screen: type to search, ↑ ↓ to choose, Return or a double-click to paste.
struct SideColumn<Search: View>: View {
    @ObservedObject var model: AppModel
    let search: Search
    let openLibrary: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var items: [Clip] { model.filtered }
    private var count: Int { model.preferences.compactCount }
    private var cursorOnFirst: Bool { items.first.map { $0.id == model.cursor } ?? true }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                EncoreMark()
                Text("encore").font(.system(size: 15, weight: .semibold)).tracking(-0.2)
                Spacer()
            }
            .padding(.horizontal, 4)
            // The whole top strip, out to the window's edges, so a grab just above or beside the title still moves it.
            .overlay(WindowDragArea { model.compactMoved?() }.padding(.horizontal, -12).padding(.top, -12).padding(.bottom, -5).help(L("Drag to move")))
            .overlay(alignment: .trailing) {
                if !model.preferences.captureEnabled { Image(systemName: "pause.circle.fill").foregroundStyle(.orange).help(L("Capture paused")).padding(.trailing, 4) }
            }
            search
            libraryBar
            // ↓ on the last copy shown slides the list up by one row; the wheel scrolls it too.
            ScrollViewReader { proxy in
                ScrollView(showsIndicators: false) {
                    LazyVStack(spacing: SideRow.spacing) {
                        ForEach(Array(items.enumerated()), id: \.element.id) { index, clip in
                            SideRow(model: model, clip: clip, index: index).id(clip.id)
                                .modifier(ClipDustFrame(id: clip.id))
                        }
                    }
                }
                .frame(height: CGFloat(count) * SideRow.height + CGFloat(count - 1) * SideRow.spacing)
                .background {
                    GeometryReader { proxy in Color.clear.preference(key: ClipDustViewportKey.self, value: proxy.frame(in: .named("clip-dust"))) }
                }
                .overlay {
                    if items.isEmpty {
                        Text(model.query.isEmpty ? L("Copy text, a link, or an image. Find it here with \(model.shortcutStatus).") : L("Try another word or remove the filters."))
                            .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center)
                    }
                }
                .onChanged(model.cursor) { id in
                    guard let id else { return }
                    withAnimation(reduceMotion ? nil : .easeOut(duration: 0.16)) { proxy.scrollTo(id) }
                }
            }
            .animation(reduceMotion ? .easeOut(duration: 0.12) : .easeInOut(duration: 0.24), value: items.map(\.id))
            Spacer(minLength: 0)
            // Same order as the shelf footer: the switches, then the hints.
            HStack(spacing: 10) {
                iconSwitch(model.preferences.pasteDirectly, on: ("arrow.down.doc", L("paste")), off: ("doc.on.doc", L("copy"))) { value in
                    model.preferences.pasteDirectly = value; model.preferencesChanged()
                }.help(L("What Return and double-click do"))
                iconSwitch(false, on: ("rectangle.bottomthird.inset.filled", L("shelf")), off: ("rectangle.inset.topright.filled", L("compact"))) { shelf in
                    guard shelf else { return }
                    model.preferences.placement = "bottom"; model.preferencesChanged(); model.resizePanel?()
                }.help(L("Shelf or compact window"))
                Spacer(minLength: 4)
                footerHint("↑↓", L("choose"))
                footerHint("↩", model.pastesDirectly ? L("paste") : L("copy"))
            }
        }
        .padding(12)
    }

    /// Above the first copy is the library: ↑ there, or a click, opens it.
    private var libraryBar: some View {
        Button(action: openLibrary) {
            HStack(spacing: 6) {
                Image(systemName: "chevron.up").font(.system(size: 10, weight: .bold))
                Text(L("Library")).font(.system(size: 11.5, weight: .medium))
                Spacer()
                Text(Localization.keys("↑")).font(.system(size: 10.5, weight: .semibold)).padding(.horizontal, 4).padding(.vertical, 1.5)
                    .background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    .opacity(cursorOnFirst ? 1 : 0)
            }
            .foregroundStyle(cursorOnFirst ? AnyShapeStyle(.primary) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 9).frame(height: 26)
            .background(.primary.opacity(cursorOnFirst ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 8))
            .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.1), style: StrokeStyle(lineWidth: 1, dash: [3, 3])))
            .contentShape(Rectangle())
        }.buttonStyle(.plain).help(L("Full library"))
    }

    /// Two explicit icons, the active one highlighted: the compact counterpart of the shelf's text switches.
    private func iconSwitch(_ value: Bool, on: (String, String), off: (String, String), set: @escaping (Bool) -> Void) -> some View {
        HStack(spacing: 0) {
            ForEach([true, false], id: \.self) { option in
                let symbol = option ? on : off
                let active = value == option
                Button { if !active { withAnimation(.easeOut(duration: 0.15)) { set(option) } } } label: {
                    Image(systemName: symbol.0).font(.system(size: 11, weight: .medium)).frame(width: 24, height: 18)
                        .background(active ? Palette.accent.opacity(0.35) : .clear, in: Capsule())
                        .foregroundStyle(active ? AnyShapeStyle(.primary) : AnyShapeStyle(.primary.opacity(0.6)))
                }.buttonStyle(.plain).accessibilityLabel(symbol.1).help(symbol.1)
            }
        }.padding(2).background(.primary.opacity(0.06), in: Capsule())
    }

    private func footerHint(_ keys: String, _ label: String) -> some View {
        HStack(spacing: 4) {
            Text(Localization.keys(keys)).font(.system(size: 10.5, weight: .semibold)).padding(.horizontal, 4).padding(.vertical, 1.5)
                .background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
            Text(label).font(.system(size: 10.5))
        }.foregroundStyle(.secondary)
    }
}

/// Moves the compact window, which has no title bar, drawing it towards the snapping points while it is dragged.
private struct WindowDragArea: NSViewRepresentable {
    let onEnd: () -> Void

    final class DragView: NSView {
        var onEnd: (() -> Void)?

        // The first click on the window moves it too, instead of only making it active.
        override func acceptsFirstMouse(for event: NSEvent?) -> Bool { true }

        override func mouseDown(with event: NSEvent) {
            guard let window else { return }
            let start = NSEvent.mouseLocation, origin = window.frame.origin
            while let next = window.nextEvent(matching: [.leftMouseDragged, .leftMouseUp]), next.type == .leftMouseDragged {
                let mouse = NSEvent.mouseLocation
                var target = NSPoint(x: origin.x + mouse.x - start.x, y: origin.y + mouse.y - start.y)
                if let screen = NSScreen.screens.first(where: { $0.frame.contains(mouse) }) ?? window.screen {
                    target = CompactPlacement.attract(target, size: window.frame.size, in: screen.visibleFrame)
                }
                window.setFrameOrigin(target)
            }
            onEnd?()
        }
    }

    func makeNSView(context: Context) -> DragView { DragView() }
    func updateNSView(_ view: DragView, context: Context) { view.onEnd = onEnd }
}

private struct SideRow: View {
    /// Rows have one height, so the list shows exactly the chosen number of copies.
    static let height = CompactPlacement.rowHeight
    static let spacing = CompactPlacement.rowSpacing
    @ObservedObject var model: AppModel
    let clip: Clip
    let index: Int
    @State private var hovered = false
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        let selected = model.cursor == clip.id
        HStack(spacing: 10) {
            preview
                .frame(width: 42, height: 42).clipShape(RoundedRectangle(cornerRadius: 8))
                .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.primary.opacity(0.08)))
                .overlay(alignment: .bottomTrailing) {
                    if !clip.sourceBundle.isEmpty {
                        Image(nsImage: ApplicationCatalog.app(clip.sourceBundle).icon).resizable().frame(width: 18, height: 18)
                            .shadow(color: .black.opacity(0.25), radius: 1, y: 0.5).offset(x: 5, y: 5)
                    }
                }
            VStack(alignment: .leading, spacing: 3) {
                content
                HStack(spacing: 4) {
                    if clip.favorite { Image(systemName: "star.fill").font(.system(size: 9)).foregroundStyle(.yellow) }
                    Text(clip.name.isEmpty ? clip.sourceName : clip.name).lineLimit(1)
                    Text("·")
                    Text(model.relativeAge(clip.copiedAt)).lineLimit(1).layoutPriority(1)
                }.font(.system(size: 10.5)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if index < 9 {
                Text(Localization.keys("⌘\(index + 1)")).font(.system(size: 10.5, weight: .semibold)).monospacedDigit()
                    .foregroundStyle(selected ? .primary : .tertiary)
                    .padding(.horizontal, 5).padding(.vertical, 2)
                    .background(.primary.opacity(selected ? 0.12 : 0.05), in: RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.horizontal, 9).padding(.vertical, 8)
        .frame(maxWidth: .infinity, minHeight: Self.height, maxHeight: Self.height, alignment: .leading)
        .background(selected ? Palette.accent.opacity(scheme == .dark ? 0.24 : 0.16) : Color.primary.opacity(hovered ? 0.08 : 0.04), in: RoundedRectangle(cornerRadius: 11))
        .overlay(RoundedRectangle(cornerRadius: 11).strokeBorder(selected ? Palette.accent.opacity(0.9) : .clear, lineWidth: 1.5))
        .contentShape(Rectangle())
        .onHover { hovered = $0 }
        .onTapGesture(count: 2) { model.paste([clip]) }
        .onTapGesture { model.select(clip.id) }
        .help(clip.kind == .text ? String(clip.text.prefix(400)) : clip.displayTitle)
    }

    @ViewBuilder private var preview: some View {
        switch clip.kind {
        case .image:
            if let image = model.image(for: clip) { Image(nsImage: image).resizable().scaledToFill() } else { symbol }
        case .color:
            Palette.color(clip.text)
        case .file:
            if let url = model.fileURLs(for: clip).first { Image(nsImage: NSWorkspace.shared.icon(forFile: url.path)).resizable().scaledToFit().padding(4) } else { symbol }
        default:
            symbol
        }
    }

    private var symbol: some View {
        ZStack {
            Color.primary.opacity(0.06)
            Image(systemName: clip.kind.symbol).font(.system(size: 15, weight: .medium)).foregroundStyle(clip.kind == .link ? Palette.accent : .secondary)
        }
    }

    @ViewBuilder private var content: some View {
        switch clip.kind {
        case .link:
            let url = URL(string: clip.text)
            VStack(alignment: .leading, spacing: 1) {
                Text(url?.host?.replacingOccurrences(of: "www.", with: "") ?? clip.text).font(.system(size: 12.5, weight: .semibold)).lineLimit(1)
                Text(url.map { $0.path.removingPercentEncoding ?? $0.path } ?? "").font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1)
            }
        case .code:
            Text(clip.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)).font(.system(size: 11.5, design: .monospaced)).lineLimit(2)
        case .color:
            Text(clip.text.uppercased()).font(.system(size: 12.5, weight: .semibold, design: .rounded)).lineLimit(1)
        case .text:
            Text(clip.name.isEmpty ? String(clip.text.trimmingCharacters(in: .whitespacesAndNewlines).prefix(300)) : clip.name).font(.system(size: 12.5)).lineLimit(2)
        default:
            Text(clip.displayTitle).font(.system(size: 12.5)).lineLimit(2)
        }
    }
}
