import Foundation

public final class Storage: @unchecked Sendable {
    public let root: URL
    private let queue = DispatchQueue(label: "local.kama.Encore.storage", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var failed = false
    private var metadataDate: Date?
    private var lastBackup = Date.distantPast
    private var recoveredMessage: String?
    public var recoveryNotice: String? { queue.sync { recoveredMessage } }
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
            do {
                let library = try decodeLibrary(Data(contentsOf: url))
                metadataDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return library
            } catch {
                let originalError = error
                let backup = root.appendingPathComponent("Library.backup.json")
                guard let data = try? Data(contentsOf: backup), let library = try? decodeLibrary(data) else { throw originalError }
                let recovery = root.appendingPathComponent("Recovery")
                try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let damaged = recovery.appendingPathComponent("Library-damaged-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: url, to: damaged)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: damaged.path)
                try write(data, to: url)
                metadataDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                recoveredMessage = L("Library restored from backup. The damaged file was kept in Recovery.")
                return library
            }
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
                let metadata = root.appendingPathComponent("Library.json")
                let backup = root.appendingPathComponent("Library.backup.json")
                if FileManager.default.fileExists(atPath: metadata.path),
                   metadataDate == (try? metadata.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate),
                   Date().timeIntervalSince(lastBackup) >= 60 || !FileManager.default.fileExists(atPath: backup.path) {
                    let staged = root.appendingPathComponent(".Library-backup-\(UUID())")
                    try FileManager.default.copyItem(at: metadata, to: staged)
                    if FileManager.default.fileExists(atPath: backup.path) { _ = try FileManager.default.replaceItemAt(backup, withItemAt: staged) }
                    else { try FileManager.default.moveItem(at: staged, to: backup) }
                    try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: backup.path)
                    lastBackup = Date()
                }
                try write(encoder.encode(library), to: metadata)
                metadataDate = try metadata.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                for id in deleting { try? FileManager.default.removeItem(at: payloadURL(id)) }
            } catch {
                failed = true
                let handler = errorHandler
                DispatchQueue.main.async { handler?(error.localizedDescription) }
            }
        }
    }

    public func flush() { queue.sync {} }

    private func decodeLibrary(_ data: Data) throws -> Library {
        let library = try decoder.decode(Library.self, from: data)
        guard library.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return library
    }

    private func payloadURL(_ id: UUID) -> URL { root.appendingPathComponent("Items/\(id.uuidString).json") }
    private func write(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
