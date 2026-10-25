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
