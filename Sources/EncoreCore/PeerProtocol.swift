import Foundation

public enum PeerProtocol {
    public static let version = 1
    public static let serviceType = "_encore._tcp"
    public static let maxFrameBytes = 4 * 1_048_576
    public static let chunkBytes = 1_048_576
    public static let maxListLimit = 200
    public static let previewLength = 300
    public static let thumbnailPixels = 160
}

public struct PeerDevice: Codable, Hashable, Identifiable, Sendable {
    public var id: String
    public var name: String
    public init(id: String, name: String) { self.id = id; self.name = name }
}

public struct ListRequest: Codable, Equatable, Sendable {
    public var query: String?
    public var limit: Int
    public var before: Date?
    public init(query: String? = nil, limit: Int = 50, before: Date? = nil) { self.query = query; self.limit = limit; self.before = before }
}

public struct RemoteClip: Codable, Identifiable, Equatable, Sendable {
    public var id: UUID
    public var kind: ClipKind
    public var title: String
    public var preview: String
    public var byteCount: Int
    public var copiedAt: Date
    public var firstCopiedAt: Date?
    public var sourceName: String
    public var sourceBundle: String
    public var thumbnail: Data?

    public init(_ clip: Clip, thumbnail: Data? = nil) {
        id = clip.id; kind = clip.kind; title = clip.title
        preview = String((clip.text.isEmpty ? clip.recognizedText : clip.text).prefix(PeerProtocol.previewLength))
        byteCount = clip.byteCount; copiedAt = clip.copiedAt; firstCopiedAt = clip.firstCopiedAt
        sourceName = clip.sourceName; sourceBundle = clip.sourceBundle; self.thumbnail = thumbnail
    }
}

public struct PeerHello: Codable, Equatable, Sendable {
    public var device: PeerDevice
    public var nonce: Data
    public var key: Data
    public var mac: Data?
}

public enum PeerFailure: String, Codable, Error, Sendable {
    case unsupportedVersion, unknownPeer, authenticationFailed, pairingRejected, pairingBusy, cancelled, notFound, forbidden, tooLarge, malformed, closed, timeout, unavailable
}

public enum PeerMessage: Codable, Equatable, Sendable {
    case pairRequest(device: PeerDevice, commitment: Data)
    case pairKey(device: PeerDevice, key: Data)
    case pairReveal(key: Data)
    case pairConfirm
    case hello(PeerHello)
    case finish(mac: Data)
    case list(ListRequest)
    case clips([RemoteClip])
    case payload(id: UUID)
    case chunk(index: Int, count: Int, data: Data)
    case error(PeerFailure)
}

public struct PeerEnvelope: Codable, Equatable, Sendable {
    public var v: Int
    public var message: PeerMessage
    public init(_ message: PeerMessage, version: Int = PeerProtocol.version) { v = version; self.message = message }

    public func encoded() throws -> Data {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .millisecondsSince1970
        return try encoder.encode(self)
    }

    public static func decode(_ data: Data) throws -> PeerMessage {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .millisecondsSince1970
        struct Version: Decodable { var v: Int }
        guard let version = try? decoder.decode(Version.self, from: data) else { throw PeerFailure.malformed }
        guard version.v == PeerProtocol.version else { throw PeerFailure.unsupportedVersion }
        guard let envelope = try? decoder.decode(PeerEnvelope.self, from: data) else { throw PeerFailure.malformed }
        return envelope.message
    }
}

public enum PeerFrame {
    public static func encode(_ body: Data, maxLength: Int = PeerProtocol.maxFrameBytes) throws -> Data {
        guard body.count <= maxLength else { throw PeerFailure.tooLarge }
        var length = UInt32(body.count).bigEndian
        return Data(bytes: &length, count: 4) + body
    }
}

public struct FrameDecoder: Sendable {
    public let maxLength: Int
    private var buffer = Data()
    public init(maxLength: Int = PeerProtocol.maxFrameBytes) { self.maxLength = maxLength }

    public mutating func append(_ data: Data) { buffer.append(data) }

    public mutating func next() throws -> Data? {
        guard buffer.count >= 4 else { return nil }
        let start = buffer.startIndex
        let length = buffer[start..<start + 4].reduce(0) { $0 << 8 | Int($1) }
        guard length <= maxLength else { throw PeerFailure.tooLarge }
        guard buffer.count >= 4 + length else { return nil }
        let body = Data(buffer[start + 4..<start + 4 + length])
        buffer = Data(buffer[(start + 4 + length)...])
        return body
    }
}
