import Foundation

public final class Storage: @unchecked Sendable {
    public let root: URL
    private let queue = DispatchQueue(label: "local.kama.Encore.storage", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var failed = false
    private var errorHandler: (@MainActor @Sendable (String) -> Void)?
    public var onError: (@MainActor @Sendable (String) -> Void)? {
        get { queue.sync { errorHandler } }
        set { queue.sync { errorHandler = newValue } }
    }

    public init(root: URL) throws {
        self.root = root
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Items"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    public func load() throws -> Library {
        try queue.sync {
            let url = root.appendingPathComponent("Library.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return Library() }
            let library = try decoder.decode(Library.self, from: Data(contentsOf: url))
            guard library.version == 1 else { throw CocoaError(.coderReadCorrupt) }
            return library
        }
    }

    public func payload(_ id: UUID) -> ClipPayload? {
        queue.sync { try? decoder.decode(ClipPayload.self, from: Data(contentsOf: payloadURL(id))) }
    }

    public func save(_ library: Library, payload: (UUID, ClipPayload)? = nil, deleting: [UUID] = []) {
        save(library, payloads: payload.map { [$0] } ?? [], deleting: deleting)
    }

    public func save(_ library: Library, payloads: [(UUID, ClipPayload)], deleting: [UUID] = []) {
        queue.async { [self] in
            guard !failed else { return }
            do {
                for (id, value) in payloads { try write(encoder.encode(value), to: payloadURL(id)) }
                try write(encoder.encode(library), to: root.appendingPathComponent("Library.json"))
                for id in deleting { try? FileManager.default.removeItem(at: payloadURL(id)) }
            } catch {
                failed = true
                let handler = errorHandler
                DispatchQueue.main.async { handler?(error.localizedDescription) }
            }
        }
    }

    public func flush() { queue.sync {} }

    private func payloadURL(_ id: UUID) -> URL { root.appendingPathComponent("Items/\(id.uuidString).json") }
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
