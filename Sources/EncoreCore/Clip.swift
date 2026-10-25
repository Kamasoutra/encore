import Foundation
import CryptoKit

public enum ClipKind: String, Codable, CaseIterable, Identifiable, Sendable {
    case text, link, image, file, color, code
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .text: L("Texte")
        case .link: L("Liens")
        case .image: L("Images")
        case .file: L("Fichiers")
        case .color: L("Couleurs")
        case .code: L("Code")
        }
    }
    public var symbol: String {
        switch self {
        case .text: "text.alignleft"
        case .link: "link"
        case .image: "photo"
        case .file: "doc"
        case .color: "paintpalette"
        case .code: "chevron.left.forwardslash.chevron.right"
        }
    }
    public var searchNames: [String] {
        let english: String = switch self { case .text: "text"; case .link: "links"; case .image: "images"; case .file: "files"; case .color: "colors"; case .code: "code" }
        let translated = title.folding(options: [.diacriticInsensitive, .caseInsensitive], locale: Localization.locale).filter { !$0.isWhitespace }
        return translated == english ? [english] : [english, translated]
    }
    public static func detect(text: String, hasImage: Bool = false, hasFiles: Bool = false) -> ClipKind {
        if hasFiles { return .file }
        if hasImage { return .image }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: "^#(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{4}|[0-9a-fA-F]{6}|[0-9a-fA-F]{8})$", options: .regularExpression) != nil { return .color }
        if !value.contains(where: \.isWhitespace), let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return .link }
        let patterns = ["^(import |func |class |struct |def |const |let |var |SELECT |#!/)", "[{};]\\s*\\n", "^\\s*[\\[{]\\s*\"", "^\\s*(curl |git |ssh |docker |npm |brew )"]
        if patterns.contains(where: { value.range(of: $0, options: .regularExpression) != nil }) { return .code }
        return .text
    }
}

public struct Clip: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var fingerprint: String
    public var kind: ClipKind
    public var text: String
    public var title: String
    public var sourceName: String
    public var sourceBundle: String
    public var copiedAt: Date
    public var lastUsedAt: Date?
    public var favorite: Bool
    public var collectionIDs: Set<UUID>
    public var recognizedText: String
    public var byteCount: Int
    public var fileNames: [String]
    public var firstCopiedAt: Date?
    public var referencedFileBytes: Int64?

    public init(id: UUID = UUID(), fingerprint: String = "", kind: ClipKind, text: String, title: String = "", sourceName: String = "Encore", sourceBundle: String = "", copiedAt: Date = Date(), favorite: Bool = false, byteCount: Int = 0, fileNames: [String] = [], referencedFileBytes: Int64? = nil) {
        self.id = id
        self.fingerprint = fingerprint
        self.kind = kind
        self.text = text
        self.title = title
        self.sourceName = sourceName
        self.sourceBundle = sourceBundle
        self.copiedAt = copiedAt
        self.favorite = favorite
        self.collectionIDs = []
        self.recognizedText = ""
        self.byteCount = byteCount
        self.fileNames = fileNames
        self.firstCopiedAt = copiedAt
        self.referencedFileBytes = referencedFileBytes
    }

    public var displayTitle: String {
        if !title.isEmpty { return title }
        if kind == .file { return fileNames.first ?? L("Fichier") }
        if kind == .image { return L("Image copiée") }
        if kind == .link, let url = URL(string: text) { return url.host?.replacingOccurrences(of: "www.", with: "") ?? text }
        return String(text.split(separator: "\n").first.map(String.init)?.prefix(100) ?? L("Sans titre").prefix(100))
    }

    public var isProtected: Bool { favorite || !collectionIDs.isEmpty }
    public var firstCopyDate: Date { firstCopiedAt ?? copiedAt }
    public var retentionByteCount: Int64? {
        if kind == .file { return referencedFileBytes.flatMap { $0 >= 0 ? $0 : nil } }
        return Int64(max(0, byteCount))
    }
}

public struct ClipCollection: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var name: String
    public var colorIndex: Int
    public init(id: UUID = UUID(), name: String, colorIndex: Int = 0) {
        self.id = id; self.name = name; self.colorIndex = colorIndex
    }
}

public struct PasteItem: Codable, Equatable, Sendable {
    public var representations: [String: Data]
    public init(_ representations: [String: Data]) { self.representations = representations }
}

