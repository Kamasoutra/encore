import Foundation
import Security

public struct PeerSecret: Equatable, Sendable {
    public var device: PeerDevice
    public var key: Data
    public init(device: PeerDevice, key: Data) { self.device = device; self.key = key }
}

public protocol PeerSecretStore: AnyObject, Sendable {
    func load() throws -> [PeerSecret]
    func save(_ secret: PeerSecret) throws
    func remove(_ id: String) throws
}

public final class MemoryPeerSecretStore: PeerSecretStore, @unchecked Sendable {
    private let lock = NSLock()
    private var secrets: [String: PeerSecret] = [:]
    public init() {}
    public func load() throws -> [PeerSecret] { lock.withLock { Array(secrets.values) } }
    public func save(_ secret: PeerSecret) throws { lock.withLock { secrets[secret.device.id] = secret } }
    public func remove(_ id: String) throws { _ = lock.withLock { secrets.removeValue(forKey: id) } }
}

/// Pairing secrets in a file only the user can read.
/// The keychain ties each item to the exact build when the app has no Apple Team ID, so every update asked for the
/// login password and blocked the app until answered. The keychain is now read once, to migrate existing pairings.
public final class FilePeerSecretStore: PeerSecretStore, @unchecked Sendable {
    private struct Entry: Codable { var id: String; var name: String; var key: Data }
    public let url: URL
    private let legacy: PeerSecretStore?
    private let lock = NSLock()

    public init(url: URL, legacy: PeerSecretStore? = nil) { self.url = url; self.legacy = legacy }

    public func load() throws -> [PeerSecret] {
        try lock.withLock {
            if FileManager.default.fileExists(atPath: url.path) { return try read() }
            guard let legacy else { return [] }
            // A failed read (for example a refused prompt) writes nothing, so the migration is tried again next launch.
            let secrets = try legacy.load()
            try write(secrets)
            return secrets
        }
    }

    public func save(_ secret: PeerSecret) throws {
        try lock.withLock {
            var secrets = FileManager.default.fileExists(atPath: url.path) ? try read() : []
            secrets.removeAll { $0.device.id == secret.device.id }
            secrets.append(secret)
            try write(secrets)
        }
    }

    public func remove(_ id: String) throws {
        try lock.withLock {
            guard FileManager.default.fileExists(atPath: url.path) else { return }
            try write(try read().filter { $0.device.id != id })
        }
    }

    private func read() throws -> [PeerSecret] {
        try JSONDecoder().decode([Entry].self, from: Data(contentsOf: url)).map { PeerSecret(device: .init(id: $0.id, name: $0.name), key: $0.key) }
    }

    private func write(_ secrets: [PeerSecret]) throws {
        let data = try JSONEncoder().encode(secrets.map { Entry(id: $0.device.id, name: $0.device.name, key: $0.key) })
        let folder = url.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: folder.path)
        // Created owner-only before the secrets go in, then swapped in place, so they are never readable by others.
        let temporary = folder.appendingPathComponent(".\(url.lastPathComponent)-\(UUID().uuidString)")
        let descriptor = open(temporary.path, O_WRONLY | O_CREAT | O_EXCL, 0o600)
        guard descriptor >= 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        do {
            let handle = FileHandle(fileDescriptor: descriptor, closeOnDealloc: true)
            try handle.write(contentsOf: data)
            try handle.synchronize()
            try handle.close()
            guard rename(temporary.path, url.path) == 0 else { throw POSIXError(POSIXErrorCode(rawValue: errno) ?? .EIO) }
        } catch {
            unlink(temporary.path)
            throw error
        }
    }
}

public final class KeychainPeerSecretStore: PeerSecretStore, @unchecked Sendable {
    public let service: String
    public init(service: String = "local.kama.Encore.peers") { self.service = service }

    public func load() throws -> [PeerSecret] {
        var result: CFTypeRef?
        let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecMatchLimit: kSecMatchLimitAll, kSecReturnAttributes: true] as CFDictionary, &result)
        if status == errSecItemNotFound { return [] }
        guard status == errSecSuccess, let items = result as? [[String: Any]] else { throw Self.error(status) }
        return try items.compactMap { attributes in
            guard let account = attributes[kSecAttrAccount as String] as? String else { return nil }
            var data: CFTypeRef?
            let status = SecItemCopyMatching([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: account, kSecMatchLimit: kSecMatchLimitOne, kSecReturnData: true] as CFDictionary, &data)
            guard status == errSecSuccess, let key = data as? Data else { throw Self.error(status) }
            let name = (attributes[kSecAttrGeneric as String] as? Data).flatMap { String(data: $0, encoding: .utf8) } ?? account
            return PeerSecret(device: .init(id: account, name: name), key: key)
        }
    }

    public func save(_ secret: PeerSecret) throws {
        try remove(secret.device.id)
        let status = SecItemAdd([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: secret.device.id, kSecAttrLabel: "Encore · \(secret.device.name)", kSecAttrGeneric: Data(secret.device.name.utf8), kSecAttrAccessible: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly, kSecValueData: secret.key] as CFDictionary, nil)
        guard status == errSecSuccess else { throw Self.error(status) }
    }

    public func remove(_ id: String) throws {
        let status = SecItemDelete([kSecClass: kSecClassGenericPassword, kSecAttrService: service, kSecAttrAccount: id] as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(status) }
    }

    private static func error(_ status: OSStatus) -> NSError {
        NSError(domain: NSOSStatusErrorDomain, code: Int(status), userInfo: [NSLocalizedDescriptionKey: SecCopyErrorMessageString(status, nil) as String? ?? "\(status)"])
    }
}
