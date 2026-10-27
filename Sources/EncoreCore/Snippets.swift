import Foundation

extension Clip {
    /// Keeps the name, tags and language of an incoming copy of the same content where this item has none.
    public mutating func adoptSnippetDetails(of other: Clip) {
        if name.isEmpty { name = String(other.name.prefix(100)) }
        tags = Array((tags + other.tags.filter { !tags.contains($0) }).prefix(12))
        if language == nil { language = other.language }
    }

    /// Favorites are grouped by language for code, then by their first tag.
    public var snippetGroup: String {
        if let language, !language.isEmpty { return language }
        return tags.sorted().first.map { "#\($0)" } ?? ""
    }
}

public enum CodeLanguage {
    public static let common = ["Bash", "C", "C#", "C++", "CSS", "Elixir", "Go", "HTML", "Java", "JavaScript", "JSON", "Kotlin", "Markdown", "PHP", "Python", "Ruby", "Rust", "SQL", "Swift", "TypeScript", "YAML"]
}

/// Placeholders in a snippet: {{name}} asks for a value before pasting, {{date}}, {{time}} and {{clipboard}} fill themselves,
/// {{cursor}} marks where the insertion point goes after pasting.
public struct SnippetTemplate: Equatable, Sendable {
    public static let builtIns: Set<String> = ["date", "time", "clipboard", "cursor"]
    // NSRegularExpression rather than Swift regex literals, which need macOS 13.
    private static let pattern = try! NSRegularExpression(pattern: #"\{\{\s*([\p{L}\p{N}_][\p{L}\p{N}_\- ]{0,39}?)\s*\}\}"#)

    public let text: String
    /// Each placeholder with the range it covers and the field name inside.
    private let matches: [(range: Range<String.Index>, field: String)]

    public init?(_ text: String) {
        let found = Self.pattern.matches(in: text, range: NSRange(text.startIndex..., in: text)).compactMap { match -> (Range<String.Index>, String)? in
            guard let range = Range(match.range, in: text), let field = Range(match.range(at: 1), in: text) else { return nil }
            return (range, String(text[field]))
        }
        guard !found.isEmpty else { return nil }
        self.text = text
        matches = found
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.text == rhs.text }

    /// Names the user must fill in, in order of first appearance.
    public var fields: [String] {
        var seen = Set<String>()
        return matches.map(\.field).filter { !Self.builtIns.contains($0.lowercased()) && seen.insert($0).inserted }
    }

    /// The text to paste, and how many characters follow the cursor mark, if there is one.
    public func render(values: [String: String], clipboard: String, now: Date = Date(), locale: Locale = Localization.locale) -> (text: String, charactersAfterCursor: Int?) {
        var result = ""
        var cursor: Int?
        var position = text.startIndex
        for match in matches {
            result += text[position..<match.range.lowerBound]
            switch match.field.lowercased() {
            case "date": result += now.formatted(Date.FormatStyle(date: .numeric, time: .omitted, locale: locale))
            case "time": result += now.formatted(Date.FormatStyle(date: .omitted, time: .shortened, locale: locale))
            case "clipboard": result += clipboard
            case "cursor": if cursor == nil { cursor = result.count }
            default: result += values[match.field] ?? ""
            }
            position = match.range.upperBound
        }
        result += text[position...]
        return (result, cursor.map { result.count - $0 })
    }
}

/// Snippets as readable JSON, to keep or share without the rest of the history.
public struct SnippetFile: Codable, Equatable, Sendable {
    public struct Entry: Codable, Equatable, Sendable {
        public var name: String
        public var text: String
        public var tags: [String]
        public var language: String?
        public init(name: String, text: String, tags: [String] = [], language: String? = nil) {
            self.name = name; self.text = text; self.tags = tags; self.language = language
        }
    }
    public var version = 1
    public var snippets: [Entry]

    public init(snippets: [Entry]) { self.snippets = snippets }

    /// Favorites with text; images and files stay in the full backup.
    public init(library: Library) {
        snippets = library.clips.filter { $0.favorite && [.text, .code, .link, .color].contains($0.kind) && !$0.text.isEmpty }
            .map { Entry(name: $0.name, text: $0.text, tags: $0.tags, language: $0.language) }
    }

    /// Adds the snippets as favorites. Content already in the library is marked favorite and keeps its own details first.
    public func merged(into original: Library, now: Date = Date()) throws -> (library: Library, payloads: [(UUID, ClipPayload)]) {
        guard version == 1 else { throw CocoaError(.coderReadCorrupt) }
        var library = original
        var payloads: [(UUID, ClipPayload)] = []
        var indices = Dictionary(library.clips.enumerated().map { ($0.element.fingerprint, $0.offset) }, uniquingKeysWith: { first, _ in first })
        for entry in snippets where !entry.text.isEmpty {
            let payload = ClipPayload.text(entry.text)
            guard payload.byteCount <= PasteboardCapture.maxBytes else { throw CocoaError(.coderReadCorrupt) }
            var clip = Clip(fingerprint: payload.fingerprint, kind: .detect(text: entry.text), text: entry.text, copiedAt: now, favorite: true, byteCount: payload.byteCount)
            clip.name = String(entry.name.prefix(100))
            clip.tags = Clip.tags(from: entry.tags.joined(separator: ","))
            clip.language = entry.language.map { String($0.prefix(40)) }
            if let index = indices[payload.fingerprint] {
                library.clips[index].favorite = true
                library.clips[index].adoptSnippetDetails(of: clip)
                continue
            }
            indices[payload.fingerprint] = library.clips.count
            library.clips.append(clip)
            payloads.append((clip.id, payload))
        }
        library.clips.sort { $0.copiedAt > $1.copiedAt }
        return (library, payloads)
    }
}
