import Foundation

public struct ClipQuery {
    public var query: String
    public var kind: ClipKind?
    public var source: String?
    public var favorites = false
    public var collectionID: UUID?

    public init(query: String = "", kind: ClipKind? = nil, source: String? = nil, favorites: Bool = false, collectionID: UUID? = nil) {
        self.query = query; self.kind = kind; self.source = source; self.favorites = favorites; self.collectionID = collectionID
    }

    public func matches(_ clip: Clip, now: Date = Date(), calendar: Calendar = .current) -> Bool {
        if let kind, clip.kind != kind { return false }
        if let source, clip.sourceBundle != source { return false }
        if favorites && !clip.favorite { return false }
        if let collectionID, !clip.collectionIDs.contains(collectionID) { return false }
        let haystack = "\(clip.title) \(clip.text) \(clip.recognizedText) \(clip.sourceName) \(clip.fileNames.joined(separator: " "))".folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
        return query.split(whereSeparator: \.isWhitespace).allSatisfy { token in
            let word = String(token).folding(options: [.diacriticInsensitive, .caseInsensitive], locale: .current)
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
}
