import Foundation
import CryptoKit

public final class Storage: @unchecked Sendable {
    public let root: URL
    private let queue = DispatchQueue(label: "local.kama.Encore.storage", qos: .utility)
    private let encoder = JSONEncoder()
    private let decoder = JSONDecoder()
    private var failed = false
    private var metadataDate: Date?
    private var lastBackup = Date.distantPast
    /// Library.json is written at most once per `writeDelay`, with the latest state: rewriting a large history on every copy
    /// encoded megabytes each time. New contents are still written at once, and `flush` and `load` write what is pending.
    public var writeDelay: TimeInterval = 1
    private var pendingLibrary: Library?
    private var pendingDeletions: [UUID] = []
    private var writeScheduled = false
    /// Set when the history is encrypted: files are then sealed with ChaCha20-Poly1305 under this key, kept in the keychain.
    /// Files in either form are read, so a history half converted stays readable.
    private var key: SymmetricKey?
    private static let sealedMagic = Data("ENCORE-SEALED-1\n".utf8)
    public var isEncrypted: Bool { queue.sync { key != nil } }
    private var recoveredMessage: String?
    public var recoveryNotice: String? { queue.sync { recoveredMessage } }
    private var errorHandler: (@MainActor @Sendable (String) -> Void)?
    public var onError: (@MainActor @Sendable (String) -> Void)? {
        get { queue.sync { errorHandler } }
        set { queue.sync { errorHandler = newValue } }
    }

    public init(root: URL, key: SymmetricKey? = nil) throws {
        self.root = root
        self.key = key
        try FileManager.default.createDirectory(at: root.appendingPathComponent("Items"), withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: root.path)
    }

    public func load() throws -> Library {
        try queue.sync {
            writePending()
            let url = root.appendingPathComponent("Library.json")
            guard FileManager.default.fileExists(atPath: url.path) else { return Library() }
            do {
                let library = try decodeLibrary(open(Data(contentsOf: url)))
                metadataDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                return library
            } catch {
                let originalError = error
                let backup = root.appendingPathComponent("Library.backup.json")
                guard let data = try? Data(contentsOf: backup), let library = try? decodeLibrary(open(data)) else { throw originalError }
                let recovery = root.appendingPathComponent("Recovery")
                try FileManager.default.createDirectory(at: recovery, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
                let damaged = recovery.appendingPathComponent("Library-damaged-\(UUID().uuidString).json")
                try FileManager.default.copyItem(at: url, to: damaged)
                try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: damaged.path)
                try writeRaw(data, to: url)
                metadataDate = try url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                recoveredMessage = L("Library restored from backup. The damaged file was kept in Recovery.")
                return library
            }
        }
    }

    /// A content waiting to be removed with the next write already reads as gone.
    public func payload(_ id: UUID) -> ClipPayload? {
        queue.sync { pendingDeletions.contains(id) ? nil : try? decoder.decode(ClipPayload.self, from: open(Data(contentsOf: payloadURL(id)))) }
    }

    public func save(_ library: Library, payload: (UUID, ClipPayload)? = nil, deleting: [UUID] = []) {
        save(library, payloads: payload.map { [$0] } ?? [], deleting: deleting)
    }

    public func save(_ library: Library, payloads: [(UUID, ClipPayload)], deleting: [UUID] = []) {
        queue.async { [self] in
            guard !failed else { return }
            do {
                for (id, value) in payloads { try write(encoder.encode(value), to: payloadURL(id)) }
                // A content written again, as by undoing a deletion, must not be removed by the pending write.
                let written = Set(payloads.map(\.0))
                pendingDeletions.removeAll { written.contains($0) }
            } catch {
                fail(error)
                return
            }
            pendingLibrary = library
            pendingDeletions += deleting
            guard !writeScheduled else { return }
            writeScheduled = true
            queue.asyncAfter(deadline: .now() + writeDelay) { [self] in writePending() }
        }
    }

    /// On the storage queue: writes the latest library, after a backup at most once a minute, then removes deleted contents.
    private func writePending() {
        writeScheduled = false
        guard !failed, let library = pendingLibrary else { return }
        let deleting = pendingDeletions
        pendingLibrary = nil; pendingDeletions = []
        do {
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
            fail(error)
        }
    }

    private func fail(_ error: Error) {
        failed = true
        let handler = errorHandler
        DispatchQueue.main.async { handler?(error.localizedDescription) }
    }

    public func flush() { queue.sync { writePending() } }

    /// Encrypts the whole history under `newKey`, or turns it back to plain files with nil: the library, its backup and every content.
    /// Runs on the storage queue; files already in the target form are left as they are.
    public func changeKey(to newKey: SymmetricKey?, library: Library, completion: @escaping @Sendable (Error?) -> Void) {
        queue.async { [self] in
            writePending()
            let previous = key
            do {
                var contents: [(URL, Data)] = []
                let items = (try? FileManager.default.contentsOfDirectory(at: root.appendingPathComponent("Items"), includingPropertiesForKeys: nil)) ?? []
                for url in items where url.pathExtension == "json" { contents.append((url, try open(Data(contentsOf: url)))) }
                let backup = root.appendingPathComponent("Library.backup.json")
                if let data = try? Data(contentsOf: backup), let plain = try? open(data) { contents.append((backup, plain)) }
                key = newKey
                for (url, plain) in contents { try write(plain, to: url) }
                try write(encoder.encode(library), to: root.appendingPathComponent("Library.json"))
                metadataDate = try root.appendingPathComponent("Library.json").resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate
                DispatchQueue.main.async { completion(nil) }
            } catch {
                // Files written so far are readable with either key, which the caller keeps until it knows the result.
                key = previous ?? newKey
                DispatchQueue.main.async { completion(error) }
            }
        }
    }

    public enum StorageError: LocalizedError {
        case locked
        public var errorDescription: String? { L("The history is encrypted, and its key is not in this Mac's keychain.") }
    }

    private func seal(_ data: Data) throws -> Data {
        guard let key else { return data }
        return Self.sealedMagic + (try ChaChaPoly.seal(data, using: key).combined)
    }

    private func open(_ data: Data) throws -> Data {
        guard data.starts(with: Self.sealedMagic) else { return data }
        guard let key else { throw StorageError.locked }
        return try ChaChaPoly.open(ChaChaPoly.SealedBox(combined: data.dropFirst(Self.sealedMagic.count)), using: key)
    }

    private func decodeLibrary(_ data: Data) throws -> Library {
        let library = try decoder.decode(Library.self, from: data)
        guard library.version == 1 else { throw CocoaError(.coderReadCorrupt) }
        return library
    }

    private func payloadURL(_ id: UUID) -> URL { root.appendingPathComponent("Items/\(id.uuidString).json") }
    private func write(_ data: Data, to url: URL) throws { try writeRaw(seal(data), to: url) }

    private func writeRaw(_ data: Data, to url: URL) throws {
        try data.write(to: url, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
    }
}
