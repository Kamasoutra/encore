import Foundation

public struct ClipQuery {
    public var query: String
    public var kind: ClipKind?
    public var source: String?
    public var favorites = false
    public var snippets = false
    public var collectionID: UUID?

    public init(query: String = "", kind: ClipKind? = nil, source: String? = nil, favorites: Bool = false, snippets: Bool = false, collectionID: UUID? = nil) {
        self.query = query; self.kind = kind; self.source = source; self.favorites = favorites; self.snippets = snippets; self.collectionID = collectionID
    }

    public func matches(_ clip: Clip, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let kind, clip.kind != kind { return false }
        if let source, clip.sourceBundle != source { return false }
        if favorites && !clip.favorite { return false }
        if snippets && !clip.snippet { return false }
        if let collectionID, !clip.collectionIDs.contains(collectionID) { return false }
        let haystack = Self.fold("\(clip.name) \(clip.tags.joined(separator: " ")) \(clip.title) \(clip.text) \(clip.recognizedText) \(clip.sourceName) \(clip.fileNames.joined(separator: " "))")
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { token in
            let word = Self.fold(String(token))
            if word.hasPrefix("tag:") { return clip.tags.contains(Self.fold(String(word.dropFirst(4)))) }
            if word.hasPrefix("lang:") {
                let value = String(word.dropFirst(5))
                return clip.language.map { Self.fold($0) == value || CodeLanguage.named(value)?.name == $0 } ?? false
            }
            if word.hasPrefix("app:") { return clip.sourceName.lowercased().contains(word.dropFirst(4)) || clip.sourceBundle.lowercased().contains(word.dropFirst(4)) }
            if word.hasPrefix("type:") {
                let value = String(word.dropFirst(5))
                return clip.kind.searchNames.contains { $0.hasPrefix(value) }
            }
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
            return haystack.contains(word)
        }
    }

    /// Whether the plain words of the query all appear in the clip's name: such matches are listed first.
    public func matchesName(_ clip: Clip) -> Bool {
        let words = query.split(whereSeparator: \.isWhitespace).map { Self.fold(String($0)) }.filter { !$0.contains(":") }
        guard !words.isEmpty, !clip.name.isEmpty else { return false }
        let name = Self.fold(clip.name)
        return words.allSatisfy(name.contains)
    }

    private static func fold(_ text: String) -> String { text.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current) }
}
