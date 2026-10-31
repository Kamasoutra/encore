import CryptoKit
import Foundation
import Security

/// The key that encrypts the history on disk, in the login keychain. It exists only while encryption is on:
/// its presence is what tells encore the history is encrypted, so the setting cannot disagree with the files.
enum HistoryKey {
    /// Tests use their own service, so they never touch the real key.
    static var service = "local.kama.Encore.history"
    private static var query: [String: Any] {
        [kSecClass as String: kSecClassGenericPassword, kSecAttrService as String: service, kSecAttrAccount as String: "history-key"]
    }

    static func read() throws -> SymmetricKey? {
        var item: CFTypeRef?
        let status = SecItemCopyMatching(query.merging([kSecReturnData as String: true]) { $1 } as CFDictionary, &item)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = item as? Data, data.count == 32 else { throw KeychainError(status: status) }
        return SymmetricKey(data: data)
    }

    /// A new random key, stored before any file is encrypted with it.
    static func create() throws -> SymmetricKey {
        let key = SymmetricKey(size: .bits256)
        let data = key.withUnsafeBytes { Data($0) }
        let attributes = query.merging([kSecValueData as String: data, kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlock]) { $1 }
        SecItemDelete(query as CFDictionary)
        let status = SecItemAdd(attributes as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError(status: status) }
        return key
    }

    static func delete() { SecItemDelete(query as CFDictionary) }

    struct KeychainError: LocalizedError {
        let status: OSStatus
        var errorDescription: String? { SecCopyErrorMessageString(status, nil) as String? ?? "\(status)" }
    }
}
