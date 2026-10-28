import SwiftUI
import EncoreCore

/// A language's Seti icon, tinted with its color like VS Code's default file icons.
struct LanguageIcon: View {
    let language: CodeLanguage
    var size: CGFloat = 14

    var body: some View {
        Image(nsImage: Self.image(language.icon)).renderingMode(.template).resizable().interpolation(.high)
            .frame(width: size, height: size).foregroundStyle(language.tint)
            .accessibilityLabel(language.name)
    }

    private static var cache: [String: NSImage] = [:]

    /// Icons ship as PDF, which macOS 12 draws as vectors where it cannot read SVG.
    static func image(_ name: String) -> NSImage {
        if let image = cache[name] { return image }
        let image = FeedbackSounds.resources.url(forResource: name, withExtension: "pdf", subdirectory: "Languages").flatMap(NSImage.init(contentsOf:)) ?? NSImage()
        image.isTemplate = true
        cache[name] = image
        return image
    }
}

extension CodeLanguage {
    var tint: Color {
        Color(.sRGB, red: Double(color >> 16 & 0xFF) / 255, green: Double(color >> 8 & 0xFF) / 255, blue: Double(color & 0xFF) / 255)
    }

    /// Shown before anything is typed, after the detected language.
    static let popular = ["Bash", "JavaScript", "TypeScript", "Python", "SQL", "JSON", "HTML", "CSS", "Swift", "Go", "Rust", "YAML"].compactMap(named)
}

/// Marks a snippet on its card: the language's icon, or a generic one when no language is set.
struct SnippetBadge: View {
    let clip: Clip
    var size: CGFloat = 15

    var body: some View {
        Group {
            if let language = CodeLanguage.named(clip.language) {
                LanguageIcon(language: language, size: size)
            } else {
                Image(systemName: clip.kind == .code ? "chevron.left.forwardslash.chevron.right" : "text.quote")
                    .font(.system(size: size * 0.75, weight: .semibold)).foregroundStyle(Palette.accent).frame(width: size, height: size)
            }
        }.help(L("Snippets")).accessibilityLabel(L("Snippets"))
    }
}

/// Files a card as a snippet from the keyboard: a name, a language picked by typing a few letters, and tags.
/// Return moves from one field to the next and saves from the last one.
struct SnippetEditorView: View {
    let model: AppModel
    let clip: Clip
    @State private var name = ""
    @State private var query = ""
    @State private var language: CodeLanguage?
    @State private var tags = ""
    @FocusState private var focus: Field?

    private enum Field { case name, language, tags }

    private var matches: [CodeLanguage] {
        if query.trimmingCharacters(in: .whitespaces).isEmpty {
            return Array(([language].compactMap { $0 } + CodeLanguage.popular.filter { $0 != language }).prefix(12))
        }
        return Array(CodeLanguage.search(query).prefix(12))
    }

