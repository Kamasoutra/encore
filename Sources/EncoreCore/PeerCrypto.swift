import Foundation
import CryptoKit

public enum PairingCrypto {
    public static func commitment(_ key: Data) -> Data { Data(SHA256.hash(data: Data("encore-commit-v1".utf8) + key)) }

    public static func transcript(_ a: (device: PeerDevice, key: Data), _ b: (device: PeerDevice, key: Data)) -> Data {
        let ordered = [a, b].sorted { $0.device.id < $1.device.id }
        var hash = SHA256()
        hash.update(data: Data("encore-pair-v1".utf8))
        for part in ordered { hash.update(data: field(Data(part.device.id.utf8)) + field(part.key)) }
        return Data(hash.finalize())
    }

    public static func code(transcript: Data) -> String {
        let digest = Array(SHA256.hash(data: Data("encore-code-v1".utf8) + transcript))
        let value = digest.prefix(4).reduce(UInt32(0)) { $0 << 8 | UInt32($1) } % 1_000_000
        return String(format: "%06u", value)
    }

    public static func secret(privateKey: P256.KeyAgreement.PrivateKey, remoteKey: Data, transcript: Data) throws -> Data {
        let shared = try privateKey.sharedSecretFromKeyAgreement(with: P256.KeyAgreement.PublicKey(x963Representation: remoteKey))
        let key = shared.hkdfDerivedSymmetricKey(using: SHA256.self, salt: transcript, sharedInfo: Data("encore-pair-secret-v1".utf8), outputByteCount: 32)
        return key.withUnsafeBytes { Data($0) }
    }

    static func field(_ data: Data) -> Data {
        var length = UInt32(data.count).bigEndian
        return Data(bytes: &length, count: 4) + data
    }
}

public struct SessionKeys: Sendable {
    public let auth: SymmetricKey
    public let clientToServer: SymmetricKey
    public let serverToClient: SymmetricKey
    public let transcript: Data

    public init(secret: Data, shared: Data, client: PeerHello, server: PeerHello) {
        var hash = SHA256()
        hash.update(data: Data("encore-session-v1".utf8))
        for hello in [client, server] { hash.update(data: PairingCrypto.field(Data(hello.device.id.utf8)) + PairingCrypto.field(hello.nonce) + PairingCrypto.field(hello.key)) }
        transcript = Data(hash.finalize())
        let material = HKDF<SHA256>.deriveKey(inputKeyMaterial: SymmetricKey(data: secret + shared), salt: transcript, info: Data("encore-session-keys-v1".utf8), outputByteCount: 96)
        let bytes = material.withUnsafeBytes { Data($0) }
        auth = SymmetricKey(data: bytes.prefix(32))
        clientToServer = SymmetricKey(data: bytes.dropFirst(32).prefix(32))
        serverToClient = SymmetricKey(data: bytes.suffix(32))
    }

    public func mac(_ role: String) -> Data { Data(HMAC<SHA256>.authenticationCode(for: Data(role.utf8) + transcript, using: auth)) }
    public func verify(_ mac: Data?, role: String) -> Bool {
        guard let mac else { return false }
        return HMAC<SHA256>.isValidAuthenticationCode(mac, authenticating: Data(role.utf8) + transcript, using: auth)
    }
}

public struct SessionCipher: Sendable {
    private let key: SymmetricKey
    private var counter: UInt64 = 0
    public init(key: SymmetricKey) { self.key = key }

    public mutating func seal(_ data: Data) throws -> Data {
        let box = try ChaChaPoly.seal(data, using: key, nonce: nonce())
        counter += 1
        return box.ciphertext + box.tag
    }

    public mutating func open(_ data: Data) throws -> Data {
        guard data.count >= 16 else { throw PeerFailure.authenticationFailed }
        do {
            let box = try ChaChaPoly.SealedBox(nonce: nonce(), ciphertext: data.dropLast(16), tag: data.suffix(16))
            let plain = try ChaChaPoly.open(box, using: key)
            counter += 1
            return plain
        } catch { throw PeerFailure.authenticationFailed }
    }

    private func nonce() throws -> ChaChaPoly.Nonce {
        var value = counter.bigEndian
        return try ChaChaPoly.Nonce(data: Data(count: 4) + Data(bytes: &value, count: 8))
    }
}
