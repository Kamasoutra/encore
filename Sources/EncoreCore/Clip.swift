import Foundation
import CryptoKit

public enum ClipKind: String, Codable, CaseIterable, Identifiable {
    case text, link, image, file, color, code
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .text: "Texte"
        case .link: "Liens"
        case .image: "Images"
        case .file: "Fichiers"
        case .color: "Couleurs"
        case .code: "Code"
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
    public static func detect(text: String, hasImage: Bool = false, hasFiles: Bool = false) -> ClipKind {
        if hasFiles { return .file }
        if hasImage { return .image }
        let value = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if value.range(of: "^#[0-9a-fA-F]{3}([0-9a-fA-F]{3})?([0-9a-fA-F]{2})?$", options: .regularExpression) != nil { return .color }
        if !value.contains(where: \.isWhitespace), let url = URL(string: value), ["https", "http"].contains(url.scheme?.lowercased() ?? ""), url.host != nil { return .link }
        let patterns = ["^(import |func |class |struct |def |const |let |var |SELECT |#!/)", "[{};]\\s*\\n", "^\\s*[\\[{]\\s*\"", "^\\s*(curl |git |ssh |docker |npm |brew )"]
        if patterns.contains(where: { value.range(of: $0, options: .regularExpression) != nil }) { return .code }
        return .text
    }
}

public struct Clip: Codable, Identifiable, Equatable {
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

    public init(id: UUID = UUID(), fingerprint: String = "", kind: ClipKind, text: String, title: String = "", sourceName: String = "Encore", sourceBundle: String = "", copiedAt: Date = Date(), favorite: Bool = false, byteCount: Int = 0, fileNames: [String] = []) {
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
    }

    public var displayTitle: String {
        if !title.isEmpty { return title }
        if kind == .file { return fileNames.first ?? "Fichier" }
        if kind == .image { return "Image copiée" }
        if kind == .link, let url = URL(string: text) { return url.host?.replacingOccurrences(of: "www.", with: "") ?? text }
        return String(text.split(separator: "\n").first.map(String.init)?.prefix(100) ?? "Sans titre".prefix(100))
    }

    public var isProtected: Bool { favorite || !collectionIDs.isEmpty }
}

public struct ClipCollection: Codable, Identifiable, Equatable {
    public var id: UUID
    public var name: String
    public var colorIndex: Int
    public init(id: UUID = UUID(), name: String, colorIndex: Int = 0) {
        self.id = id; self.name = name; self.colorIndex = colorIndex
    }
}

public struct PasteItem: Codable, Equatable {
    public var representations: [String: Data]
    public init(_ representations: [String: Data]) { self.representations = representations }
}

public struct ClipPayload: Codable, Equatable {
    public var items: [PasteItem]
    public init(items: [PasteItem]) { self.items = items }
    public static func text(_ text: String) -> ClipPayload {
        .init(items: [.init(["public.utf8-plain-text": Data(text.utf8)])])
    }
    public var fingerprint: String {
        var hash = SHA256()
        for item in items {
            for key in item.representations.keys.sorted() {
                let data = item.representations[key]!
                hash.update(data: Data("\(key.utf8.count):\(key):\(data.count):".utf8))
                hash.update(data: data)
            }
            hash.update(data: Data([0]))
        }
        return hash.finalize().map { String(format: "%02x", $0) }.joined()
    }
    public var byteCount: Int { items.reduce(0) { $0 + $1.representations.values.reduce(0) { $0 + $1.count } } }
}

public struct Library: Codable {
    public var version = 1
    public var clips: [Clip] = []
    public var collections: [ClipCollection] = []
    public init() {}

    @discardableResult public mutating func upsert(_ clip: Clip) -> UUID {
        if let index = clips.firstIndex(where: { $0.fingerprint == clip.fingerprint && !clip.fingerprint.isEmpty }) {
            var existing = clips.remove(at: index)
            existing.copiedAt = clip.copiedAt
            existing.sourceName = clip.sourceName
            existing.sourceBundle = clip.sourceBundle
            clips.insert(existing, at: 0)
            return existing.id
        }
        clips.insert(clip, at: 0)
        return clip.id
    }

    public mutating func prune(days: Int, limit: Int, now: Date = Date()) -> [UUID] {
        let cutoff = now.addingTimeInterval(-Double(days) * 86_400)
        var ordinary = 0
        let removed = clips.filter { clip in
            if clip.isProtected { return false }
            if days > 0 && clip.copiedAt < cutoff { return true }
            ordinary += 1
            return limit > 0 && ordinary > limit
        }.map(\.id)
        let ids = Set(removed)
        clips.removeAll { ids.contains($0.id) }
        return removed
    }
}

public enum TextAction: String, CaseIterable, Identifiable {
    case trim, uppercase, lowercase, prettyJSON, compactJSON, decodeURL, cleanURL, base64Encode, base64Decode
    public var id: String { rawValue }
    public var title: String {
        switch self {
        case .trim: "Nettoyer les espaces"
        case .uppercase: "MAJUSCULES"
        case .lowercase: "minuscules"
        case .prettyJSON: "Formater le JSON"
        case .compactJSON: "Compacter le JSON"
        case .decodeURL: "Décoder l’URL"
        case .cleanURL: "Retirer les paramètres de suivi"
        case .base64Encode: "Encoder en Base64"
        case .base64Decode: "Décoder le Base64"
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
        public var errorDescription: String? { "Le contenu ne correspond pas à cette transformation." }
    }
}