    /// Existing tags that complete the one being typed.
    private var suggestions: [String] {
        let entered = Clip.tags(from: tags)
        let partial = tags.hasSuffix(",") || tags.hasSuffix(" ") ? "" : (tags.split(whereSeparator: { $0 == "," || $0 == " " }).last.map { String($0).lowercased() } ?? "")
        return model.tags.filter { !entered.contains($0) || $0 == partial }.filter { partial.isEmpty || ($0.hasPrefix(partial) && $0 != partial) }.prefix(8).map { $0 }
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.25).onTapGesture { model.snippetEditor = nil }
            VStack(alignment: .leading, spacing: 14) {
                HStack(spacing: 8) {
                    if let language { LanguageIcon(language: language, size: 18) } else { Image(systemName: clip.kind.symbol).font(.system(size: 15, weight: .semibold)).foregroundStyle(Palette.accent(clip.kind)) }
                    Text(L("Make a snippet")).font(.system(size: 15, weight: .semibold))
                    Spacer()
                    Text(clip.displayTitle).font(.system(size: 11)).foregroundStyle(.secondary).lineLimit(1).frame(maxWidth: 180, alignment: .trailing)
                }
                TextField(L("Snippet name"), text: $name).textFieldStyle(.roundedBorder).focused($focus, equals: .name)
                    .onSubmit { focus = .language }
                VStack(alignment: .leading, spacing: 8) {
                    HStack {
                        Text(L("Code language")).font(.system(size: 11, weight: .semibold)).foregroundStyle(.secondary)
                        Spacer()
                        if language != nil {
                            Button { language = nil } label: { Label(L("None"), systemImage: "xmark.circle.fill").font(.system(size: 11)) }.buttonStyle(.plain).foregroundStyle(.secondary)
                        }
                    }
                    TextField(L("Type to filter languages"), text: $query).textFieldStyle(.roundedBorder).focused($focus, equals: .language)
                        .onSubmit {
                            if !query.trimmingCharacters(in: .whitespaces).isEmpty, let first = matches.first { language = first }
                            query = ""
                            focus = .tags
                        }
                    LazyVGrid(columns: [GridItem(.adaptive(minimum: 104), spacing: 6)], alignment: .leading, spacing: 6) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { offset, item in
                            languageChip(item, highlighted: item == language || (offset == 0 && !query.isEmpty))
                        }
                    }
                    if matches.isEmpty { Text(L("No items found")).font(.system(size: 11)).foregroundStyle(.secondary) }
                }
                VStack(alignment: .leading, spacing: 8) {
                    TextField(L("Tags, separated by commas"), text: $tags).textFieldStyle(.roundedBorder).focused($focus, equals: .tags)
                        .onSubmit { save() }
                    if !suggestions.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(suggestions, id: \.self) { tag in
                                Button { complete(tag) } label: {
                                    Text("#\(tag)").font(.system(size: 11, weight: .medium)).padding(.horizontal, 7).padding(.vertical, 3)
                                        .background(.primary.opacity(0.08), in: Capsule())
                                }.buttonStyle(.plain)
                            }
                        }
                    }
                }
                HStack {
                    Text(Localization.keys("↩")).font(.system(size: 11, weight: .semibold)).padding(.horizontal, 5).padding(.vertical, 2).background(.primary.opacity(0.1), in: RoundedRectangle(cornerRadius: 4))
                    Text(L("next")).font(.system(size: 11)).foregroundStyle(.secondary)
                    Spacer()
                    Button(L("Cancel")) { model.snippetEditor = nil }
                    Button(L("Save")) { save() }.buttonStyle(.borderedProminent)
                }
            }
            .padding(18).frame(width: 440)
            .background(.regularMaterial, in: RoundedRectangle(cornerRadius: 14))
            .shadow(color: .black.opacity(0.3), radius: 20, y: 6)
        }
        .clipShape(RoundedRectangle(cornerRadius: 20))
        .onAppear {
            name = clip.name
            tags = clip.tags.joined(separator: ", ")
            language = CodeLanguage.named(clip.language) ?? ([.text, .code].contains(clip.kind) ? CodeLanguage.detect(clip.text) : nil)
            // Focus once the field exists; set during appearance it is ignored.
            DispatchQueue.main.async { focus = .name }
        }
    }

    private func languageChip(_ item: CodeLanguage, highlighted: Bool) -> some View {
        Button {
            language = item
            query = ""
            focus = .tags
        } label: {
            HStack(spacing: 5) {
                LanguageIcon(language: item, size: 14)
                Text(item.name).font(.system(size: 11, weight: highlighted ? .semibold : .regular)).lineLimit(1)
            }
            .padding(.horizontal, 7).padding(.vertical, 4).frame(maxWidth: .infinity, alignment: .leading)
            .background(highlighted ? item.tint.opacity(0.22) : Color.primary.opacity(0.06), in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(highlighted ? item.tint.opacity(0.7) : .clear))
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }.buttonStyle(.plain)
    }

    /// Replaces the tag being typed with the chosen one.
    private func complete(_ tag: String) {
        var parts = tags.split(separator: ",", omittingEmptySubsequences: false).map { $0.trimmingCharacters(in: .whitespaces) }
        if let last = parts.last, !last.isEmpty, tag.hasPrefix(last.lowercased().trimmingCharacters(in: CharacterSet(charactersIn: "#"))) { parts.removeLast() }
        parts = parts.filter { !$0.isEmpty } + [tag]
        tags = parts.joined(separator: ", ") + ", "
        focus = .tags
    }

    private func save() {
        model.updateSnippet(clip.id, name: name, tags: Clip.tags(from: tags), language: language?.name, snippet: true)
        model.snippetEditor = nil
    }
}