public struct ClipPayload: Codable, Equatable, Sendable {
    public var items: [PasteItem]
    public init(items: [PasteItem]) { self.items = items }
    public static func text(_ text: String) -> ClipPayload {
        .init(items: [.init(["public.utf8-plain-text": Data(text.utf8)])])
    }
    public var fingerprint: String {
        var hash = SHA256()
        for item in items {
            for key in item.representations.keys.sorted() where key != "org.nspasteboard.source" {
                let data = item.representations[key]!
                hash.update(data: Data("\(key.utf8.count):\(key):\(data.count):".utf8))
                hash.update(data: data)
            }
            hash.update(data: Data([0]))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public var byteCount: Int { items.reduce(0) { $0 + $1.representations.values.reduce(0) { $0 + $1.count } } }
    public var fileURLs: [URL] {
        items.compactMap { item in
            guard let data = item.representations["public.file-url"], let string = String(data: data, encoding: .utf8), let url = URL(string: string), url.isFileURL else { return nil }
            return (url as NSURL).filePathURL ?? url
        }
    }
}

public struct Library: Codable, Sendable {
    public var version = 1
    public var clips: [Clip] = []
    public var collections: [ClipCollection] = []
    public init() {}

    @discardableResult public mutating func upsert(_ clip: Clip) -> UUID {
        if let index = clips.firstIndex(where: { $0.fingerprint == clip.fingerprint && !clip.fingerprint.isEmpty }) {
            var existing = clips.remove(at: index)
            existing.firstCopiedAt = existing.firstCopyDate
            existing.copiedAt = clip.copiedAt
            existing.referencedFileBytes = clip.referencedFileBytes
            existing.sourceName = clip.sourceName
            existing.sourceBundle = clip.sourceBundle
            clips.insert(existing, at: 0)
            return existing.id
        }
        clips.insert(clip, at: 0)
        return clip.id
    }

    public mutating func prune(days: Int, limit: Int, now: Date = Date()) -> [UUID] {
        prune(policy: RetentionPolicy(fallback: days > 0 ? .init(days, .days) : .forever), limit: limit, now: now)
    }

    public mutating func prune(policy: RetentionPolicy, limit: Int, now: Date = Date()) -> [UUID] {
        var ordinary = 0
        let ordered = clips.sorted { $0.copiedAt > $1.copiedAt }
        let removed = ordered.filter { clip in
            let decision = policy.decision(for: clip)
            if decision.protected { return false }
            if decision.isExpired(at: now) { return true }
            if decision.isRuleManaged { return false }
            ordinary += 1
            return limit > 0 && ordinary > limit
        }.map(\.id)
        let ids = Set(removed)
        guard !ids.isEmpty else { return [] }
        clips.removeAll { ids.contains($0.id) }
        return removed
    }
}

public enum TextAction: String, CaseIterable, Identifiable {
    case trim, uppercase, lowercase, prettyJSON, compactJSON, decodeURL, cleanURL, base64Encode, base64Decode
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .trim: L("Nettoyer les espaces")
        case .uppercase: "MAJUSCULES"
        case .lowercase: "minuscules"
        case .prettyJSON: L("Formater le JSON")
        case .compactJSON: L("Compacter le JSON")
        case .decodeURL: L("Décoder l’URL")
        case .cleanURL: L("Retirer les paramètres de suivi")
        case .base64Encode: L("Encoder en Base64")
        case .base64Decode: L("Décoder le Base64")
        }
    }
    public func apply(_ text: String) throws -> String {
        switch self {
        case .trim: return text.trimmingCharacters(in: .whitespacesAndNewlines)
        case .uppercase: return text.uppercased()
        case .lowercase: return text.lowercased()
        case .prettyJSON, .compactJSON:
            let value = try JSONSerialization.jsonObject(with: Data(text.utf8), options: .fragmentsAllowed)
            return String(decoding: try JSONSerialization.data(withJSONObject: value, options: self == .prettyJSON ? [.prettyPrinted, .sortedKeys, .fragmentsAllowed] : [.sortedKeys, .fragmentsAllowed]), as: UTF8.self)
        case .decodeURL:
            guard let value = text.removingPercentEncoding else { throw TransformError.invalidInput }
            return value
        case .cleanURL:
            guard var url = URLComponents(string: text), ["http", "https"].contains(url.scheme ?? ""), url.host != nil else { throw TransformError.invalidInput }
            url.queryItems = url.queryItems?.filter { !($0.name.lowercased().hasPrefix("utm_") || ["fbclid", "gclid", "mc_cid", "mc_eid"].contains($0.name.lowercased())) }
            if url.queryItems?.isEmpty == true { url.queryItems = nil }
            guard let value = url.string else { throw TransformError.invalidInput }
            return value
        case .base64Encode: return Data(text.utf8).base64EncodedString()
        case .base64Decode:
            guard let data = Data(base64Encoded: text, options: []), let value = String(data: data, encoding: .utf8) else { throw TransformError.invalidInput }
            return value
        }
    }
    public enum TransformError: LocalizedError {
        case invalidInput
        public var errorDescription: String? { L("Le contenu ne correspond pas à cette transformation.") }
    }
}
