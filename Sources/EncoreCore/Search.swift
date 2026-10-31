import Foundation

public struct ClipQuery {
    /// The words are split and folded once, not for every item: searching 10,000 items did it 10,000 times per key.
    public var query: String { didSet { prepare() } }
    private var words: [String] = []
    /// The kinds each `type:` word stands for, worked out once: their names are translated, and asking per item was slow.
    private var kindsByType: [String: Set<ClipKind>] = [:]
    public var kind: ClipKind?
    public var source: String?
    public var favorites = false
    public var snippets = false
    public var collectionID: UUID?

    public init(query: String = "", kind: ClipKind? = nil, source: String? = nil, favorites: Bool = false, snippets: Bool = false, collectionID: UUID? = nil) {
        self.query = query; self.kind = kind; self.source = source; self.favorites = favorites; self.snippets = snippets; self.collectionID = collectionID
        prepare()
    }

    private mutating func prepare() {
        words = query.split(whereSeparator: \.isWhitespace).map { Self.fold(String($0)) }
        kindsByType = Dictionary(words.filter { $0.hasPrefix("type:") }.map { word in
            let value = String(word.dropFirst(5))
            return (word, Set(ClipKind.allCases.filter { kind in kind.searchNames.contains { $0.hasPrefix(value) } }))
        }, uniquingKeysWith: { first, _ in first })
    }

    /// Whether a plain word appears in the item, ignoring case and accents. Fields are searched one by one,
    /// without building and folding one long text per item.
    private static func contains(_ clip: Clip, _ word: String) -> Bool {
        let options: String.CompareOptions = [.caseInsensitive, .diacriticInsensitive]
        let fields = [clip.name, clip.title, clip.text, clip.recognizedText, clip.sourceName]
        return fields.contains { $0.range(of: word, options: options) != nil }
            || clip.tags.contains { $0.range(of: word, options: options) != nil }
            || clip.fileNames.contains { $0.range(of: word, options: options) != nil }
    }

    public func matches(_ clip: Clip, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let kind, clip.kind != kind { return false }
        if let source, clip.sourceBundle != source { return false }
        if favorites && !clip.favorite { return false }
        if snippets && !clip.snippet { return false }
        if let collectionID, !clip.collectionIDs.contains(collectionID) { return false }
        return words.allSatisfy { word in
            if word.hasPrefix("tag:") { return clip.tags.contains(String(word.dropFirst(4))) }
            if word.hasPrefix("lang:") {
                let value = String(word.dropFirst(5))
                return clip.language.map { Self.fold($0) == value || CodeLanguage.named(value)?.name == $0 } ?? false
            }
            if word.hasPrefix("app:") {
                let value = String(word.dropFirst(4))
                return clip.sourceName.range(of: value, options: .caseInsensitive) != nil || clip.sourceBundle.range(of: value, options: .caseInsensitive) != nil
            }
            if word.hasPrefix("type:") { return kindsByType[word]?.contains(clip.kind) ?? false }
            if word == "date:today" || word == "date:aujourdhui" { return calendar.isDate(clip.copiedAt, inSameDayAs: now) }
            if word == "date:week" {
                guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return false }
                return clip.copiedAt >= week.start && clip.copiedAt < week.end
            }
            if word == "date:7d" || word == "date:30d" { return clip.copiedAt >= now.addingTimeInterval(word == "date:7d" ? -7 * 86_400 : -30 * 86_400) }
            if word.hasPrefix("after:") || word.hasPrefix("before:") {
                let value = String(word.dropFirst(word.hasPrefix("after:") ? 6 : 7))
                let formatter = DateFormatter()
                formatter.calendar = calendar
                formatter.locale = Locale(identifier: "en_US_POSIX")
                formatter.timeZone = calendar.timeZone
                formatter.dateFormat = "yyyy-MM-dd"
                formatter.isLenient = false
                guard let date = formatter.date(from: value) else { return false }
                return word.hasPrefix("after:") ? clip.copiedAt >= date : clip.copiedAt < date
            }
            return Self.contains(clip, word)
        }
    }

    /// Whether the plain words of the query all appear in the clip's name: such matches are listed first.
    public func matchesName(_ clip: Clip) -> Bool {
        let plain = words.filter { !$0.contains(":") }
        guard !plain.isEmpty, !clip.name.isEmpty else { return false }
        return plain.allSatisfy { clip.name.range(of: $0, options: [.caseInsensitive, .diacriticInsensitive]) != nil }
    }

    private static func fold(_ text: String) -> String { text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
}
